import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

import '../models/app_state.dart';
import '../models/settings.dart';
import '../models/websocket_messages.dart';
import '../utils/logger.dart';
import 'audio_service.dart';
import 'settings_service.dart';
import 'backend_service.dart';
import 'hotkey_service.dart';
import 'paste_service.dart';
import 'audio_cue_service.dart';
import 'settings_window_service.dart';

class AppService extends ChangeNotifier {
  final AudioService _audioService;
  final SettingsService _settingsService;
  final BackendService _backendService;
  final HotkeyService _hotkeyService;
  final PasteService _pasteService;
  final AudioCueService _audioCueService;
  final SettingsWindowService _settingsWindowService;

  final _uuid = const Uuid();

  AppState _state = const AppState();
  Settings _settings = const Settings();

  String? _currentSessionId;
  Timer? _recordingTimer;
  StreamSubscription? _audioStreamSubscription;
  WebSocketChannel? _webSocketChannel;

  AppState get state => _state;
  Settings get settings => _settings;
  SettingsWindowService get settingsWindowService => _settingsWindowService;

  AppService({
    required AudioService audioService,
    required SettingsService settingsService,
    required BackendService backendService,
    required HotkeyService hotkeyService,
    required PasteService pasteService,
    required AudioCueService audioCueService,
    required SettingsWindowService settingsWindowService,
  }) : _audioService = audioService,
       _settingsService = settingsService,
       _backendService = backendService,
       _hotkeyService = hotkeyService,
       _pasteService = pasteService,
       _audioCueService = audioCueService,
       _settingsWindowService = settingsWindowService;

  Future<void> initialize() async {
    AppLogger.info('Starting AppService initialization...');

    try {
      // Load settings
      AppLogger.debug('Loading settings...');
      _settings = await _settingsService.loadSettings();
      AppLogger.success('Settings loaded successfully');

      // Check audio permissions first
      AppLogger.debug('Checking audio permissions...');
      final hasPermissions = await _audioService.hasPermissions();
      AppLogger.info('Audio permissions status: $hasPermissions');

      if (!hasPermissions) {
        AppLogger.warning('Audio permissions not granted, requesting...');
        final granted = await _audioService.requestPermissions();
        AppLogger.info('Audio permission request result: $granted');

        if (!granted) {
          AppLogger.error(
            'Audio permissions denied - app functionality will be limited',
          );
          _updateState(
            _state.copyWith(
              recordingState: RecordingState.error,
              errorMessage: 'Microphone permission required for recording',
            ),
          );
          return;
        }
      }

      // Initialize hotkey service first
      AppLogger.debug('Initializing hotkey service...');
      await _hotkeyService.initialize();
      AppLogger.success('Hotkey service initialized');

      // Initialize hotkeys
      AppLogger.debug('Setting up hotkeys...');
      await _setupHotkeys();

      // Initialize backend
      AppLogger.debug('Initializing backend...');
      await _backendService.initialize();
      AppLogger.success('Backend initialized');

      AppLogger.debug('Connecting to backend WebSocket...');
      await _connectToBackend();
      AppLogger.success('Connected to backend');

      _updateState(_state.copyWith(recordingState: RecordingState.idle));

      AppLogger.success('AppService initialization completed successfully!');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize AppService', e);
      AppLogger.debug('Stack trace: $stackTrace');
      _updateState(
        _state.copyWith(
          recordingState: RecordingState.error,
          errorMessage: 'Initialization failed: $e',
        ),
      );
    }
  }

