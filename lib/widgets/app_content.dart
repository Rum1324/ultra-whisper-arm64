import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_service.dart';
import 'floating_overlay.dart';
import 'meeting_panel.dart';

class AppContent extends StatelessWidget {
  const AppContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppService>(
      builder: (context, appService, child) {
        // A meeting takes over the window while it lasts. The two surfaces
        // cannot be shown together: the same window is a 360x100 dictation
        // overlay and a 420x520 meeting panel, and dictation is refused during
        // a meeting anyway because both want the one microphone.
        final showMeeting = appService.pendingMeetingPrompt != null ||
            appService.isMeetingActive;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: showMeeting ? const MeetingPanel() : const FloatingOverlay(),
        );
      },
    );
  }
}
