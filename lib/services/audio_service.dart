import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import '../utils/logger.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<Uint8List> _audioController = StreamController<Uint8List>.broadcast();
  
  bool _isRecording = false;
  StreamSubscription? _recordingSubscription;
  
  Stream<Uint8List> get audioStream => _audioController.stream;
  bool get isRecording => _isRecording;
  
  Future<bool> requestPermissions() async {
    AppLogger.audio('Requesting microphone permissions via record package...');
    try {
      // The record package will handle permissions automatically when we start recording
      final hasPermission = await _recorder.hasPermission();
      AppLogger.info('Record package permission status: $hasPermission');
      
      if (hasPermission) {
        AppLogger.success('Microphone permission granted');
      } else {
        AppLogger.warning('Microphone permission not granted - will be requested on first recording attempt');
      }
      return hasPermission;
    } catch (e) {
      AppLogger.error('Error checking microphone permission via record package', e);
      return false;
    }
  }
  
  Future<bool> hasPermissions() async {
    AppLogger.debug('Checking microphone permissions via record package...');
    try {
      final hasPermission = await _recorder.hasPermission();
      AppLogger.info('Record package permission check result: $hasPermission');
      return hasPermission;
    } catch (e) {
      AppLogger.error('Error checking microphone permission via record package', e);
      // Return true to allow the attempt - the record package will handle the permission request
      AppLogger.info('Assuming permissions are OK - record package will handle permission request');
      return true;
    }
  }
  
  Future<List<String>> getAvailableInputDevices() async {
    try {
      // This would need platform-specific implementation
      // For now, return basic options
      return ['Built-in Microphone', 'BlackHole 2ch'];
    } catch (e) {
      debugPrint('Error getting input devices: $e');
      return ['Default'];
    }
  }
  
  Future<void> startRecording(String deviceId) async {
    AppLogger.audio('AudioService.startRecording() called with device: $deviceId');
    
    if (_isRecording) {
      AppLogger.warning('Already recording - ignoring start request');
      return;
    }
    
    try {
      AppLogger.debug('Checking permissions before starting recording...');
      if (!await hasPermissions()) {
        AppLogger.warning('No microphone permission - requesting...');
        final granted = await requestPermissions();
        if (!granted) {
          throw Exception('Microphone permission not granted');
        }
      }
      
      AppLogger.debug('Setting up recording configuration...');
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      );
      
      AppLogger.debug('Starting audio recorder stream...');
      final stream = await _recorder.startStream(config);
      
      AppLogger.debug('Setting up stream listener...');
      _recordingSubscription = stream.listen(
        (data) {
          if (!_audioController.isClosed) {
            // More detailed logging to debug audio issues
            AppLogger.debug('Received audio data: ${data.length} bytes');

            // Check if audio is silent
            bool isSilent = true;
            for (int i = 0; i < data.length && i < 100; i++) {
              if (data[i] != 0 && data[i] != 128) {  // Check for non-zero/non-center values
                isSilent = false;
                break;
              }
            }

            if (isSilent && data.length > 100) {
              AppLogger.warning('Audio chunk appears to be silent!');
            }

            _audioController.add(Uint8List.fromList(data));
          }
        },
        onError: (error) {
          AppLogger.error('Recording stream error', error);
          _audioController.addError(error);
        },
      );
      
      _isRecording = true;
      AppLogger.success('Audio recording started successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to start recording', e);
      AppLogger.debug('Stack trace: $stackTrace');
      throw Exception('Failed to start recording: $e');
    }
  }
  
  Future<void> stopRecording() async {
    AppLogger.audio('AudioService.stopRecording() called');
    
    if (!_isRecording) {
      AppLogger.warning('Not recording - ignoring stop request');
      return;
    }
    
    try {
      AppLogger.debug('Cancelling recording subscription...');
      await _recordingSubscription?.cancel();
      
      AppLogger.debug('Stopping audio recorder...');
      await _recorder.stop();
      
      _isRecording = false;
      AppLogger.success('Audio recording stopped successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Error stopping recording', e);
      AppLogger.debug('Stack trace: $stackTrace');
      throw Exception('Failed to stop recording: $e');
    }
  }
  
  void dispose() {
    _recordingSubscription?.cancel();
    _recorder.dispose();
    _audioController.close();
  }
}