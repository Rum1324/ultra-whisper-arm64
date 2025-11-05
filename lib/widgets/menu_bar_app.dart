import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../services/app_service.dart';
import 'settings_window.dart';

class MenuBarApp extends StatelessWidget {
  const MenuBarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppService>(
      builder: (context, appService, child) {
        final state = appService.state;
        
        return PopupMenuButton<String>(
          icon: Icon(
            _getStatusIcon(state.recordingState),
            color: _getStatusColor(state.recordingState),
            size: 18,
          ),
          tooltip: 'UltraWhisper',
          onSelected: (value) => _handleMenuSelection(context, value, appService),
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'toggle_recording',
              enabled: state.recordingState == RecordingState.idle ||
                       state.recordingState == RecordingState.recording,
              child: Row(
                children: [
                  Icon(
                    state.recordingState == RecordingState.recording
                        ? Icons.stop
                        : Icons.mic,
                    size: 16,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    state.recordingState == RecordingState.recording
                        ? 'Stop Recording'
                        : 'Start Recording',
                  ),
                ],
              ),
            ),
            
            const PopupMenuDivider(),
            
            PopupMenuItem<String>(
              value: 'toggle_overlay',
              child: Row(
                children: [
                  Icon(
                    state.isOverlayVisible
                        ? Icons.visibility_off
                        : Icons.visibility,
                    size: 16,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    state.isOverlayVisible
                        ? 'Hide Overlay'
                        : 'Show Overlay',
                  ),
                ],
              ),
            ),
            
            PopupMenuItem<String>(
              value: 'toggle_partial_text',
              child: Row(
                children: [
                  Icon(
                    state.isPartialTextVisible
                        ? Icons.text_fields_outlined
                        : Icons.text_fields,
                    size: 16,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    state.isPartialTextVisible
                        ? 'Hide Partial Text'
                        : 'Show Partial Text',
                  ),
                ],
              ),
            ),
            
            const PopupMenuDivider(),
            
            PopupMenuItem<String>(
              value: 'test_manual_record',
              child: Row(
                children: [
                  Icon(
                    Icons.mic_outlined,
                    size: 16,
                    color: Colors.blue[600],
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Test Manual Recording',
                    style: TextStyle(color: Colors.blue[600]),
                  ),
                ],
              ),
            ),
            
            PopupMenuItem<String>(
              value: 'settings',
              child: Row(
                children: [
                  Icon(
                    Icons.settings,
                    size: 16,
                    color: Colors.grey[700],
                  ),
                  SizedBox(width: 8),
                  Text('Settings...'),
                ],
              ),
            ),
            
            const PopupMenuDivider(),
            
            PopupMenuItem<String>(
              value: 'quit',
              child: Row(
                children: [
                  Icon(
                    Icons.exit_to_app,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Quit UltraWhisper',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
  
  void _handleMenuSelection(BuildContext context, String value, AppService appService) {
    switch (value) {
      case 'toggle_recording':
        appService.toggleRecording();
        break;
        
      case 'toggle_overlay':
        appService.toggleOverlayVisibility();
        break;
        
      case 'toggle_partial_text':
        appService.togglePartialTextVisibility();
        break;
        
      case 'test_manual_record':
        _handleManualRecordTest(appService);
        break;
        
      case 'settings':
        _showSettingsWindow(context);
        break;
        
      case 'quit':
        _quitApplication();
        break;
    }
  }
  
  void _handleManualRecordTest(AppService appService) {
    // Test manual recording - simulate a quick record/stop cycle
    Future.microtask(() async {
      if (appService.state.recordingState == RecordingState.idle) {
        await appService.startRecording();
        // Record for 3 seconds then stop
        await Future.delayed(const Duration(seconds: 3));
        await appService.stopRecording();
      } else if (appService.state.recordingState == RecordingState.recording) {
        await appService.stopRecording();
      }
    });
  }
  
  void _showSettingsWindow(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const SettingsWindow(),
      barrierDismissible: true,
    );
  }
  
  void _quitApplication() {
    // In a real app, this would properly clean up resources
    // and quit the application gracefully
    exit(0);
  }
  
  IconData _getStatusIcon(RecordingState state) {
    switch (state) {
      case RecordingState.idle:
        return Icons.mic_none;
      case RecordingState.recording:
        return Icons.fiber_manual_record;
      case RecordingState.processing:
        return Icons.hourglass_empty;
      case RecordingState.error:
        return Icons.error_outline;
    }
  }
  
  Color _getStatusColor(RecordingState state) {
    switch (state) {
      case RecordingState.idle:
        return Colors.grey[600]!;
      case RecordingState.recording:
        return Colors.red[600]!;
      case RecordingState.processing:
        return Colors.orange[600]!;
      case RecordingState.error:
        return Colors.red[700]!;
    }
  }
}