import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../models/app_state.dart';
import '../models/settings.dart';
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
class FloatingOverlay extends StatefulWidget {
  const FloatingOverlay({super.key});

  @override
  State<FloatingOverlay> createState() => _FloatingOverlayState();
}

class _FloatingOverlayState extends State<FloatingOverlay>
    with SingleTickerProviderStateMixin {
  // Focus motion: a new object rises 8px and fades in over 0.22s, ease-out.
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 160),
  );
  late final AppService _appService;

  /// What the island last showed, kept on screen while it fades out.
  AppState? _shown;

  @override
  void initState() {
    super.initState();
    _appService = context.read<AppService>();
    _appService.addListener(_sync);
    _appear.addStatusListener((status) {
      // Fully faded out: drop the island, and the orb's ticker with it.
      if (status == AnimationStatus.dismissed) setState(() => _shown = null);
    });
    _sync();
  }

  void _sync() {
    final state = _appService.state;
    final show = state.isOverlayVisible &&
        state.recordingState != RecordingState.idle;
    if (show) {
      _shown = state;
      if (_appear.status != AnimationStatus.forward &&
          _appear.status != AnimationStatus.completed) {
        _appear.forward();
      }
    } else if (_shown != null &&
        _appear.status != AnimationStatus.reverse &&
        _appear.status != AnimationStatus.dismissed) {
      _appear.reverse();
    }
  }

  @override
  void dispose() {
    _appService.removeListener(_sync);
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild on every state change; which state to draw comes from _sync.
    context.watch<AppService>();
    final shown = _shown;
    if (shown == null) return const SizedBox.expand();

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: AnimatedBuilder(
          animation: _appear,
          builder: (context, _) {
            final t = Curves.easeOut.transform(_appear.value);
            // No opacity layer: the fade is drawn into the island's own
            // colours, and the rise is a plain translate. An Opacity or
            // FadeTransition would composite offscreen, and on Skia its
            // first use stalls on shader compilation, which is the stutter
            // the island used to show as it appeared.
            return Transform.translate(
              offset: Offset(0, 8 * (1 - t)),
              child: _Island(
                state: shown,
                expressiveness: _appService.settings.orbExpressiveness,
                opacity: t,
                onStop: _appService.stopRecording,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Island extends StatelessWidget {
  const _Island({
    required this.state,
    required this.expressiveness,
    required this.opacity,
    required this.onStop,
  });

  final AppState state;
  final OrbExpressiveness expressiveness;
  final double opacity;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final recording = state.recordingState == RecordingState.recording;
    final error = state.recordingState == RecordingState.error;
    Color fade(Color c) => c.withValues(alpha: c.a * opacity);

    final island = Container(
      height: 44,
      constraints: const BoxConstraints(maxWidth: 340),
      padding: EdgeInsets.fromLTRB(error ? 16 : 6, 0, 18, 0),
      decoration: BoxDecoration(
        color: fade(FocusIsland.ground),
        borderRadius: const BorderRadius.all(FocusRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: fade(FocusIsland.levelRisk),
                shape: BoxShape.circle,
              ),
            )
          else
            ThinkingOrb(
              level: recording ? state.audioLevel : 0,
              mode: recording ? OrbMode.listening : OrbMode.writing,
              opacity: opacity,
              expressiveness: expressiveness,
            ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              _label(),
              overflow: TextOverflow.ellipsis,
              style: FocusText.islandNow.copyWith(
                fontSize: 13,
                color: fade(FocusIsland.ink),
              ),
            ),
          ),
          if (recording) ...[
            const SizedBox(width: 10),
            Text(
              _clock(state.recordingDuration),
              style: FocusText.islandMeta.copyWith(
                fontSize: 13,
                color: fade(FocusIsland.ink2),
              ),
            ),
          ],
        ],
      ),
    );

    // Dragging the island moves the window, in every state. The gesture
    // arena keeps this apart from the tap: a press that moves past the slop
    // becomes a drag, one that does not stays a click.
    final movable = GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onTap: recording ? onStop : null,
      child: island,
    );

    if (!recording) return movable;

    // The whole island is the stop button: one target, nothing to aim for.
    return Tooltip(
      message: 'Click to stop · drag to move',
      child: Semantics(
        button: true,
        label: 'Stop recording',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: movable,
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
