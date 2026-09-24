import 'package:flutter/services.dart';
import '../utils/logger.dart';

class StatusBarService {
  static const _statusBarChannel = MethodChannel('com.glassywhisper.status_bar');
  static const _statusBarEventsChannel = MethodChannel('com.glassywhisper.status_bar_events');

  // Callbacks for menu actions
  Function()? onStartRecording;
  Function()? onStopRecording;
  Function()? onToggleMeeting;
  Function()? onOpenSettings;
  Function()? onRestart;
  Function()? onCheckForUpdates;
  Function()? onQuit;
  Function()? onToggleVolumeDuck;
  Function()? onToggleSkipDuckWhenBluetooth;

  StatusBarService() {
    _setupEventChannel();
  }

  void _setupEventChannel() {
    _statusBarEventsChannel.setMethodCallHandler(_handleStatusBarEvent);
    AppLogger.debug('StatusBarService: Event handler set up');
  }

  Future<void> _handleStatusBarEvent(MethodCall call) async {
    AppLogger.debug('StatusBarService: Received event: ${call.method}');

    switch (call.method) {
      case 'startRecording':
        AppLogger.info('StatusBarService: Start recording requested from menu bar');
        onStartRecording?.call();
        break;

      case 'stopRecording':
        AppLogger.info('StatusBarService: Stop recording requested from menu bar');
        onStopRecording?.call();
        break;

      case 'toggleMeeting':
        AppLogger.info('StatusBarService: Meeting toggle requested from menu bar');
        onToggleMeeting?.call();
        break;

      case 'openSettings':
        AppLogger.info('StatusBarService: Open settings requested from menu bar');
        onOpenSettings?.call();
        break;

      case 'restart':
        AppLogger.info('StatusBarService: Restart requested from menu bar');
        onRestart?.call();
        break;

      case 'checkForUpdates':
        AppLogger.info('StatusBarService: Check for updates requested from menu bar');
        onCheckForUpdates?.call();
        break;

      case 'quit':
        AppLogger.info('StatusBarService: Quit requested from menu bar');
        onQuit?.call();
        break;

      case 'toggleVolumeDuck':
        AppLogger.info('StatusBarService: Volume duck toggle requested from menu bar');
        onToggleVolumeDuck?.call();
        break;

      case 'toggleSkipDuckWhenBluetooth':
        AppLogger.info('StatusBarService: Skip-duck-when-Bluetooth toggle requested from menu bar');
        onToggleSkipDuckWhenBluetooth?.call();
        break;

      default:
        AppLogger.warning('StatusBarService: Unknown event: ${call.method}');
    }
  }

  Future<void> setRecordingState(bool recording) async {
    try {
      await _statusBarChannel.invokeMethod('setRecordingState', {
        'recording': recording,
      });
      AppLogger.debug('StatusBarService: Recording state set to $recording');
    } catch (e) {
      AppLogger.error('StatusBarService: Failed to set recording state', e);
    }
  }

  /// Reflect whether a meeting is being recorded, so the menu reads
  /// "Stop Meeting" while one is live.
  Future<void> setMeetingState(bool active) async {
    try {
      await _statusBarChannel.invokeMethod('setMeetingState', {'active': active});
      AppLogger.debug('StatusBarService: Meeting state set to $active');
    } catch (e) {
      AppLogger.error('StatusBarService: Failed to set meeting state', e);
    }
  }

  Future<void> showStatusBar() async {
    try {
      await _statusBarChannel.invokeMethod('showStatusBar');
      AppLogger.debug('StatusBarService: Status bar shown');
    } catch (e) {
      AppLogger.error('StatusBarService: Failed to show status bar', e);
    }
  }

  Future<void> hideStatusBar() async {
    try {
      await _statusBarChannel.invokeMethod('hideStatusBar');
      AppLogger.debug('StatusBarService: Status bar hidden');
    } catch (e) {
      AppLogger.error('StatusBarService: Failed to hide status bar', e);
    }
  }

  Future<void> setVolumeDuckState(bool enabled) async {
    try {
      await _statusBarChannel.invokeMethod('setVolumeDuckState', {
        'enabled': enabled,
      });
      AppLogger.debug('StatusBarService: Volume duck state set to $enabled');
    } catch (e) {
      AppLogger.error('StatusBarService: Failed to set volume duck state', e);
    }
  }

  /// Reflect the ducking choice for the current output device.
  ///
  /// [deviceName] names the device in the menu title so the item cannot be
  /// mistaken for a global switch; empty falls back to a generic label.
  Future<void> setDeviceSkipDuckState({
    required bool enabled,
    required String deviceName,
  }) async {
    try {
      await _statusBarChannel.invokeMethod('setDeviceSkipDuckState', {
        'enabled': enabled,
        'deviceName': deviceName,
      });
      AppLogger.debug(
        'StatusBarService: Skip-duck state set to $enabled for "$deviceName"',
      );
    } catch (e) {
      AppLogger.error('StatusBarService: Failed to set skip-duck state', e);
    }
  }
}
