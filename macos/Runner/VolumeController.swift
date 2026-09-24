import Foundation
import CoreAudio
import AudioToolbox

class VolumeController {

    // MARK: - Volume State Management

    struct VolumeState {
        let volume: Float32      // 0.0 to 1.0
        let isMuted: Bool
        let deviceID: AudioDeviceID
        let timestamp: Date
    }

    private static var savedState: VolumeState?
    private static let kVolumeSettingsKey = "com.ultrawhisper.savedVolume"

    // MARK: - Public API

    /// Get the default output device ID
    static func getDefaultOutputDevice() throws -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var deviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &deviceIDSize,
            &deviceID
        )

        guard status == noErr else {
            throw VolumeError.failedToGetDevice(status: status)
        }

        guard deviceID != kAudioDeviceUnknown else {
            throw VolumeError.noOutputDevice
        }

        return deviceID
    }

    /// Describes the current default output device.
    struct OutputDeviceInfo {
        /// Stable identifier that survives reconnects, unlike the name. Empty
        /// when CoreAudio would not give one — such a device cannot be
        /// remembered, so callers fall back to the transport heuristic.
        let uid: String
        let name: String
        let transportType: UInt32
        let isBluetooth: Bool
    }

    /// Get the name and transport type of the default output device.
    ///
    /// Used to decide whether ducking is worth doing: audio played through Bluetooth
    /// headphones never reaches the microphone, so there is nothing to duck.
    static func getOutputDeviceInfo() throws -> OutputDeviceInfo {
        let deviceID = try getDefaultOutputDevice()

        var transportType = UInt32(0)
        var transportSize = UInt32(MemoryLayout<UInt32>.size)

        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let transportStatus = AudioObjectGetPropertyData(
            deviceID,
            &transportAddress,
            0,
            nil,
            &transportSize,
            &transportType
        )

        guard transportStatus == noErr else {
            throw VolumeError.failedToGetTransportType(status: transportStatus)
        }

        let isBluetooth = transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE

        return OutputDeviceInfo(
            uid: deviceUID(for: deviceID),
            name: deviceName(for: deviceID),
            transportType: transportType,
            isBluetooth: isBluetooth
        )
    }

    /// Best-effort device name. Used for logging and UI hints only, so failure
    /// yields an empty string rather than an error.
    private static func deviceName(for deviceID: AudioDeviceID) -> String {
        cfStringProperty(kAudioObjectPropertyName, for: deviceID)
    }

    /// Best-effort persistent device identifier, used as the key for
    /// remembered per-device preferences. Empty on failure so the caller can
    /// tell "no identity" from a real one.
    private static func deviceUID(for deviceID: AudioDeviceID) -> String {
        cfStringProperty(kAudioDevicePropertyDeviceUID, for: deviceID)
    }

    private static func cfStringProperty(
        _ selector: AudioObjectPropertySelector,
        for deviceID: AudioDeviceID
    ) -> String {
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &nameSize,
            &name
        )

        guard status == noErr, let cfName = name?.takeRetainedValue() else {
            return ""
        }

        return cfName as String
    }

    /// Get current system volume (0.0 to 1.0)
    static func getCurrentVolume() throws -> Float32 {
        let deviceID = try getDefaultOutputDevice()

        var volume = Float32(0.0)
        var volumeSize = UInt32(MemoryLayout<Float32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &volumeSize,
            &volume
        )

        guard status == noErr else {
            throw VolumeError.failedToGetVolume(status: status)
        }

        return volume
    }

    /// Set system volume (0.0 to 1.0)
    static func setVolume(_ volume: Float32) throws {
        let deviceID = try getDefaultOutputDevice()

        var newVolume = min(max(volume, 0.0), 1.0) // Clamp to 0.0-1.0
        let volumeSize = UInt32(MemoryLayout<Float32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Check if volume is settable
        var isSettable: DarwinBoolean = false
        let settableStatus = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)

        guard settableStatus == noErr && isSettable.boolValue else {
            throw VolumeError.volumeNotSettable
        }

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            volumeSize,
            &newVolume
        )

        guard status == noErr else {
            throw VolumeError.failedToSetVolume(status: status)
        }

        NSLog("VolumeController: Set volume to \(newVolume)")
    }

    /// Get current mute state
    static func isMuted() throws -> Bool {
        let deviceID = try getDefaultOutputDevice()

        var muted = UInt32(0)
        var mutedSize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &mutedSize,
            &muted
        )

        guard status == noErr else {
            // Some devices don't support mute property
            if status == kAudioHardwareUnknownPropertyError {
                return false
            }
            throw VolumeError.failedToGetMuteState(status: status)
        }

        return muted != 0
    }

    /// Set mute state
    static func setMuted(_ muted: Bool) throws {
        let deviceID = try getDefaultOutputDevice()

        var muteValue = UInt32(muted ? 1 : 0)
        let muteSize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            muteSize,
            &muteValue
        )

        guard status == noErr else {
            // Some devices don't support mute property
            if status == kAudioHardwareUnknownPropertyError {
                NSLog("VolumeController: Device does not support mute property")
                return
            }
            throw VolumeError.failedToSetMuteState(status: status)
        }

        NSLog("VolumeController: Set muted to \(muted)")
    }

    // MARK: - High-Level Volume Ducking API

    /// Save current volume state and reduce to specified percentage
    /// - Parameter duckPercentage: Percentage to reduce volume to (0.0 to 1.0)
    /// - Parameter persistent: Whether to save to UserDefaults for crash recovery
    static func duckVolume(to duckPercentage: Float32, persistent: Bool = true) throws {
        let currentVolume = try getCurrentVolume()
        let currentMuted = try isMuted()
        let deviceID = try getDefaultOutputDevice()

        // Save current state
        savedState = VolumeState(
            volume: currentVolume,
            isMuted: currentMuted,
            deviceID: deviceID,
            timestamp: Date()
        )

        // Persist to UserDefaults for crash recovery
        if persistent {
            saveStateToDisk(savedState!)
        }

        NSLog("VolumeController: Saved volume state - volume: \(currentVolume), muted: \(currentMuted)")

        // Unmute if currently muted (so ducking works)
        if currentMuted {
            try setMuted(false)
        }

        // Duck volume
        let duckedVolume = currentVolume * duckPercentage
        try setVolume(duckedVolume)

        NSLog("VolumeController: Ducked volume from \(currentVolume) to \(duckedVolume)")
    }

    /// Restore previously saved volume state
    /// - Parameter clearPersistent: Whether to clear persistent storage after restore
    static func restoreVolume(clearPersistent: Bool = true) throws {
        // Try to get saved state from memory or disk
        if savedState == nil {
            if let persistentState = loadStateFromDisk() {
                savedState = persistentState
            } else {
                throw VolumeError.noSavedState
            }
        }

        guard let state = savedState else {
            throw VolumeError.noSavedState
        }

        // Check if output device has changed
        let currentDeviceID = try getDefaultOutputDevice()
        if currentDeviceID != state.deviceID {
            NSLog("VolumeController: Warning - Output device changed since save. Restoring to new device.")
        }

        // Check if user manually changed volume during recording
        let currentVolume = try getCurrentVolume()
        let expectedDuckedVolume = state.volume * 0.1 // Assume 10% duck by default

        // Only restore if volume hasn't been manually changed significantly
        if abs(currentVolume - expectedDuckedVolume) > 0.05 {
            NSLog("VolumeController: User changed volume during recording (current: \(currentVolume), expected: \(expectedDuckedVolume)). Skipping restore.")
            savedState = nil
            if clearPersistent {
                clearStateFromDisk()
            }
            return
        }

        // Restore volume
        try setVolume(state.volume)

        // Restore mute state
        try setMuted(state.isMuted)

        NSLog("VolumeController: Restored volume to \(state.volume), muted: \(state.isMuted)")

        // Clear saved state
        savedState = nil

        if clearPersistent {
            clearStateFromDisk()
        }
    }

    // MARK: - Persistent Storage for Crash Recovery

    private static func saveStateToDisk(_ state: VolumeState) {
        let defaults = UserDefaults.standard
        defaults.set(state.volume, forKey: "\(kVolumeSettingsKey).volume")
        defaults.set(state.isMuted, forKey: "\(kVolumeSettingsKey).muted")
        defaults.set(state.deviceID, forKey: "\(kVolumeSettingsKey).deviceID")
        defaults.set(state.timestamp, forKey: "\(kVolumeSettingsKey).timestamp")
    }

    private static func loadStateFromDisk() -> VolumeState? {
        let defaults = UserDefaults.standard

        guard let timestamp = defaults.object(forKey: "\(kVolumeSettingsKey).timestamp") as? Date else {
            return nil
        }

        // Don't restore if saved state is too old (> 1 hour)
        if Date().timeIntervalSince(timestamp) > 3600 {
            NSLog("VolumeController: Saved state too old, ignoring")
            clearStateFromDisk()
            return nil
        }

        let volume = defaults.float(forKey: "\(kVolumeSettingsKey).volume")
        let muted = defaults.bool(forKey: "\(kVolumeSettingsKey).muted")
        let deviceID = AudioDeviceID(defaults.integer(forKey: "\(kVolumeSettingsKey).deviceID"))

        return VolumeState(
            volume: volume,
            isMuted: muted,
            deviceID: deviceID,
            timestamp: timestamp
        )
    }

    private static func clearStateFromDisk() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "\(kVolumeSettingsKey).volume")
        defaults.removeObject(forKey: "\(kVolumeSettingsKey).muted")
        defaults.removeObject(forKey: "\(kVolumeSettingsKey).deviceID")
        defaults.removeObject(forKey: "\(kVolumeSettingsKey).timestamp")
    }

    /// Attempt to restore volume on app launch (crash recovery)
    static func restoreVolumeOnLaunch() {
        do {
            if let state = loadStateFromDisk() {
                NSLog("VolumeController: Found persistent volume state from \(state.timestamp)")
                try restoreVolume(clearPersistent: true)
            }
        } catch {
            NSLog("VolumeController: Failed to restore volume on launch: \(error)")
            clearStateFromDisk()
        }
    }

    // MARK: - Error Types

    enum VolumeError: Error, LocalizedError {
        case failedToGetDevice(status: OSStatus)
        case noOutputDevice
        case failedToGetTransportType(status: OSStatus)
        case failedToGetVolume(status: OSStatus)
        case failedToSetVolume(status: OSStatus)
        case failedToGetMuteState(status: OSStatus)
        case failedToSetMuteState(status: OSStatus)
        case volumeNotSettable
        case noSavedState

        var errorDescription: String? {
            switch self {
            case .failedToGetDevice(let status):
                return "Failed to get output device (status: \(status))"
            case .noOutputDevice:
                return "No output device available"
            case .failedToGetTransportType(let status):
                return "Failed to get output device transport type (status: \(status))"
            case .failedToGetVolume(let status):
                return "Failed to get volume (status: \(status))"
            case .failedToSetVolume(let status):
                return "Failed to set volume (status: \(status))"
            case .failedToGetMuteState(let status):
                return "Failed to get mute state (status: \(status))"
            case .failedToSetMuteState(let status):
                return "Failed to set mute state (status: \(status))"
            case .volumeNotSettable:
                return "Volume is not settable on this device"
            case .noSavedState:
                return "No saved volume state available"
            }
        }
    }
}
