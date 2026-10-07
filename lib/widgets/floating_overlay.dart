import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../services/app_service.dart';
import '../theme/focus_theme.dart';
import 'thinking_orb.dart';

/// The dictation overlay: one small black island, and only while there is
/// something to say.
///
/// - Idle: nothing. Recording starts from the hotkey or the menu bar, which
///   also holds Settings and Quit, so the overlay carries no controls of its
///   own. The window lets clicks through meanwhile (see main.dart).
/// - Recording: the orb following your voice, "Listening" and the elapsed
///   time. The island is the stop button.
/// - Writing: the orb settles to a slow swell.
/// - Error: a red dot and the message.
///
/// The orb is unmounted while idle, and with it its ticker: the window is
/// always on screen, so anything left animating would cost CPU all day.
class FloatingOverlay extends StatelessWidget {
  const FloatingOverlay({super.key});

  static const _enter = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppService>(
      builder: (context, appService, child) {
        final state = appService.state;
        final show = state.isOverlayVisible &&
            state.recordingState != RecordingState.idle;

        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            // Focus motion: a new object rises 8px and fades in over 0.22s.
            child: AnimatedSwitcher(
              duration: _enter,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.2),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, if (current != null) current],
              ),
              child: show
                  ? _Island(
                      key: ValueKey(state.recordingState),
                      state: state,
                      onStop: appService.stopRecording,
                    )
                  : const SizedBox.shrink(key: ValueKey('hidden')),
            ),
          ),
        );
      },
    );
  }
}

class _Island extends StatelessWidget {
  const _Island({super.key, required this.state, required this.onStop});

  final AppState state;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final recording = state.recordingState == RecordingState.recording;
    final error = state.recordingState == RecordingState.error;

    final island = Container(
      height: 44,
      constraints: const BoxConstraints(maxWidth: 340),
      padding: EdgeInsets.fromLTRB(error ? 16 : 6, 0, 18, 0),
      decoration: const BoxDecoration(
        color: FocusIsland.ground,
        borderRadius: BorderRadius.all(FocusRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error)
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: FocusIsland.levelRisk,
                shape: BoxShape.circle,
              ),
            )
          else
            ThinkingOrb(
              level: recording ? state.audioLevel : 0,
              mode: recording ? OrbMode.listening : OrbMode.writing,
            ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              _label(),
              overflow: TextOverflow.ellipsis,
              style: FocusText.islandNow.copyWith(fontSize: 13),
            ),
          ),
          if (recording) ...[
            const SizedBox(width: 10),
            Text(
              _clock(state.recordingDuration),
              style: FocusText.islandMeta.copyWith(fontSize: 13),
            ),
          ],
        ],
      ),
    );

    if (!recording) return island;

    // The whole island is the stop button: one target, nothing to aim for.
    return Tooltip(
      message: 'Click to stop',
      child: Semantics(
        button: true,
        label: 'Stop recording',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(onTap: onStop, child: island),
        ),
      ),
    );
  }

  String _label() => switch (state.recordingState) {
        RecordingState.recording => 'Listening',
        RecordingState.processing => 'Writing',
        RecordingState.error => state.errorMessage ?? 'Something went wrong.',
        RecordingState.idle => '',
      };

  /// Elapsed time as it is said: 0:07, 1:32.
  static String _clock(Duration d) {
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inMinutes}:$s';
  }
}
