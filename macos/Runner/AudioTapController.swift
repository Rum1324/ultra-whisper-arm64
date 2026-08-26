import AVFoundation
import AppKit
import CoreAudio
import Foundation
import ScreenCaptureKit

/// ScreenCaptureKit fallback for system audio.
///
/// This used to carry a note saying Core Audio process taps return nothing but
/// digital silence on this machine, under every configuration tried. That was
/// wrong, and it cost real time — a tap capturing a 440 Hz tone was verified
/// working on 2026-08-23, in a standalone testbed on this same hardware.
///
/// The cause was settled the same day by reading the TCC database directly:
///
///     sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
///       "select service, client, auth_value from access
///        where client like '%ultrawhisper%';"
///
/// `com.ultrawhisper.ultrawhisper` had a `kTCCServiceMicrophone` row and **no
/// `kTCCServiceAudioCapture` row at all** — while the testbed's
/// `com.sakot.audiocaptureTest` had one, which is the entire difference between
/// the two. Audio Recording and Microphone are separate TCC services; holding
/// the mic grant says nothing about taps. Worse, the rows that did exist were
/// written while the app was ad-hoc signed, so their `csreq` is a list of
/// cdhashes that every single rebuild invalidates, and System Settings keeps
/// showing the toggle as on.
///
/// So: never read "the toggle is on" as proof, and never read silence as a code
/// bug before checking that row. `AudioTapController` below is the preferred
/// path, not a doomed one.
///
/// This class stays because a fallback is still worth having: SCK needs only
/// macOS 13 (below the 14.4 taps floor) and a permission that can be checked
/// honestly. Its audio is display-scoped rather than process-scoped, so the
/// "them" track picks up notification sounds and other media — which is exactly
/// what the tap exists to avoid.
@available(macOS 13.0, *)
final class ScreenCaptureAudioProbe: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private(set) var peak: Float = 0
    private(set) var bytes = 0
    private let lock = NSLock()

    /// Whether screen-capture access is currently authorized.
    ///
    /// Unlike Core Audio taps — which are created happily and then hand back
    /// silence when denied — this can be asked directly. It is the only
    /// trustworthy permission signal available for system audio.
    static func isAuthorized() -> Bool { CGPreflightScreenCaptureAccess() }

    /// Ask the system to prompt. Returns immediately; the grant only takes
    /// effect on the NEXT launch, which is macOS behaviour, not a bug here.
    @discardableResult
    static func requestAuthorization() -> Bool { CGRequestScreenCaptureAccess() }

    /// Capture briefly and report the loudest sample seen.
    func measure(seconds: Double) async throws -> (peak: Float, bytes: Int) {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "sck", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No display to capture from."])
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 1
        // Our own output would otherwise feed back into the recording.
        config.excludesCurrentProcessAudio = true
        // Smallest legal video capture; SCK still wants a video configuration
        // even when only the audio is wanted.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        self.stream = stream

        try await stream.startCapture()
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        try? await stream.stopCapture()
        self.stream = nil

        lock.lock(); defer { lock.unlock() }
        return (peak, bytes)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio,
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
              let pointer, length > 0 else { return }

        let count = length / MemoryLayout<Float>.size
        var localPeak: Float = 0
        pointer.withMemoryRebound(to: Float.self, capacity: count) { floats in
            for index in 0..<count {
                let magnitude = abs(floats[index])
                if magnitude > localPeak { localPeak = magnitude }
            }
        }
        lock.lock()
        bytes += length
        if localPeak > peak { peak = localPeak }
        lock.unlock()
    }
}

/// Per-process system-audio capture, plus microphone activity detection.
///
/// This exists so a meeting can be recorded as TWO separate tracks — the mic
/// ("me") and the meeting app's own output ("them"). There is no diarization
/// anywhere in UltraWhisper; speaker attribution is physical, and it is what
/// makes "my background vs theirs" and per-owner action items possible at all.
///
/// Core Audio process taps are used rather than ScreenCaptureKit. SCK's audio is
/// display-scoped, not process-scoped: notification sounds and any other playing
/// media land in the same buffer even when the content filter names a single
/// app, which would put the wrong voice in the "them" track. Taps also need only
/// the System Audio Recording permission instead of full Screen Recording.
///
/// Requires macOS 14.4. See `docs/MEETING_PROTOCOL.md`.
@available(macOS 14.4, *)
final class AudioTapController {