  Future<void> _connectToBackend() async {
    try {
      // Close existing connection if any
      await _webSocketChannel?.sink.close();
      _webSocketChannel = null;

      final port = _backendService.getPort();
      if (port == null) {
        throw Exception('Backend port not available');
      }

      final uri = Uri.parse('ws://127.0.0.1:$port/ws');
      AppLogger.websocket('Connecting to WebSocket at: $uri');

      _webSocketChannel = WebSocketChannel.connect(uri);

      // Wait a bit for connection to establish
      await Future.delayed(const Duration(milliseconds: 100));

      // Send hello message
      final helloCommand = HelloCommand(appVersion: '0.2.0', locale: 'en_US');

      final envelope = MessageEnvelope(
        type: 'hello',
        id: _uuid.v4(),
        data: helloCommand.toJson(),
      );

      final message = jsonEncode(envelope.toJson());
      AppLogger.websocket('Sending hello message: $message');
      _webSocketChannel!.sink.add(message);

      // Listen for messages
      _webSocketChannel!.stream.listen(
        _handleWebSocketMessage,
        onError: _handleWebSocketError,
        onDone: _handleWebSocketDisconnection,
      );

      AppLogger.success('Connected to backend WebSocket at $uri');
    } catch (e) {
      AppLogger.error('Failed to connect to backend WebSocket', e);
      throw Exception('Backend connection failed: $e');
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      if (message == null) {
        AppLogger.warning('Received null WebSocket message');
        return;
      }

      final messageStr = message.toString();
      AppLogger.websocket('Received WebSocket message: $messageStr');

      final data = jsonDecode(messageStr);
      final envelope = MessageEnvelope.fromJson(data);

      switch (envelope.type) {
        case 'hello_ack':
          final event = HelloAckEvent.fromJson(envelope.data);
          AppLogger.websocket(
            'Connected to backend: ${event.serverVersion}, device: ${event.device}',
          );
          break;

        case 'partial':
          final event = PartialEvent.fromJson(envelope.data);
          _updateState(_state.copyWith(partialText: event.text));
          break;

        case 'final':
          final event = FinalEvent.fromJson(envelope.data);
          _handleFinalTranscription(event.text);
          break;

        case 'error':
          final event = ErrorEvent.fromJson(envelope.data);
          _handleTranscriptionError(event.message);
          break;

        case 'stats':
          final event = StatsEvent.fromJson(envelope.data);
          debugPrint(
            'Transcription stats: RT factor: ${event.rtFactor}, tokens/s: ${event.tokensPerS}',
          );
          break;
      }
    } catch (e) {
      debugPrint('Error handling WebSocket message: $e');
    }
  }

  void _handleWebSocketError(error) {
    debugPrint('WebSocket error: $error');
    _updateState(
      _state.copyWith(
        recordingState: RecordingState.error,
        errorMessage: 'Connection error: $error',
      ),
    );
  }

  void _handleWebSocketDisconnection() {
    AppLogger.websocket('WebSocket disconnected - attempting reconnection...');
    _updateState(
      _state.copyWith(
        recordingState: RecordingState.error,
        errorMessage: 'WebSocket disconnected',
      ),
    );

    // Attempt to reconnect after a delay
    Timer(const Duration(seconds: 2), () async {
      try {
        AppLogger.websocket('Attempting to reconnect to backend...');
        await _connectToBackend();
        AppLogger.success('WebSocket reconnected successfully');

        // Reset error state if we were in an error state due to disconnection
        if (_state.recordingState == RecordingState.error &&
            _state.errorMessage == 'WebSocket disconnected') {
          _updateState(
            _state.copyWith(
              recordingState: RecordingState.idle,
              errorMessage: null,
            ),
          );
        }
      } catch (e) {
        AppLogger.error('Failed to reconnect WebSocket', e);
        _updateState(
          _state.copyWith(
            recordingState: RecordingState.error,
            errorMessage: 'Reconnection failed: $e',
          ),
        );

        // Try again in 5 seconds
        Timer(const Duration(seconds: 5), () async {
          try {
            await _connectToBackend();
          } catch (e) {
            AppLogger.error('Second reconnection attempt failed', e);
          }
        });
      }
    });
  }

  Future<void> _setupHotkeys() async {
    AppLogger.hotkey('Setting up hotkeys...');

    // Register hold-to-talk hotkey
    if (_settings.holdToTalkHotkey.isNotEmpty) {
      AppLogger.hotkey(
        'Registering hold-to-talk hotkey: ${_settings.holdToTalkHotkey}',
      );
      try {
        await _hotkeyService.registerHotkey(
          _settings.holdToTalkHotkey,
          onPressed: () {
            AppLogger.hotkey('Hold-to-talk hotkey PRESSED');
            startRecording();
          },
          onReleased: () {
            AppLogger.hotkey('Hold-to-talk hotkey RELEASED');
            stopRecording();
          },
        );
        AppLogger.success('Hold-to-talk hotkey registered successfully');
      } catch (e) {
        AppLogger.error('Failed to register hold-to-talk hotkey', e);
      }
    } else {
      AppLogger.warning('No hold-to-talk hotkey configured');
    }

    // Register toggle recording hotkey
    if (_settings.toggleRecordHotkey.isNotEmpty) {
      AppLogger.hotkey(
        'Registering toggle recording hotkey: ${_settings.toggleRecordHotkey}',
      );
      try {
        await _hotkeyService.registerHotkey(
          _settings.toggleRecordHotkey,
          onPressed: () {
            AppLogger.hotkey('Toggle recording hotkey PRESSED');
            toggleRecording();
          },
        );
        AppLogger.success('Toggle recording hotkey registered successfully');
      } catch (e) {
        AppLogger.error('Failed to register toggle recording hotkey', e);
      }
    } else {
      AppLogger.warning('No toggle recording hotkey configured');
    }

    AppLogger.success('Hotkey setup completed');
  }

