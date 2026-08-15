import AVFoundation
import AppKit
import CoreAudio
import Foundation

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

        var asDictionary: [String: Any] {
            [
                "pid": Int(pid),
                "bundleId": bundleID as Any,
                "name": name,
                "runningOutput": runningOutput,
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
                runningOutput: scalar(object, address(kAudioProcessPropertyIsRunningOutput), UInt32(0)) != 0
            )
        }
    }

    // MARK: - Capture

    func startCapture(processObjectIDs: [AudioObjectID]) throws {
        guard !processObjectIDs.isEmpty else {
            throw error(-1, "No audio processes to tap.")
        }
        stopCapture()

        let description = CATapDescription(monoMixdownOfProcesses: processObjectIDs)
        description.name = "UltraWhisper Meeting Tap"
        description.isPrivate = true            // never appears as a system-wide device
        description.muteBehavior = .unmuted     // the user must still HEAR the meeting

        var status = AudioHardwareCreateProcessTap(description, &tapID)
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
        guard status == noErr else {
            stopCapture()
            throw error(status, "Could not create the capture device.")
        }

        sawAudio = false
        silenceReported = false
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
        guard status == noErr else {
            stopCapture()
            throw error(status, "Could not start the capture device.")
        }
        NSLog("AudioTapController: capturing \(processObjectIDs.count) process(es) at \(source.sampleRate) Hz")
    }

    private func handle(_ bufferList: UnsafePointer<AudioBufferList>) {
        guard let sourceFormat, let targetFormat, let converter else { return }

        let frames = AVAudioFrameCount(
            bufferList.pointee.mBuffers.mDataByteSize / max(1, sourceFormat.streamDescription.pointee.mBytesPerFrame))
        guard frames > 0,
              let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, bufferListNoCopy: bufferList)
        else { return }

        noteSilence(in: input, frames: frames)

        let capacity = AVAudioFrameCount(
            (Double(frames) * targetFormat.sampleRate / sourceFormat.sampleRate).rounded(.up) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

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
        guard conversionError == nil,
              output.frameLength > 0,
              let channel = output.int16ChannelData
        else { return }

        let byteCount = Int(output.frameLength) * MemoryLayout<Int16>.size
        onAudio?(Data(bytes: channel[0], count: byteCount))
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