    // The backend wants exactly this: PCM int16, mono, 16 kHz. Taps hand back
    // float32 at the hardware rate (48 kHz here), so every buffer is converted
    // before it leaves this class.
    static let targetSampleRate: Double = 16_000

    /// A capture that produced nothing but digital silence for this long is
    /// reported as suspect.
    ///
    /// This matters more than it looks. When the System Audio Recording
    /// permission is missing, macOS does NOT fail the call — the tap is created,
    /// the aggregate device runs, the IOProc fires at the correct rate, and every
    /// sample is zero. A denial is therefore indistinguishable from a meeting
    /// where nobody spoke, and without this watchdog the user gets an empty
    /// "them" track and no error whatsoever. Verified by direct experiment: a tap
    /// on a process actively playing a test tone returned 131072 frames of pure
    /// zeroes.
    static let silenceWarningSeconds: Double = 8.0

    /// Anything below this counts as digital silence rather than a quiet room.
    private static let silenceFloor: Float = 1e-6

    struct Process {
        let objectID: AudioObjectID
        let pid: pid_t
        let bundleID: String?
        let name: String
        let runningOutput: Bool

        /// Whether this process is currently pulling from an input device.
        ///
        /// Paired with `runningOutput` this is the meeting detector: a real-time
        /// call is the one common situation where a SINGLE process both captures
        /// the mic and plays audio. Music is output-only, dictation is
        /// input-only, and a browser in a Meet call is both — which is why the
        /// signal works without knowing any app's bundle ID.
        let runningInput: Bool

        /// Whether this process looks like a live call right now.
        var looksLikeMeeting: Bool { runningInput && runningOutput }

        var asDictionary: [String: Any] {
            [
                "pid": Int(pid),
                "bundleId": bundleID as Any,
                "name": name,
                "runningOutput": runningOutput,
                "runningInput": runningInput,
            ]
        }
    }

    /// Emitted for every converted buffer: PCM int16, mono, 16 kHz.
    var onAudio: ((Data) -> Void)?
    /// Emitted once if the capture looks like a silent-denial rather than a quiet room.
    var onSilenceSuspected: (() -> Void)?
    /// Emitted when the default input device starts or stops being used by anyone.
    var onMicActivityChanged: ((Bool) -> Void)?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?

    private var sawAudio = false
    private var silenceReported = false
    private var loggedBufferShape = false
    private var loggedCallbacks = 0

    /// Which buffer of the aggregate's input list carries the tap.
    ///
    /// Latched on the first callback that contains audio, exactly as the
    /// known-good testbed does. The aggregate is built from the default output
    /// device AND the tap, and any input streams that device contributes are
    /// listed first — a headset with a microphone contributes one — so
    /// `mBuffers[0]` can be somebody else's silence while the tap sits later.
    /// Reading index 0 and concluding "the tap is silent" is the trap.
    private var selectedBuffer = 0
    private var bufferLatched = false

    /// Names the running .app, so re-signed variants launched to bisect a
    /// permission problem each get their own diagnostic file.
    private static let variantName =
        Bundle.main.bundleURL.deletingPathExtension().lastPathComponent

    /// Appended to `~/.ultrawhisper_tap_diag-<variant>`, which is the only channel that
    /// survives an `open`-launched app: stdout is discarded and NSLog has not
    /// been reaching the unified log from this bundle.
    private static func diag(_ line: String) {
        NSLog("AudioTapController: \(line)")
        let path = NSHomeDirectory() + "/.ultrawhisper_tap_diag-" + Self.variantName
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// How many input streams the aggregate exposes, and how wide each is.
    ///
    /// This is the question the buffer-shape log cannot answer on its own:
    /// whether the tap is even present in the aggregate's input list.
    private static func inputStreamShape(_ device: AudioObjectID) -> String {
        var addr = address(kAudioDevicePropertyStreamConfiguration,
                           kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr,
              size > 0 else { return "unavailable" }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr else {
            return "unreadable"
        }
        let list = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self))
        let parts = list.enumerated().map { "[\($0.offset)] \($0.element.mNumberChannels)ch" }
        return "\(list.count) stream(s): \(parts.joined(separator: " "))"
    }
    private var captureStarted: CFAbsoluteTime = 0
    private let lock = NSLock()

    private var micListenerInstalled = false
    private var micDeviceID = AudioObjectID(kAudioObjectUnknown)