  Future<void> startRecording() async {
    AppLogger.audio('startRecording() called');
    AppLogger.debug('Current recording state: ${_state.recordingState}');

    if (_state.recordingState != RecordingState.idle) {
      AppLogger.warning(
        'Cannot start recording - not in idle state (current: ${_state.recordingState})',
      );
      return;
    }

    try {
      AppLogger.audio('Starting new recording session...');
      
      // Bring window to front during recording if enabled
      if (_settings.bringToFrontDuringRecording) {
        await _bringWindowToFront();
      }
      
      // Play audio cue to indicate recording start
      await _audioCueService.playRecordingStartCue();
      
      _currentSessionId = _uuid.v4();
      AppLogger.debug('Generated session ID: $_currentSessionId');

      // Send start session command to backend
      final languageCode = _getLanguageCode(_settings.autoDetectLanguage, _settings.manualLanguage);
      AppLogger.info('🌐 Language setting: autoDetect=${_settings.autoDetectLanguage}, manual=${_settings.manualLanguage.name}, sending: $languageCode');

      final startCommand = StartSessionCommand(
        sessionId: _currentSessionId!,
        model: _settings.model.name,
        device: _settings.device.name,
        computeType: _settings.computeType.name,
        enablePartial: true,
        language: languageCode,
        post: PostProcessingOptions(
          smartCaps: _settings.smartCapitalization,
          punctuation: _settings.punctuation,
          disfluencyCleanup: _settings.disfluencyCleanup,
        ),
      );

      final envelope = MessageEnvelope(
        type: 'start_session',
        id: _uuid.v4(),
        data: startCommand.toJson(),
      );

      _webSocketChannel?.sink.add(jsonEncode(envelope.toJson()));
      AppLogger.websocket('Sent start_session command to backend');

      // Start audio recording
      AppLogger.audio(
        'Starting audio recording with device: ${_settings.inputDevice}',
      );
      await _audioService.startRecording(_settings.inputDevice);
      AppLogger.success('Audio recording started successfully');

      // Listen to audio stream
      AppLogger.debug('Setting up audio stream listener...');
      _audioStreamSubscription = _audioService.audioStream.listen(
        _handleAudioChunk,
        onError: (error) {
          AppLogger.error('Audio stream error', error);
        },
      );

      // Start recording timer
      AppLogger.debug('Starting recording timer...');
      _startRecordingTimer();

      _updateState(
        _state.copyWith(
          recordingState: RecordingState.recording,
          partialText: null,
          finalText: null,
          recordingDuration: Duration.zero,
        ),
      );

      AppLogger.success('Recording started successfully!');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to start recording', e);
      AppLogger.debug('Stack trace: $stackTrace');
      _updateState(
        _state.copyWith(
          recordingState: RecordingState.error,
          errorMessage: 'Recording failed: $e',
        ),
      );
    }
  }

  void _handleAudioChunk(Uint8List audioData) {
    AppLogger.debug('Received audio chunk: ${audioData.length} bytes');

    // Send audio chunk to backend via WebSocket
    if (_webSocketChannel != null) {
      _webSocketChannel!.sink.add(audioData);
      AppLogger.debug('Sent ${audioData.length} bytes to backend');
    }

    // Update audio level for UI
    final level = _calculateAudioLevel(audioData);
    AppLogger.debug('Audio level calculated: $level');
    _updateState(_state.copyWith(audioLevel: level));
  }

