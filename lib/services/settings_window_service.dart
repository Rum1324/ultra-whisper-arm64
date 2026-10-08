import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One secondary window: the settings window or the setup window.
///
/// Each is its own Flutter engine (desktop_multi_window), routed by the string
/// passed to `createWindow` — see `main.dart`.
class _ManagedWindow {
  _ManagedWindow({required this.argument, required this.title, required this.size});

  final String argument;
  final String title;
  final Size size;

  WindowController? _controller;

  bool get isOpen => _controller != null;

  Future<void> open() async {
    // Closing with the red button (or ⌘W) never reaches Dart: the plugin drops
    // the window natively, and `show()` on a dropped id is a silent no-op. So
    // a remembered controller can be dead, and reusing it opens nothing.
    if (_controller != null &&
        !(await DesktopMultiWindow.getAllSubWindowIds()).contains(_controller!.windowId)) {
      _controller = null;
    }
    if (_controller != null) {
      try {
        await _controller!.show();
        await _activateApp();
        return;
      } catch (e) {
        debugPrint('Failed to focus existing $argument window: $e');
        _controller = null;
      }
    }

    try {
      final window = await DesktopMultiWindow.createWindow(argument);
      await window.setFrame(const Offset(100, 100) & size);
      await window.setTitle(title);
      await window.center();
      await window.show();
      _controller = window;
      await _activateApp();
      debugPrint('$argument window opened with ID: ${window.windowId}');
    } catch (e) {
      debugPrint('Failed to open $argument window: $e');
      _controller = null;
    }
  }

  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      await controller.close();
    } catch (e) {
      debugPrint('Failed to close $argument window: $e');
    }
  }

  /// The app is a menu bar accessory, so a new window opens behind whatever
  /// the user is in unless the app is activated. On first launch that would
  /// leave a friend looking at nothing.
  static Future<void> _activateApp() async {
    try {
      await const MethodChannel('com.glassywhisper.app_lifecycle').invokeMethod('activateApp');
    } catch (e) {
      debugPrint('Could not activate the app: $e');
    }
  }
}

/// Opens and closes the settings and setup windows.
class SettingsWindowService {
  final _settings = _ManagedWindow(
    argument: 'settings',
    title: 'Settings - UltraWhisper',
    size: const Size(700, 600),
  );

  final _setup = _ManagedWindow(
    argument: 'setup',
    title: 'Welcome to UltraWhisper',
    size: const Size(760, 640),
  );

  bool get isSettingsWindowOpen => _settings.isOpen;
  bool get isSetupWindowOpen => _setup.isOpen;

  Future<void> openSettingsWindow() => _settings.open();
  Future<void> closeSettingsWindow() => _settings.close();

  Future<void> openSetupWindow() => _setup.open();
  Future<void> closeSetupWindow() => _setup.close();

  void dispose() {}
}
