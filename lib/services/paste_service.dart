import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/settings.dart';
import 'keystroke_service.dart';

class PasteService {
  final KeystrokeService _keystrokeService = KeystrokeService();
  Future<void> performPasteAction(String text, PasteAction action) async {
    try {
      switch (action) {
        case PasteAction.paste:
          await _pasteWithClipboardPreservation(text, false);
          break;
        case PasteAction.pasteWithEnter:
          await _pasteWithClipboardPreservation(text, true);
          break;
        case PasteAction.clipboardOnly:
          await _copyToClipboard(text);
          break;
      }
      debugPrint('Paste action completed: $action');
    } catch (e) {
      debugPrint('Failed to perform paste action: $e');
      throw Exception('Paste action failed: $e');
    }
  }
  
  Future<void> _pasteWithClipboardPreservation(String text, bool pressEnter) async {
    try {
      debugPrint('');
      debugPrint('=== PASTE OPERATION STARTING ===');
      debugPrint('Text to paste: "$text"');
      debugPrint('Press Enter after: $pressEnter');

      // 1. Read current clipboard contents
      final originalClipboard = await _getClipboardData();
      debugPrint('✅ Step 1: Read original clipboard: "${originalClipboard?.text}"');

      // 2. Set transcript to clipboard
      await _copyToClipboard(text);
      debugPrint('✅ Step 2: Copied transcription to clipboard');

      // Verify clipboard was actually set
      final verifyClipboard = await _getClipboardData();
      if (verifyClipboard?.text == text) {
        debugPrint('✅ Step 2b: Verified clipboard contains our text');
      } else {
        debugPrint('❌ Step 2b: Clipboard verification failed! Expected: "$text", Got: "${verifyClipboard?.text}"');
      }

      // 3. Check accessibility permissions first
      final hasPermission = await hasAccessibilityPermission();
      debugPrint('🔑 Step 3: Accessibility permission status: $hasPermission');
      
      if (!hasPermission) {
        debugPrint('Accessibility permission not granted - requesting permission');
        try {
          await requestAccessibilityPermission();
          debugPrint('Accessibility permission request completed');
        } catch (e) {
          debugPrint('Failed to request accessibility permission: $e');
        }
      }
      
      // 4. Attempt to send keystrokes via platform channel
      try {
        debugPrint('🎯 Step 4: Attempting to send Cmd+V keystroke...');
        await _keystrokeService.sendKeystroke('cmd+v');
        debugPrint('✅ Step 4: Successfully sent Cmd+V keystroke');

        // 5. Optionally press Enter
        if (pressEnter) {
          await Future.delayed(const Duration(milliseconds: 100));
          debugPrint('🎯 Step 5: Attempting to send Enter keystroke...');
          await _keystrokeService.sendKeystroke('enter');
          debugPrint('✅ Step 5: Successfully sent Enter keystroke');
        }

        // 6. Restore clipboard with proper ordering after successful paste
        debugPrint('⏱️ Step 6: Scheduling clipboard restore in 500ms');
        _scheduleClipboardRestoreWithOrdering(text, originalClipboard);
        debugPrint('=== PASTE OPERATION COMPLETED SUCCESSFULLY ===');
        debugPrint('');

      } catch (e) {
        debugPrint('❌ Step 4: FAILED to send keystrokes via platform channel');
        debugPrint('Error: $e');
        debugPrint('Error type: ${e.runtimeType}');
        debugPrint('Stack trace: ${StackTrace.current}');
        
        // Check if it's a permission issue
        if (e.toString().contains('Accessibility permission required')) {
          debugPrint('Permission issue detected - requesting accessibility access');
          try {
            await requestAccessibilityPermission();
          } catch (permError) {
            debugPrint('Failed to request permission: $permError');
          }
        }
        
        debugPrint('Note: Transcription copied to clipboard. User should manually paste with Cmd+V');
        debugPrint('Text ready for pasting: $text');
        
        // Fall back to delayed clipboard restoration for manual pasting
        // Give user more time to paste manually in production
        _scheduleClipboardRestoreForManualPaste(text, originalClipboard);
      }
      
      debugPrint('Clipboard-preserving paste completed');
    } catch (e) {
      debugPrint('Error in clipboard-preserving paste: $e');
      rethrow;
    }
  }
  
  Future<ClipboardData?> _getClipboardData() async {
    try {
      return await Clipboard.getData(Clipboard.kTextPlain);
    } catch (e) {
      debugPrint('Error getting clipboard data: $e');
      return null;
    }
  }
  
  Future<void> _restoreClipboardData(ClipboardData? data) async {
    try {
      if (data != null && data.text != null) {
        await Clipboard.setData(data);
      }
    } catch (e) {
      debugPrint('Error restoring clipboard data: $e');
    }
  }
  
  Future<void> _copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      debugPrint('Successfully copied to clipboard: $text');
    } catch (e) {
      debugPrint('Error copying to clipboard: $e');
      throw Exception('Failed to copy to clipboard: $e');
    }
  }
  
  Future<void> sendKeystroke(String keystroke) async {
    // Delegate to the keystroke service which uses platform channel
    await _keystrokeService.sendKeystroke(keystroke);
  }
  
  Future<void> sendKeySequence(List<String> keystrokes, {int delayMs = 100}) async {
    // Delegate to the keystroke service which handles the sequence and delays
    await _keystrokeService.sendKeySequence(keystrokes, delayMs: delayMs);
  }
  
  void _scheduleClipboardRestoreWithOrdering(String transcribedText, ClipboardData? originalClipboard) {
    // Simple clipboard restoration after paste completes
    Timer(const Duration(milliseconds: 500), () async {
      // Simply restore the original clipboard content
      if (originalClipboard != null && originalClipboard.text != null && originalClipboard.text!.isNotEmpty) {
        await _restoreClipboardData(originalClipboard);
        debugPrint('Restored original clipboard: ${originalClipboard.text}');
      }
    });
  }

  void _scheduleClipboardRestoreForManualPaste(String transcribedText, ClipboardData? originalClipboard) {
    // Extended timing for manual paste in production builds
    debugPrint('Scheduling extended clipboard restoration for manual pasting');
    debugPrint('User has 10 seconds to manually paste: $transcribedText');
    
    Timer(const Duration(seconds: 10), () async {
      debugPrint('Manual paste window expired - restoring original clipboard');
      
      if (originalClipboard != null && originalClipboard.text != null && originalClipboard.text!.isNotEmpty) {
        await _restoreClipboardData(originalClipboard);
        debugPrint('Restored original clipboard after manual paste window: ${originalClipboard.text}');
      }
    });
  }
  
  /// Check if accessibility permissions are granted for keystroke sending
  Future<bool> hasAccessibilityPermission() async {
    try {
      return await _keystrokeService.hasAccessibilityPermission();
    } catch (e) {
      debugPrint('Error checking accessibility permission: $e');
      return false;
    }
  }
  
  /// Request accessibility permissions (opens System Preferences)
  Future<void> requestAccessibilityPermission() async {
    try {
      await _keystrokeService.requestAccessibilityPermission();
    } catch (e) {
      debugPrint('Error requesting accessibility permission: $e');
      throw Exception('Failed to request accessibility permission: $e');
    }
  }
}