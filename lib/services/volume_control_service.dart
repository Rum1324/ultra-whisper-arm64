import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Snapshot of the system's default audio output device.
class OutputDeviceInfo {
  /// Stable CoreAudio identifier, empty when the device would not give one.
  /// A device without a UID cannot be remembered across reconnects.
  final String uid;

  /// Human-readable device name, or an empty string if it could not be read.
  final String name;

  /// CoreAudio transport type constant (kAudioDeviceTransportType*).
  final int transportType;

  /// True when the device is connected over Bluetooth or Bluetooth LE.
  final bool isBluetooth;

  const OutputDeviceInfo({
    required this.uid,
    required this.name,
    required this.transportType,
    required this.isBluetooth,
  });

  /// Name for display, falling back to a generic label for unnamed devices.
  String get displayName => name.isEmpty ? 'Unknown device' : name;
}

class VolumeControlService {
  static const MethodChannel _channel = MethodChannel('com.ultrawhisper.volume');

  bool _volumeDuckedByUs = false;

  /// Get the current system volume (0.0 to 1.0)
  Future<double> getVolume() async {
    try {
      final double volume = await _channel.invokeMethod('getVolume');
      return volume;
    } catch (e) {
      debugPrint('VolumeControlService: Failed to get volume: $e');
      rethrow;
    }
  }

  /// Set the system volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    try {
      await _channel.invokeMethod('setVolume', {'volume': volume});
    } catch (e) {
      debugPrint('VolumeControlService: Failed to set volume: $e');
      rethrow;
    }
  }

  /// Describe the current default output device.
  ///
  /// Returns null if the device could not be inspected — callers should treat
  /// that as "unknown" and fall back to their default behaviour.
  Future<OutputDeviceInfo?> getOutputDeviceInfo() async {
    try {
      final Map<Object?, Object?>? info =
          await _channel.invokeMethod('getOutputDeviceInfo');
      if (info == null) return null;

      return OutputDeviceInfo(
        uid: info['uid'] as String? ?? '',
        name: info['name'] as String? ?? '',
        transportType: info['transportType'] as int? ?? 0,
        isBluetooth: info['isBluetooth'] as bool? ?? false,
      );
    } catch (e) {
      debugPrint('VolumeControlService: Failed to get output device info: $e');
      return null;
    }
  }

  /// Check if the system is muted
  Future<bool> isMuted() async {
    try {
      final bool muted = await _channel.invokeMethod('isMuted');
      return muted;
    } catch (e) {
      debugPrint('VolumeControlService: Failed to check mute state: $e');
      rethrow;
    }
  }

  /// Set the system mute state
  Future<void> setMuted(bool muted) async {
    try {
      await _channel.invokeMethod('setMuted', {'muted': muted});
    } catch (e) {
      debugPrint('VolumeControlService: Failed to set mute state: $e');
      rethrow;
    }
  }

  /// Duck volume before recording (save state and reduce volume)
  ///
  /// This method should be called when recording starts. It will:
  /// - Save the current volume level and mute state
  /// - Reduce the volume to the specified percentage
  /// - Enable crash recovery by persisting the state
  ///
  /// [percentage] - The percentage to reduce volume to (0.0 to 1.0, default 0.1 = 10%)
  /// [persistent] - Whether to save state for crash recovery (default true)
  ///
  /// Whether ducking should happen at all is decided by the caller: that answer
  /// now depends on remembered per-device preferences, and the caller has to
  /// look the device up anyway to record that it was used.
  Future<void> duckVolumeForRecording({
    required double percentage,
    bool persistent = true,
  }) async {
    try {
      await _channel.invokeMethod('duckVolume', {
        'percentage': percentage,
        'persistent': persistent,
      });
      _volumeDuckedByUs = true;
      debugPrint('VolumeControlService: Successfully ducked volume to ${(percentage * 100).toStringAsFixed(0)}%');
    } catch (e) {
      debugPrint('VolumeControlService: Failed to duck volume (non-fatal): $e');
      // Don't rethrow - volume ducking failure shouldn't prevent recording
    }
  }

  /// Restore volume after recording
  ///
  /// This method should be called when recording ends. It will:
  /// - Restore the previously saved volume level
  /// - Restore the previously saved mute state
  /// - Clear the saved state (both in-memory and persistent)
  ///
  /// Note: This will only restore if we successfully ducked the volume earlier.
  /// If the user manually changed the volume during recording, restoration may be skipped
  /// (handled by the native side).
  Future<void> restoreVolumeAfterRecording() async {
    if (!_volumeDuckedByUs) {
      debugPrint('VolumeControlService: Volume was not ducked by us, skipping restore');
      return;
    }

    try {
      await _channel.invokeMethod('restoreVolume');
      _volumeDuckedByUs = false;
      debugPrint('VolumeControlService: Successfully restored volume');
    } catch (e) {
      debugPrint('VolumeControlService: Failed to restore volume (non-fatal): $e');
      // Don't rethrow - volume restore failure shouldn't break the app
      _volumeDuckedByUs = false; // Reset state even on failure
    }
  }

  /// Reset the service state (useful for testing or error recovery)
  void reset() {
    _volumeDuckedByUs = false;
  }

  /// Check if volume is currently ducked by this service
  bool get isVolumeDucked => _volumeDuckedByUs;
}
