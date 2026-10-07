import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

class AudioCueService {
  static AudioCueService? _instance;
  static AudioCueService get instance => _instance ??= AudioCueService._();
  AudioCueService._();

  late AudioPlayer _audioPlayer;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _audioPlayer = AudioPlayer();
      _isInitialized = true;
      debugPrint('AudioCueService: Initialized successfully');
    } catch (e) {
      debugPrint('AudioCueService: Failed to initialize: $e');
    }
  }

  Future<void> playRecordingStartCue() async {
    if (!_isInitialized) {
      debugPrint('AudioCueService: Not initialized, skipping cue');
      return;
    }

    try {
      debugPrint('AudioCueService: Playing recording start cue');
      await _audioPlayer.play(AssetSource('audio_assets/start.wav'));
      debugPrint('AudioCueService: Recording start cue played successfully');
    } catch (e) {
      debugPrint('AudioCueService: Failed to play recording start cue: $e');
    }
  }

  Future<void> dispose() async {
    if (_isInitialized) {
      try {
        await _audioPlayer.dispose();
        _isInitialized = false;
        debugPrint('AudioCueService: Disposed successfully');
      } catch (e) {
        debugPrint('AudioCueService: Error during disposal: $e');
      }
    }
  }
}