  double _calculateAudioLevel(Uint8List audioData) {
    if (audioData.isEmpty) return 0.0;

    // Calculate RMS (Root Mean Square) for better audio level representation
    double sum = 0.0;
    int sampleCount = 0;

    for (int i = 0; i < audioData.length; i += 2) {
      if (i + 1 < audioData.length) {
        // Convert 16-bit PCM to signed integer
        final sample = (audioData[i + 1] << 8) | audioData[i];
        final signedSample = sample > 32767 ? sample - 65536 : sample;
        final normalizedSample = signedSample / 32768.0;

        // Use absolute value for better responsiveness
        sum += normalizedSample * normalizedSample;
        sampleCount++;
      }
    }

    if (sampleCount == 0) return 0.0;

    // Calculate RMS
    final rms = math.sqrt(sum / sampleCount);

    // Apply logarithmic scaling for better visual response
    // This makes quiet sounds more visible and loud sounds less overwhelming
    double scaledLevel = 0.0;
    if (rms > 0.0) {
      // Convert to dB scale and normalize
      double db = 20 * math.log(rms) / math.ln10;
      // Normalize to 0-100 range (typical speech is around -30 to -10 dB)
      scaledLevel = ((db + 60) / 50).clamp(0.0, 1.0) * 100;
    }

    return scaledLevel;
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      _updateState(
        _state.copyWith(
          recordingDuration: Duration(milliseconds: timer.tick * 100),
        ),
      );
    });
  }

  Future<void> stopRecording() async {
    AppLogger.audio('stopRecording() called');
    AppLogger.debug('Current recording state: ${_state.recordingState}');

    if (_state.recordingState != RecordingState.recording) {
      AppLogger.warning(
        'Cannot stop recording - not in recording state (current: ${_state.recordingState})',
      );
      return;
    }

    try {
      AppLogger.audio('Stopping recording and processing...');
      _updateState(_state.copyWith(recordingState: RecordingState.processing));

      // Stop audio recording
      AppLogger.debug('Stopping audio service...');
      await _audioService.stopRecording();
      AppLogger.success('Audio recording stopped');

      AppLogger.debug('Cancelling audio stream subscription...');
      _audioStreamSubscription?.cancel();

      AppLogger.debug('Cancelling recording timer...');
      _recordingTimer?.cancel();

      // End session with backend
      if (_currentSessionId != null) {
        final endCommand = EndSessionCommand(sessionId: _currentSessionId!);
        final envelope = MessageEnvelope(
          type: 'end_session',
          id: _uuid.v4(),
          data: endCommand.toJson(),
        );

        _webSocketChannel?.sink.add(jsonEncode(envelope.toJson()));
        AppLogger.websocket('Sent end_session command to backend');
      }

      // The backend will send us a 'final' event with the transcription
      AppLogger.info('Waiting for transcription from backend...');

      AppLogger.success('Recording stopped and processed successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to stop recording', e);
      AppLogger.debug('Stack trace: $stackTrace');
      
      // Send window to back even if there was an error (only if we brought it to front)
      if (_settings.bringToFrontDuringRecording) {
        await _sendWindowToBack();
      }
      
      _updateState(
        _state.copyWith(
          recordingState: RecordingState.error,
          errorMessage: 'Stop recording failed: $e',
        ),
      );
    }
  }

  Future<void> toggleRecording() async {
    AppLogger.audio('toggleRecording() called');
    AppLogger.debug('Current state: ${_state.recordingState}');

    if (_state.recordingState == RecordingState.idle) {
      AppLogger.info('Toggling from idle to recording');
      await startRecording();
    } else if (_state.recordingState == RecordingState.recording) {
      AppLogger.info('Toggling from recording to stop');
      await stopRecording();
    } else {
      AppLogger.warning(
        'Cannot toggle recording in current state: ${_state.recordingState}',
      );
    }
  }

  void _handleFinalTranscription(String text) async {
    _updateState(
      _state.copyWith(
        recordingState: RecordingState.idle,
        finalText: text,
        partialText: null,
      ),
    );

    AppLogger.info('✅ Final transcription: $text');

    // Send window to back before pasting if we brought it to front
    if (_settings.bringToFrontDuringRecording) {
      await _sendWindowToBack();
    }

    // Perform paste action
    try {
      await _pasteService.performPasteAction(text, _settings.defaultAction);
    } catch (e) {
      debugPrint('Failed to perform paste action: $e');
    }

    _currentSessionId = null;
  }

  void _handleTranscriptionError(String error) {
    _updateState(
      _state.copyWith(
        recordingState: RecordingState.error,
        errorMessage: error,
      ),
    );

    _currentSessionId = null;
    _recordingTimer?.cancel();
    _audioStreamSubscription?.cancel();
  }

  void toggleOverlayVisibility() {
    _updateState(_state.copyWith(isOverlayVisible: !_state.isOverlayVisible));
  }

  void togglePartialTextVisibility() {
    _updateState(
      _state.copyWith(isPartialTextVisible: !_state.isPartialTextVisible),
    );
  }

  Future<void> _bringWindowToFront() async {
    try {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.focus();
      AppLogger.debug('Window brought to front for recording');
    } catch (e) {
      AppLogger.error('Failed to bring window to front', e);
    }
  }

  Future<void> _sendWindowToBack() async {
    try {
      await windowManager.setAlwaysOnTop(_settings.alwaysOnTop);
      AppLogger.debug('Window sent to back after recording');
    } catch (e) {
      AppLogger.error('Failed to send window to back', e);
    }
  }

  void updateSettings(Settings newSettings) async {
    final oldSettings = _settings;
    _settings = newSettings;
    await _settingsService.saveSettings(newSettings);

    // Re-setup hotkeys if they changed
    await _hotkeyService.unregisterAllHotkeys();
    await _setupHotkeys();

    // Update window appearance if appearance settings changed
    if (oldSettings.glassOpacity != newSettings.glassOpacity ||
        oldSettings.glassEffect != newSettings.glassEffect ||
        oldSettings.alwaysOnTop != newSettings.alwaysOnTop ||
        oldSettings.overlayWidth != newSettings.overlayWidth ||
        oldSettings.overlayHeight != newSettings.overlayHeight) {
      await _updateWindowAppearance(newSettings);
    }

    notifyListeners();
  }

  Future<void> _updateWindowAppearance(Settings settings) async {
    try {
      // Update window size
      await windowManager.setSize(
        Size(settings.overlayWidth, settings.overlayHeight),
      );

      // Update always on top
      await windowManager.setAlwaysOnTop(settings.alwaysOnTop);

      // Update glass effect
      await Window.setEffect(
        effect: _getWindowEffect(settings.glassEffect),
        color: Colors.black.withValues(alpha: settings.glassOpacity),
      );

      AppLogger.debug('Window appearance updated');
    } catch (e) {
      AppLogger.error('Failed to update window appearance', e);
    }
  }

  WindowEffect _getWindowEffect(String effectName) {
    switch (effectName) {
      case 'hudWindow':
        return WindowEffect.acrylic;
      case 'sidebar':
        return WindowEffect.mica;
      case 'menu':
        return WindowEffect.acrylic;
      case 'popover':
        return WindowEffect.acrylic;
      case 'titlebar':
        return WindowEffect.titlebar;
      default:
        return WindowEffect.acrylic;
    }
  }

  void _updateState(AppState newState) {
    _state = newState;
    notifyListeners();
  }

  /// Convert Flutter language settings to whisper.cpp language code
  String _getLanguageCode(bool autoDetect, Language manualLanguage) {
    if (autoDetect) {
      return 'auto';
    }

    // Convert Language enum to whisper.cpp language codes
    switch (manualLanguage) {
      case Language.auto:
        return 'auto';
      case Language.english:
        return 'en';
      case Language.japanese:
        return 'ja';
    }
  }

  Future<void> cleanup() async {
    AppLogger.info('Cleaning up AppService...');
    _recordingTimer?.cancel();
    _audioStreamSubscription?.cancel();

    // Properly close WebSocket connection
    if (_webSocketChannel != null) {
      await _webSocketChannel!.sink.close();
      _webSocketChannel = null;
    }

    // Stop backend process
    await _backendService.stop();
    AppLogger.success('Backend process stopped');
  }

  Future<void> openSettingsWindow() async {
    AppLogger.info('Opening settings window');
    await _settingsWindowService.openSettingsWindow();
  }

  Future<void> closeSettingsWindow() async {
    AppLogger.info('Closing settings window');
    await _settingsWindowService.closeSettingsWindow();
  }

  @override
  void dispose() {
    AppLogger.info('Disposing AppService...');
    _recordingTimer?.cancel();
    _audioStreamSubscription?.cancel();

    // Close WebSocket connection synchronously
    _webSocketChannel?.sink.close();
    _webSocketChannel = null;

    // Dispose services
    _audioService.dispose();
    _hotkeyService.dispose();
    _audioCueService.dispose();
    _settingsWindowService.dispose();

    super.dispose();
  }
}