    // MARK: - Property plumbing

    private static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func scalar<T>(_ obj: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ def: T) -> T {
        var addr = addr
        var size = UInt32(MemoryLayout<T>.size)
        var out = def
        let err = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &out)
        return err == noErr ? out : def
    }

    private static func string(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var out: CFString?
        let err = withUnsafeMutablePointer(to: &out) {
            AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, $0)
        }
        guard err == noErr, let value = out else { return nil }
        return value as String
    }

    private static func objectList(_ obj: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> [AudioObjectID] {
        var addr = addr
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var out = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &out) == noErr else { return [] }
        return out
    }

    // MARK: - Process discovery

    /// Every process Core Audio knows about.
    ///
    /// A process only appears here once it has played audio at least once, so a
    /// meeting app that has been launched but has not yet made a sound is
    /// legitimately absent. Callers should re-list rather than cache.
    static func listProcesses() -> [Process] {
        objectList(AudioObjectID(kAudioObjectSystemObject),
                   address(kAudioHardwarePropertyProcessObjectList)).map { object in
            let pid = scalar(object, address(kAudioProcessPropertyPID), pid_t(-1))
            let bundleID = string(object, kAudioProcessPropertyBundleID)
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName
                ?? bundleID
                ?? "pid \(pid)"
            return Process(
                objectID: object,
                pid: pid,
                bundleID: bundleID,
                name: name,
                runningOutput: scalar(object, address(kAudioProcessPropertyIsRunningOutput), UInt32(0)) != 0,
                runningInput: scalar(object, address(kAudioProcessPropertyIsRunningInput), UInt32(0)) != 0
            )
        }
    }

    // MARK: - Permission preflight

    /// Create and immediately destroy a tap, to surface the System Audio
    /// Recording permission prompt without recording anything.
    ///
    /// Worth doing early rather than at the start of a meeting. A missing
    /// permission does not fail the capture — it yields digital silence — so
    /// without a preflight the first symptom is an empty "them" track
    /// discovered after the call is over and the audio is gone. Asking up
    /// front turns an unrecoverable failure into a question.
    ///
    /// Returns whether the tap could be created at all. That is NOT proof of
    /// authorization: macOS hands back a working tap and silent audio when the
    /// permission is denied, so only `onSilenceSuspected` during a real capture
    /// can tell those apart. Creation failing, though, is conclusive.
    @discardableResult
    func preflightPermission() -> Bool {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "UltraWhisper Permission Check"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        // Start each launch with a fresh diagnostic file; otherwise runs pile up
        // and it is not obvious which lines belong to the capture being debugged.
        try? "".write(toFile: NSHomeDirectory() + "/.ultrawhisper_tap_diag-" + Self.variantName,
                      atomically: true, encoding: .utf8)

        var probeID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &probeID)
        Self.diag("preflight createProcessTap status=\(status)")
        if probeID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(probeID)
        }
        NSLog("AudioTapController: permission preflight status=\(status)")
        return status == noErr
    }

    // MARK: - Capture

    /// Start capturing. An empty [processObjectIDs] means a GLOBAL tap of
    /// everything, which exists purely to split one diagnosis: a global tap
    /// that hears audio while a per-process tap of the same playing app hears
    /// zeroes rules the permission out and points at process targeting, and a
    /// global tap that is also silent rules targeting out. Nothing in normal
    /// use wants a global tap — it would put every notification sound in the
    /// "them" track, which is the whole reason taps beat ScreenCaptureKit.
    func startCapture(processObjectIDs: [AudioObjectID]) throws {
        stopCapture()

        let description = processObjectIDs.isEmpty
            ? CATapDescription(monoGlobalTapButExcludeProcesses: [])
            : CATapDescription(monoMixdownOfProcesses: processObjectIDs)
        description.name = "UltraWhisper Meeting Tap"
        description.isPrivate = true            // never appears as a system-wide device
        description.muteBehavior = .unmuted     // the user must still HEAR the meeting

        Self.diag("--- startCapture "
        + (processObjectIDs.isEmpty ? "GLOBAL" : "\(processObjectIDs.count) process(es)") + " ---")

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        Self.diag("createProcessTap status=\(status) tapID=\(tapID)")
        guard status == noErr else {
            throw error(status, "Could not create the audio tap.")
        }

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = Self.address(kAudioTapPropertyFormat)
        status = AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &size, &asbd)
        guard status == noErr, let source = AVAudioFormat(streamDescription: &asbd) else {
            stopCapture()
            throw error(status, "Could not read the tap's audio format.")
        }
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            stopCapture()
            throw error(-1, "Could not build the 16 kHz output format.")
        }
        sourceFormat = source
        targetFormat = target
        converter = AVAudioConverter(from: source, to: target)

        // The aggregate device is clocked by a real subdevice. With an empty
        // subdevice list there is nothing driving the IO cycle, so anchor it to
        // the current default output.
        let defaultOutput = Self.scalar(
            AudioObjectID(kAudioObjectSystemObject),
            Self.address(kAudioHardwarePropertyDefaultOutputDevice),
            AudioObjectID(kAudioObjectUnknown))
        let outputUID = Self.string(defaultOutput, kAudioDevicePropertyDeviceUID)

        var settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "UltraWhisper Meeting Capture",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]
        if let outputUID {
            settings[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
            settings[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: outputUID]]
        }

        status = AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregateID)
        Self.diag("createAggregate status=\(status) aggregateID=\(aggregateID) "
            + "mainSubDevice=\(outputUID ?? "none")")
        guard status == noErr else {
            stopCapture()
            throw error(status, "Could not create the capture device.")
        }
        Self.diag("aggregate input streams: \(Self.inputStreamShape(aggregateID))")
        Self.diag("tap format: \(source)")

        // `kAudioTapPropertyFormat` is what the tap ADVERTISES, and it is not
        // always the clock the aggregate device actually runs on. Believing it
        // resamples every buffer at the wrong ratio, which is invisible: full
        // amplitude, no dropouts, a clean signal — just at the wrong speed.
        // Measured 2026-08-23 with a 44.1 kHz Bluetooth output under a tap
        // claiming 48 kHz: a 440 Hz tone arrived as 479 Hz, exactly 48000/44100.
        // Whisper still returns plausible text from that, only worse, which is
        // the kind of bug that gets blamed on the model for months.
        //
        // Note the aggregate's kAudioDevicePropertyStreamFormat does NOT help —
        // it repeats the tap's claim. Verified empirically. The nominal sample
        // rate is the property that tells the truth.
        let aggregateNominal = Self.scalar(
            aggregateID, Self.address(kAudioDevicePropertyNominalSampleRate), Double(0))
        let outputNominal = Self.scalar(
            defaultOutput, Self.address(kAudioDevicePropertyNominalSampleRate), Double(0))
        NSLog("AudioTapController: rates — tap=%.0f aggregateNominal=%.0f output=%.0f",
              source.sampleRate, aggregateNominal, outputNominal)

        if let trueRate = [aggregateNominal, outputNominal]
            .first(where: { $0 > 0 && abs($0 - source.sampleRate) > 1 }) {
            var asbd = source.streamDescription.pointee
            asbd.mSampleRate = trueRate
            if let corrected = AVAudioFormat(streamDescription: &asbd) {
                NSLog("AudioTapController: tap claims %.0f Hz but the samples are %.0f Hz — trusting %.0f",
                      source.sampleRate, trueRate, trueRate)
                sourceFormat = corrected
                converter = AVAudioConverter(from: corrected, to: target)
            }
        }

        sawAudio = false
        silenceReported = false
        loggedBufferShape = false
        loggedCallbacks = 0
        selectedBuffer = 0
        bufferLatched = false
        captureStarted = CFAbsoluteTimeGetCurrent()

        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) {
            [weak self] _, inputData, _, _, _ in
            self?.handle(inputData)
        }
        guard status == noErr, let ioProcID else {
            stopCapture()
            throw error(status, "Could not install the audio callback.")
        }

        status = AudioDeviceStart(aggregateID, ioProcID)
        Self.diag("deviceStart status=\(status)")
        guard status == noErr else {
            stopCapture()
            throw error(status, "Could not start the capture device.")
        }
        Self.diag("capturing at \(source.sampleRate) Hz")
    }

    private func handle(_ bufferList: UnsafePointer<AudioBufferList>) {
        guard let sourceFormat, let targetFormat, let converter else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList))

        // Log the first few callbacks, not just the first.
        //
        // One sample of the input list cannot tell "the tap delivers zeroes"
        // apart from "the tap had not started producing yet when we looked" —
        // an aggregate device runs its IO cycle before the tap's first buffer
        // lands. Several consecutive callbacks can.
        if loggedCallbacks < 8 {
            loggedCallbacks += 1
            let shape = buffers.enumerated().map { index, buffer -> String in
                "[\(index)] \(buffer.mNumberChannels)ch \(buffer.mDataByteSize)B "
                    + "peak=\(peak(of: buffer))"
            }.joined(separator: "  ")
            Self.diag("cb\(loggedCallbacks) buffers=\(buffers.count)  \(shape)")
            if !loggedBufferShape {
                loggedBufferShape = true
                Self.diag("sourceFormat=\(sourceFormat) targetFormat=\(targetFormat)")
            }
        }

        // Latch the first buffer that actually carries audio. See the comment
        // on `selectedBuffer`: index 0 can belong to an input stream the output
        // sub-device contributes rather than to the tap.
        if !bufferLatched {
            for (index, buffer) in buffers.enumerated() where peak(of: buffer) > Self.silenceFloor {
                selectedBuffer = index
                bufferLatched = true
                if index != 0 {
                    Self.diag("audio is in buffer \(index), not buffer 0 — "
                        + "reading index 0 alone would have looked like silence")
                }
                break
            }
        }

        guard selectedBuffer < buffers.count else { return }
        let buffer = buffers[selectedBuffer]
        guard buffer.mDataByteSize > 0 else { return }

        // The tap's format describes its own stream; if the buffer we settled
        // on disagrees about channel count, follow the buffer.
        let inputFormat: AVAudioFormat
        if buffer.mNumberChannels == sourceFormat.channelCount {
            inputFormat = sourceFormat
        } else {
            var asbd = sourceFormat.streamDescription.pointee
            asbd.mChannelsPerFrame = buffer.mNumberChannels
            asbd.mBytesPerFrame = buffer.mNumberChannels * 4
            asbd.mBytesPerPacket = asbd.mBytesPerFrame
            guard let adjusted = AVAudioFormat(streamDescription: &asbd) else { return }
            inputFormat = adjusted
        }

        let frames = AVAudioFrameCount(
            buffer.mDataByteSize / max(1, inputFormat.streamDescription.pointee.mBytesPerFrame))
        guard frames > 0 else { return }

        var single = AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)
        let converted: Data? = withUnsafePointer(to: &single) { pointer -> Data? in
            guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, bufferListNoCopy: pointer)
            else {
                if loggedCallbacks <= 8 { Self.diag("   → could not wrap the buffer list") }
                return nil
            }

            // The exact shape the converter is being handed. A wrong
            // mBytesPerFrame silently inflates frameLength and the converter
            // then reads past the real samples, which is one of the few ways
            // this produces a full-length run of zeroes.
            if loggedCallbacks <= 8 {
                let asbd = inputFormat.streamDescription.pointee
                Self.diag("   input frameLength=\(input.frameLength) computedFrames=\(frames) "
                    + "bytesPerFrame=\(asbd.mBytesPerFrame) channels=\(asbd.mChannelsPerFrame) "
                    + "flags=\(asbd.mFormatFlags) interleaved=\(!inputFormat.isInterleaved ? "no" : "yes") "
                    + "floatChannelData=\(input.floatChannelData == nil ? "NIL" : "ok")")
            }

            noteSilence(in: input, frames: frames)

            let capacity = AVAudioFrameCount(
                (Double(frames) * targetFormat.sampleRate / inputFormat.sampleRate).rounded(.up) + 32)
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
            else { return nil }

            var pulled = false
            var conversionError: NSError?
            converter.convert(to: output, error: &conversionError) { _, status in
                if pulled {
                    status.pointee = .noDataNow
                    return nil
                }
                pulled = true
                status.pointee = .haveData
                return input
            }
            if loggedCallbacks <= 8 {
                Self.diag("   convert err=\(conversionError?.code.description ?? "none") "
                    + "outFrames=\(output.frameLength)/\(capacity) "
                    + "int16ChannelData=\(output.int16ChannelData == nil ? "NIL" : "ok")")
            }

            guard conversionError == nil,
                  output.frameLength > 0,
                  let channel = output.int16ChannelData
            else { return nil }

            return Data(bytes: channel[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
        }

        // Log what SURVIVED the conversion, not just what arrived.
        //
        // The raw buffer log above proved the tap works while the delivered
        // audio was still all zeroes — so the interesting number is the one
        // after resampling to 16 kHz int16, and logging only the input hid a
        // bug in this function for several rounds of debugging.
        if loggedCallbacks <= 8 {
            if let converted {
                var loudest: Int16 = 0
                converted.withUnsafeBytes { raw in
                    let samples = raw.bindMemory(to: Int16.self)
                    for sample in samples {
                        let magnitude = sample == Int16.min ? Int16.max : abs(sample)
                        if magnitude > loudest { loudest = magnitude }
                    }
                }
                Self.diag("   → converted \(converted.count)B peak=\(loudest)/32767")
            } else {
                Self.diag("   → conversion produced nothing")
            }
        }

        if let converted { onAudio?(converted) }
    }

    /// Loudest absolute sample in one float32 buffer.
    private func peak(of buffer: AudioBuffer) -> Float {
        guard let data = buffer.mData else { return 0 }
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0 else { return 0 }
        var loudest: Float = 0
        data.withMemoryRebound(to: Float.self, capacity: count) { floats in
            for index in 0..<count {
                let magnitude = abs(floats[index])
                if magnitude > loudest { loudest = magnitude }
            }
        }
        return loudest
    }

    /// Watch for the all-zeroes signature of a permission denial.
    private func noteSilence(in buffer: AVAudioPCMBuffer, frames: AVAudioFrameCount) {
        guard !sawAudio, let floats = buffer.floatChannelData else { return }
        let samples = floats[0]
        for index in 0..<Int(frames) where abs(samples[index]) > Self.silenceFloor {
            lock.lock(); sawAudio = true; lock.unlock()
            return
        }
        lock.lock()
        let elapsed = CFAbsoluteTimeGetCurrent() - captureStarted
        let shouldReport = !silenceReported && elapsed > Self.silenceWarningSeconds
        if shouldReport { silenceReported = true }
        lock.unlock()

        if shouldReport {
            NSLog("AudioTapController: %.0fs of digital silence — System Audio Recording permission is probably missing",
                  Self.silenceWarningSeconds)
            onSilenceSuspected?()
        }
    }

    func stopCapture() {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        converter = nil
        sourceFormat = nil
        targetFormat = nil
    }

    // MARK: - Microphone activity

    /// Whether anything on the system is currently using the default input.
    ///
    /// This is the meeting-detection signal: a call is running when the mic goes
    /// hot, and is over once it has been cold for a while. It deliberately says
    /// nothing about WHO is using the mic — that it is in use at all is the whole
    /// signal, and asking for more would mean watching other apps.
    static func micIsActive() -> Bool {
        let device = scalar(
            AudioObjectID(kAudioObjectSystemObject),
            address(kAudioHardwarePropertyDefaultInputDevice),
            AudioObjectID(kAudioObjectUnknown))
        guard device != AudioObjectID(kAudioObjectUnknown) else { return false }
        return scalar(device, address(kAudioDevicePropertyDeviceIsRunningSomewhere), UInt32(0)) != 0
    }

    func startMicActivityMonitoring() {
        guard !micListenerInstalled else { return }
        micDeviceID = Self.scalar(
            AudioObjectID(kAudioObjectSystemObject),
            Self.address(kAudioHardwarePropertyDefaultInputDevice),
            AudioObjectID(kAudioObjectUnknown))
        guard micDeviceID != AudioObjectID(kAudioObjectUnknown) else { return }

        var addr = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        let status = AudioObjectAddPropertyListenerBlock(micDeviceID, &addr, DispatchQueue.main) {
            [weak self] _, _ in
            self?.onMicActivityChanged?(Self.micIsActive())
        }
        micListenerInstalled = status == noErr
        if !micListenerInstalled {
            NSLog("AudioTapController: could not observe mic activity (status \(status))")
        }
    }

    func stopMicActivityMonitoring() {
        guard micListenerInstalled, micDeviceID != AudioObjectID(kAudioObjectUnknown) else { return }
        var addr = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        AudioObjectRemovePropertyListenerBlock(micDeviceID, &addr, DispatchQueue.main) { _, _ in }
        micListenerInstalled = false
    }

    // MARK: - Errors

    private func error(_ status: OSStatus, _ message: String) -> NSError {
        NSError(domain: "com.ultrawhisper.audiotap", code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    deinit {
        stopCapture()
        stopMicActivityMonitoring()
    }
}
