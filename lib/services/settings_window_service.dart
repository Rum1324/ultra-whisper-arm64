import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

/// Service for managing the settings window
class SettingsWindowService {
  WindowController? _settingsWindowController;
  bool _isSettingsWindowOpen = false;
  int? _settingsWindowId;

  bool get isSettingsWindowOpen => _isSettingsWindowOpen;
  int? get settingsWindowId => _settingsWindowId;

  /// Opens the settings window as a separate window
  Future<void> openSettingsWindow() async {
    // If window is already open, just focus it
    if (_isSettingsWindowOpen && _settingsWindowController != null) {
      try {
        _settingsWindowController!.show();
        return;
      } catch (e) {
        debugPrint('Failed to focus existing settings window: $e');
        _isSettingsWindowOpen = false;
        _settingsWindowController = null;
      }
    }

    try {
      // Create a new window
      final window = await DesktopMultiWindow.createWindow('settings');

      // Configure the window
      window
        ..setFrame(const Offset(100, 100) & const Size(700, 600))
        ..setTitle('Settings - UltraWhisper')
        ..center()
        ..show();

      _settingsWindowController = window;
      _settingsWindowId = window.windowId;
      _isSettingsWindowOpen = true;

      debugPrint('Settings window opened successfully with ID: $_settingsWindowId');
    } catch (e) {
      debugPrint('Failed to open settings window: $e');
      _isSettingsWindowOpen = false;
      _settingsWindowController = null;
      _settingsWindowId = null;
    }
  }

  /// Closes the settings window
  Future<void> closeSettingsWindow() async {
    if (_settingsWindowController != null) {
      try {
        await _settingsWindowController!.close();
      } catch (e) {
        debugPrint('Failed to close settings window: $e');
      }
    }
    _markWindowClosed();
  }

  /// Called when the settings window closes (either programmatically or by user)
  void onSettingsWindowClosed() {
    debugPrint('Settings window closed notification received');
    _markWindowClosed();
  }

  /// Internal method to mark window as closed
  void _markWindowClosed() {
    _settingsWindowController = null;
    _settingsWindowId = null;
    _isSettingsWindowOpen = false;
    debugPrint('Settings window state reset');
  }

  /// Disposes the service
  void dispose() {
    _markWindowClosed();
  }
}
