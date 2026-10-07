import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../services/app_service.dart';
import '../theme/focus_theme.dart';
import 'thinking_orb.dart';

class FloatingOverlay extends StatefulWidget {
  const FloatingOverlay({super.key});

  @override
  State<FloatingOverlay> createState() => _FloatingOverlayState();
}

class _FloatingOverlayState extends State<FloatingOverlay>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AppService _appService;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 50),
      vsync: this,
    );
    _appService = context.read<AppService>();
    _appService.addListener(_syncAnimation);
    _syncAnimation();
  }

  /// Ticks only while there is audio to show. The overlay window is always on
  /// screen, so a ticker left repeating renders a frame on every display
  /// refresh for as long as the app runs — ~30% CPU while doing nothing.
  void _syncAnimation() {
    final state = _appService.state;
    final active = state.isOverlayVisible &&
        (state.recordingState == RecordingState.recording ||
            state.recordingState == RecordingState.processing);
    if (active && !_animationController.isAnimating) {
      _animationController.repeat();
    } else if (!active && _animationController.isAnimating) {
      _animationController.stop();
    }
  }

  @override
  void dispose() {
    _appService.removeListener(_syncAnimation);
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppService>(
      builder: (context, appService, child) {
        final state = appService.state;

        if (!state.isOverlayVisible) {
          return const SizedBox.shrink();
        }

        // A Focus island: black in both appearances, because it floats over
        // whatever app is in front.
        return Container(
          width: double.infinity,
          height: double.infinity,
          margin: const EdgeInsets.fromLTRB(8, 34, 8, 8),
          padding: const EdgeInsets.only(left: 7),
          decoration: const BoxDecoration(
            color: FocusIsland.ground,
            borderRadius: BorderRadius.all(FocusRadius.r26),
          ),
          child: Row(
            children: [
              // Left: the listening orb, swelling with your voice
              _buildOrb(state),
              const SizedBox(width: 8),

              // Middle: what is happening, in a word
              Expanded(child: _buildStatus(state)),

              // Right: record button and menu
              _buildRecordButton(context, appService),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatus(AppState state) {
    return Text(
      _wordFor(state.recordingState),
      overflow: TextOverflow.ellipsis,
      style: FocusText.islandNow.copyWith(
        fontSize: 13,
        color: state.recordingState == RecordingState.idle
            ? FocusIsland.ink2
            : FocusIsland.ink,
      ),
    );
  }

  /// The orb is a glance aid; this word is the message.
  String _wordFor(RecordingState state) => switch (state) {
        RecordingState.idle => 'Ready',
        RecordingState.recording => 'Listening',
        RecordingState.processing => 'Writing',
        RecordingState.error => 'Error',
      };

  /// The orb moves only while the ticker runs (recording and processing).
  /// Recording follows the microphone; processing settles to a slow, low
  /// swell; idle and error hold a still frame.
  Widget _buildOrb(AppState state) {
    final recording = state.recordingState == RecordingState.recording;
    final processing = state.recordingState == RecordingState.processing;
    return ThinkingOrb(
      repaint: _animationController,
      level: recording ? (state.audioLevel / 100.0).clamp(0.0, 1.0) : 0,
      speed: processing ? 0.5 : 1,
      size: 44,
    );
  }

  Widget _buildRecordButton(BuildContext context, AppService appService) {
    final state = appService.state;
    final isRecording = state.recordingState == RecordingState.recording;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Record/Stop. While recording, Stop is the one thing the island
          // offers, so it inverts to the prominent white pill.
          Semantics(
            button: true,
            label: isRecording ? 'Stop recording' : 'Start recording',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  if (state.recordingState == RecordingState.idle) {
                    appService.startRecording();
                  } else if (state.recordingState == RecordingState.recording) {
                    appService.stopRecording();
                  }
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isRecording ? FocusIsland.ink : FocusIsland.fill,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isRecording ? Icons.stop : Icons.mic,
                    color: isRecording ? FocusIsland.ground : FocusIsland.ink,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          // Settings menu
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_horiz,
              color: FocusIsland.ink2,
              size: 18,
            ),
            tooltip: 'More',
            onSelected: (value) => _handleMenuAction(context, value, appService),
            itemBuilder: (context) {
              final c = FocusColors.of(context);
              return [
                const PopupMenuItem(
                  value: 'settings',
                  child: Text('Settings'),
                ),
                PopupMenuItem(
                  value: 'quit',
                  child: Text('Quit', style: TextStyle(color: c.bad)),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(
    BuildContext context,
    String action,
    AppService appService,
  ) {
    switch (action) {
      case 'settings':
        appService.openSettingsWindow();
        break;
      case 'quit':
        // Add quit functionality
        break;
    }
  }

}
