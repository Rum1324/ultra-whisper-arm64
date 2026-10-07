import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../services/app_service.dart';
import '../theme/focus_theme.dart';
import 'focus_controls.dart';

class FloatingOverlay extends StatefulWidget {
  const FloatingOverlay({super.key});

  @override
  State<FloatingOverlay> createState() => _FloatingOverlayState();
}

class _FloatingOverlayState extends State<FloatingOverlay>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  final List<double> _waveformHeights = List.generate(32, (index) => 0.1);
  final List<double> _frequencyBands = List.generate(8, (index) => 0.1);
  final List<double> _peakHeights = List.generate(32, (index) => 0.1);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 50),
      vsync: this,
    );
    _animationController.repeat();
  }

  @override
  void dispose() {
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
          padding: const EdgeInsets.only(left: 14),
          decoration: const BoxDecoration(
            color: FocusIsland.ground,
            borderRadius: BorderRadius.all(FocusRadius.r26),
          ),
          child: Row(
            children: [
              // Left: what is happening, as a dot and a word
              _buildStatus(state),

              // Middle: live audio waveform
              _buildAudioWaveform(state),

              // Right: record button and menu
              _buildRecordButton(context, appService),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatus(AppState state) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FocusLevelDot(_levelFor(state.recordingState), size: 8),
        const SizedBox(width: 7),
        SizedBox(
          width: 58,
          child: Text(
            _wordFor(state.recordingState),
            style: FocusText.islandMeta.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: FocusIsland.ink,
            ),
          ),
        ),
      ],
    );
  }

  /// The dot is a glance aid; this word is the message.
  String _wordFor(RecordingState state) => switch (state) {
        RecordingState.idle => 'Ready',
        RecordingState.recording => 'Listening',
        RecordingState.processing => 'Writing',
        RecordingState.error => 'Error',
      };

  /// Which Focus level dot each recording state shows. Only an error pulses:
  /// idle sits on screen for hours, and a pulsing dot there would keep a
  /// ticker running the whole time.
  FocusLevel _levelFor(RecordingState state) => switch (state) {
        RecordingState.idle => FocusLevel.offline,
        RecordingState.recording => FocusLevel.calm,
        RecordingState.processing => FocusLevel.watch,
        RecordingState.error => FocusLevel.risk,
      };

  Widget _buildAudioWaveform(AppState state) {
    // Update waveform heights based on current audio level
    _updateWaveformData(state);

    return Expanded(
      child: SizedBox(
        height: double.infinity,
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Generate multiple bars for waveform effect
                for (int i = 0; i < 32; i++) _buildWaveformBar(state, i),
              ],
            );
          },
        ),
      ),
    );
  }

  void _updateWaveformData(AppState state) {
    double rawAudioLevel = state.audioLevel / 100.0;
    double normalizedLevel = rawAudioLevel.clamp(0.0, 1.0);
    double animationValue = _animationController.value;

    if (state.recordingState == RecordingState.recording) {
      // Real-time audio analysis for recording state
      _analyzeAudioLevel(normalizedLevel, animationValue);
    } else if (state.recordingState == RecordingState.processing) {
      // Pulsing effect during processing
      _createProcessingEffect(animationValue);
    } else {
      // Minimal idle animation
      _createIdleEffect(animationValue);
    }
  }

  void _analyzeAudioLevel(double audioLevel, double animationValue) {
    // Apply logarithmic scaling for better visual response
    double enhancedLevel = math.log(1 + audioLevel * 9) / math.log(10);
    enhancedLevel = enhancedLevel.clamp(0.0, 1.0);

    // Analyze frequency bands for more realistic visualization
    _analyzeFrequencyBands(enhancedLevel, animationValue);

    // Create frequency-based variation that responds to audio level
    for (int i = 0; i < _waveformHeights.length; i++) {
      double time = animationValue * 2 * math.pi;
      double barPosition = i / _waveformHeights.length;

      // Get frequency band influence (speech has different frequency characteristics)
      int bandIndex = ((i * 8) / _waveformHeights.length).clamp(0, 7).toInt();
      double bandInfluence = _frequencyBands[bandIndex];

      // Multiple frequency components for natural speech-like waveform
      double baseFreq = math.sin(time * 3 + barPosition * 6) * 0.4;
      double midFreq = math.sin(time * 7 + barPosition * 4) * 0.3;
      double highFreq = math.sin(time * 12 + barPosition * 2) * 0.2;

      // Combine frequencies and scale by actual audio level and frequency bands
      double waveVariation =
          (baseFreq + midFreq + highFreq) * enhancedLevel * bandInfluence;

      // Center bars should be more prominent (like a real microphone)
      double centerDistance = (barPosition - 0.5).abs();
      double centerWeight = (1.0 - centerDistance * 1.2).clamp(0.4, 1.0);

      // Base level that responds strongly to audio input
      double baseResponse = enhancedLevel * centerWeight * bandInfluence;

      // Add some randomness for more natural appearance
      double randomFactor = 0.1 * math.sin(time * 20 + i * 0.5);

      // Final height combines base response with wave variation and randomness
      double finalHeight =
          (baseResponse * 0.6) +
          (waveVariation * 0.3) +
          (randomFactor * 0.1) +
          0.1;

      // Smooth transitions
      _waveformHeights[i] = _waveformHeights[i] * 0.7 + finalHeight * 0.3;
      _waveformHeights[i] = _waveformHeights[i].clamp(0.1, 1.0);

      // Update peak heights for visual effect
      if (_waveformHeights[i] > _peakHeights[i]) {
        _peakHeights[i] = _waveformHeights[i];
      } else {
        _peakHeights[i] = _peakHeights[i] * 0.95;
      }
      _peakHeights[i] = _peakHeights[i].clamp(0.1, 1.0);
    }
  }

  void _analyzeFrequencyBands(double audioLevel, double animationValue) {
    // Simulate frequency band analysis for speech
    // Speech typically has energy in these frequency ranges:
    // 85-255 Hz (vowels), 255-2000 Hz (consonants), 2000-8000 Hz (sibilants)

    double time = animationValue * 2 * math.pi;

    // Low frequencies (vowels) - more prominent
    _frequencyBands[0] = (audioLevel * 0.8 + 0.2 * math.sin(time * 2)) * 1.2;
    _frequencyBands[1] = (audioLevel * 0.9 + 0.1 * math.sin(time * 3)) * 1.1;

    // Mid frequencies (consonants) - moderate
    _frequencyBands[2] = (audioLevel * 0.7 + 0.3 * math.sin(time * 4)) * 1.0;
    _frequencyBands[3] = (audioLevel * 0.6 + 0.4 * math.sin(time * 5)) * 0.9;
    _frequencyBands[4] = (audioLevel * 0.5 + 0.5 * math.sin(time * 6)) * 0.8;

    // High frequencies (sibilants) - less prominent but present
    _frequencyBands[5] = (audioLevel * 0.4 + 0.6 * math.sin(time * 8)) * 0.7;
    _frequencyBands[6] = (audioLevel * 0.3 + 0.7 * math.sin(time * 10)) * 0.6;
    _frequencyBands[7] = (audioLevel * 0.2 + 0.8 * math.sin(time * 12)) * 0.5;

    // Clamp all values
    for (int i = 0; i < _frequencyBands.length; i++) {
      _frequencyBands[i] = _frequencyBands[i].clamp(0.1, 1.0);
    }
  }

  void _createProcessingEffect(double animationValue) {
    // Create a pulsing wave effect during processing
    double pulse = math.sin(animationValue * 6 * math.pi) * 0.5 + 0.5;

    for (int i = 0; i < _waveformHeights.length; i++) {
      double barPosition = i / _waveformHeights.length;
      double wave =
          math.sin(animationValue * 4 * math.pi + barPosition * 8) * 0.3;
      _waveformHeights[i] = ((pulse * 0.7 + wave * 0.3) * 0.8).clamp(0.1, 1.0);
      _peakHeights[i] = _waveformHeights[i];
    }
  }

  void _createIdleEffect(double animationValue) {
    // Subtle breathing effect when idle
    for (int i = 0; i < _waveformHeights.length; i++) {
      double time = animationValue * 2 * math.pi;
      double barPosition = i / _waveformHeights.length;

      // Very subtle wave pattern
      double idle = (math.sin(time * 0.5 + barPosition * 4) * 0.05 + 0.1).clamp(0.1, 1.0);
      _waveformHeights[i] = idle;
      _peakHeights[i] = idle;
    }
  }

  Widget _buildWaveformBar(AppState state, int index) {
    const baseHeight = 3.0;
    const maxHeight = 30.0;

    final heightMultiplier = _waveformHeights[index].clamp(0.0, 1.0);
    final barHeight = baseHeight + maxHeight * heightMultiplier;

    // Plain island ink at three strengths: Focus keeps colour for state, and
    // the dot beside the waveform already carries it.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 30),
      width: 3,
      height: barHeight,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: _getWaveformColor(state.recordingState),
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }

  Color _getWaveformColor(RecordingState state) {
    switch (state) {
      case RecordingState.recording:
        return FocusIsland.ink;
      case RecordingState.processing:
        return FocusIsland.ink2;
      case RecordingState.idle:
      case RecordingState.error:
        return FocusIsland.ink3;
    }
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
