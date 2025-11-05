import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../services/app_service.dart';

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

  // Audio analysis parameters
  final int _sampleRate = 16000;
  final int _fftSize = 256;
  final List<double> _audioBuffer = [];
  final int _bufferSize = 1024;

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

        return Container(
          width: double.infinity,
          height: double.infinity,
          margin: const EdgeInsets.fromLTRB(8, 34, 8, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1.5,
            ),
            boxShadow: [
              // Outer shadow for depth
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 12,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
              // Inner highlight for glass effect
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.1),
                blurRadius: 6,
                spreadRadius: -1,
                offset: const Offset(0, -2),
              ),
            ],
            // Subtle background to enhance visibility
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.08),
                Colors.white.withValues(alpha: 0.02),
              ],
            ),
          ),
          child: Row(
            children: [
              // Left: Live audio waveform
              _buildAudioWaveform(state),

              // Right: Record button
              _buildRecordButton(context, appService),
            ],
          ),
        );
      },
    );
  }

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
    double baseHeight = 3.0;
    double maxHeight = 80.0;

    double heightMultiplier = _waveformHeights[index].clamp(0.0, 1.0);
    double barHeight = (baseHeight + (maxHeight * heightMultiplier)).clamp(baseHeight, baseHeight + maxHeight);

    // Add peak indicator
    double peakHeight = (_peakHeights[index] * maxHeight * 0.1).clamp(0.0, maxHeight * 0.2);

    Color barColor = _getWaveformColor(state.recordingState);
    Color peakColor = _getPeakColor(state.recordingState);

    // Ensure total height is always positive
    double totalHeight = (barHeight + peakHeight).clamp(baseHeight, baseHeight + maxHeight + (maxHeight * 0.2));

    return Container(
      width: 4,
      height: totalHeight,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Main bar
          Positioned(
            bottom: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 30),
              width: 4,
              height: barHeight.clamp(1.0, double.infinity),
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: barColor.withValues(alpha: 0.3),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
            ),
          ),
          // Peak indicator
          if (state.recordingState == RecordingState.recording &&
              peakHeight > 2)
            Positioned(
              top: 0,
              child: Container(
                width: 2,
                height: peakHeight.clamp(1.0, double.infinity),
                decoration: BoxDecoration(
                  color: peakColor,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getWaveformColor(RecordingState state) {
    switch (state) {
      case RecordingState.idle:
        return Colors.white.withValues(alpha: 0.3);
      case RecordingState.recording:
        return Colors.green.withValues(alpha: 0.9);
      case RecordingState.processing:
        return Colors.orange.withValues(alpha: 0.9);
      case RecordingState.error:
        return Colors.red.withValues(alpha: 0.9);
    }
  }

  Color _getPeakColor(RecordingState state) {
    switch (state) {
      case RecordingState.idle:
        return Colors.white.withValues(alpha: 0.2);
      case RecordingState.recording:
        return Colors.yellow.withValues(alpha: 0.8);
      case RecordingState.processing:
        return Colors.orange.withValues(alpha: 0.6);
      case RecordingState.error:
        return Colors.red.withValues(alpha: 0.6);
    }
  }

  Widget _buildRecordButton(BuildContext context, AppService appService) {
    final state = appService.state;
    final isRecording = state.recordingState == RecordingState.recording;
    
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Record/Stop button
          GestureDetector(
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
                color: isRecording 
                    ? Colors.red.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isRecording 
                      ? Colors.red.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Icon(
                isRecording ? Icons.stop : Icons.mic,
                color: isRecording 
                    ? Colors.red.withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.7),
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Settings menu
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: Colors.white.withValues(alpha: 0.7),
              size: 16,
            ),
            color: Colors.black.withValues(alpha: 0.8),
            onSelected: (value) => _handleMenuAction(context, value, appService),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(
                      Icons.settings,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    const Text('Settings', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'quit',
                child: Row(
                  children: [
                    Icon(
                      Icons.exit_to_app,
                      color: Colors.red.withValues(alpha: 0.7),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    const Text('Quit', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
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
