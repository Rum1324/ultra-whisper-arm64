import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

import '../models/app_state.dart';
import '../models/settings.dart';
import '../models/websocket_messages.dart';
import 'meeting_service.dart';
import 'meeting_detector.dart';
import 'transcript_archive.dart';
import '../utils/logger.dart';
import '../utils/diagnostics.dart';
import 'audio_service.dart';
import 'mic_activity_service.dart';
import 'settings_service.dart';
import 'backend_service.dart';
import 'hotkey_service.dart';
import 'paste_service.dart';
import 'audio_cue_service.dart';
import 'settings_window_service.dart';
import 'volume_control_service.dart';
import 'status_bar_service.dart';

class AppService extends ChangeNotifier {
  static const _lifecycleChannel = MethodChannel('com.glassywhisper.app_lifecycle');

  final AudioService _audioService;
  final SettingsService _settingsService;
  final BackendService _backendService;
  final HotkeyService _hotkeyService;
  final PasteService _pasteService;
  final AudioCueService _audioCueService;
  final SettingsWindowService _settingsWindowService;
  final VolumeControlService _volumeControlService;
  final StatusBarService _statusBarService;

  // Owned rather than injected: it has no dependencies of its own, and keeping
  // it out of the constructor avoids threading meeting capture through every
  // existing call site while the feature is still being built.
  final MicActivityService _micActivityService = MicActivityService();

  final _uuid = const Uuid();

  AppState _state = const AppState();
  Settings _settings = const Settings();

  String? _currentSessionId;
  Timer? _recordingTimer;

  /// UID of the output device we last inspected, so the menu bar can be
  /// refreshed without another CoreAudio round trip.
  String? _lastOutputDeviceUid;
  StreamSubscription? _audioStreamSubscription;
  WebSocketChannel? _webSocketChannel;
  bool _pressEnterOnPaste = false;

  /// Client half of the meeting protocol. Constructed lazily so it always
  /// sends over whichever channel is currently connected — the socket is
  /// replaced on reconnect, and capturing it once would send into a dead sink.
  late final MeetingService _meetingService = MeetingService(
    sendJson: (envelope) => _webSocketChannel?.sink.add(jsonEncode(envelope)),
    sendBinary: (frame) => _webSocketChannel?.sink.add(frame),
  );

  MeetingService get meetingService => _meetingService;

  /// Notices that a call has probably started and names the process whose
  /// output belongs in the "them" track. Lazy for the same reason as
  /// [_meetingService]: it needs the mic-activity bridge to exist first.
  late final MeetingDetector _meetingDetector = MeetingDetector(
    listProcesses: _micActivityService.listAudioProcesses,
  );

  MeetingCandidate? _pendingMeetingPrompt;
  MeetingCandidate? _meetingTarget;
  StreamSubscription? _meetingAudioSubscription;
  Timer? _meetingTimer;
  Duration _meetingDuration = Duration.zero;
  DateTime? _meetingStartedAt;
  List<String> _lastSavedMeetingFiles = const [];
  bool _meetingSystemAudioSilent = false;
  bool _autoSummarizePending = false;
  bool _savedNoteForCurrentMeeting = false;
  bool _meetingWindowExpanded = false;

  /// The detected call awaiting a yes/no from the user, if any.
  MeetingCandidate? get pendingMeetingPrompt => _pendingMeetingPrompt;

  /// The process being tapped for "them", null for a mic-only meeting.
  MeetingCandidate? get meetingTarget => _meetingTarget;

  /// Whether the "them" track has produced nothing but digital silence.
  ///
  /// Surfaced rather than fatal: macOS answers an unauthorized tap with zeroes
  /// instead of an error, and a one-sided meeting is still worth having.
  bool get meetingSystemAudioSilent => _meetingSystemAudioSilent;

  Duration get meetingDuration => _meetingDuration;

  bool get isMeetingActive => _meetingService.phase != MeetingPhase.idle;

  bool get isMeetingRecording => _meetingService.isRecording;

  /// Files written for the meeting just finished, for the panel to show.
  List<String> get lastSavedMeetingFiles => _lastSavedMeetingFiles;

  /// Where meetings will be written, with the default already resolved.
  String get meetingSaveDirectory =>
      TranscriptArchive.resolveDirectory(_settings.meetingSaveDirectory);

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
    required VolumeControlService volumeControlService,
    required StatusBarService statusBarService,
  }) : _audioService = audioService,
       _settingsService = settingsService,
       _backendService = backendService,
       _hotkeyService = hotkeyService,
       _pasteService = pasteService,
       _audioCueService = audioCueService,
       _settingsWindowService = settingsWindowService,
       _volumeControlService = volumeControlService,
       _statusBarService = statusBarService;

  Future<void> initialize() async {
    AppLogger.info('Starting AppService initialization...');

    // Whether the opt-in tap self-test has been requested for this launch.
    //
    // Read up front because it has to survive the early returns below: the
    // diagnostic exists to be run under re-signed variants of the app that
    // deliberately have no permissions yet, and bailing out at the microphone
    // check would mean the tap is never measured at all. Costs a stat().
    final selfTestRequested = Diagnostics.tapSelfTest;

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
          // The tap needs System Audio Recording, not the microphone — they are
          // separate TCC services. Carry on when a self-test was asked for, so
          // a missing mic grant cannot mask the result being measured.
          if (!selfTestRequested) return;
        }
      }

      // Check accessibility permissions for paste functionality
      AppLogger.debug('Checking accessibility permissions...');
      try {
        final hasAccessibility = await _pasteService.hasAccessibilityPermission();
        if (!hasAccessibility) {
          AppLogger.warning('⚠️ Accessibility permission not granted');
          AppLogger.warning('Paste functionality will not work without accessibility permission');
          AppLogger.warning('Please grant access in System Settings > Privacy & Security > Accessibility');
          debugPrint('');
          debugPrint('========================================');
          debugPrint('⚠️  ACCESSIBILITY PERMISSION REQUIRED  ⚠️');
          debugPrint('========================================');
          debugPrint('Automatic paste will not work without accessibility permission.');
          debugPrint('Please grant access in:');
          debugPrint('System Settings > Privacy & Security > Accessibility > UltraWhisper');
          debugPrint('The app can still copy text to clipboard.');
          debugPrint('========================================');
          debugPrint('');

          // Note: We don't return here since the app can still function for clipboard-only mode
          // Just warn the user that paste won't work
        } else {
          AppLogger.success('✅ Accessibility permission granted');
          debugPrint('✅ Accessibility permission is granted - paste functionality will work');
        }
      } catch (e) {
        AppLogger.warning('Could not check accessibility permission: $e');
      }

      // Initialize hotkey service first
      AppLogger.debug('Initializing hotkey service...');
      await _hotkeyService.initialize();
      AppLogger.success('Hotkey service initialized');

      // Initialize hotkeys
      AppLogger.debug('Setting up hotkeys...');
      await _setupHotkeys();

      // Ask for System Audio Recording up front, before any meeting exists.
      //
      // A denied tap does not fail — macOS returns digital silence — so without
      // asking here the first symptom would be an empty "them" track found
      // after the call, when the audio is already gone. Never fatal: meeting
      // capture is an extra on top of dictation, which must work regardless.
      AppLogger.debug('Preflighting system audio permission...');
      final audioTapReady = await _micActivityService.preflightPermission();
      AppLogger.info('System audio tap available: $audioTapReady');
      _micActivityService.startListening();
      _wireMeetingCapture();

      // Opt-in diagnostic: ULTRAWHISPER_TAP_SELFTEST=1 captures a few seconds
      // from whatever is playing and reports whether real samples arrive. Only
      // an actual capture can distinguish a granted permission from a denied
      // one, since both produce a working tap.
      // Opt-in diagnostic, triggered by either an env var or a sentinel file.
      //
      // The sentinel exists because the app MUST be launched via `open` for this
      // to mean anything: TCC attributes a permission request to the
      // "responsible process", which for a shell-launched binary is the shell,
      // not the app — so a shell launch is denied no matter what the user
      // granted. And `open` discards stdout, hence writing the result to a file
      // rather than printing it.
      final sentinel = File(
        '${Platform.environment['HOME']}/.ultrawhisper_tap_selftest',
      );
      if (selfTestRequested) {
        // A pid written into the sentinel narrows the test to one process.
        final wanted = int.tryParse(
          sentinel.existsSync() ? sentinel.readAsStringSync().trim() : '',
        );
        // Step by step, most conclusive signal first.
        final authed = await _micActivityService.screenCaptureAuthorized();
        if (!authed) {
          await _micActivityService.requestScreenCaptureAccess();
        }
        final verdict = await _micActivityService.runSelfTest(onlyPid: wanted);
        final global = await _micActivityService.measureGlobalTap();
        final sck = await _micActivityService.measureScreenCaptureKit();
        final line = '[1] screenCaptureAuthorized=$authed\n'
            '[2] tapPreflightCreated=$audioTapReady\n'
            '[3] tap $verdict\n'
            '[4] $global\n'
            '[5] $sck';
        // ignore: avoid_print
        print('TAP-SELFTEST: $line');
        try {
          // Name the result after the .app, so several re-signed variants can
          // be launched in one sitting without overwriting each other. Bisecting
          // a permission problem means running the same build under different
          // identities, and a shared filename makes that one round trip each.
          final parts = Platform.resolvedExecutable.split('/');
          final index = parts.lastIndexWhere((p) => p.endsWith('.app'));
          final variant = index >= 0
              ? parts[index].substring(0, parts[index].length - 4)
              : 'unknown';
          File('${Platform.environment['HOME']}/.ultrawhisper_tap_selftest-$variant.result')
              .writeAsStringSync('${DateTime.now().toIso8601String()}  $line\n');
        } catch (_) {
          // A diagnostic that cannot write its result is still not worth
          // taking the app down for.
        }
      }

      // Initialize backend
      AppLogger.debug('Initializing backend...');
      await _backendService.initialize();
      AppLogger.success('Backend initialized');

      AppLogger.debug('Connecting to backend WebSocket...');
      await _connectToBackend();
      AppLogger.success('Connected to backend');

      // Apply initial Dock visibility setting
      AppLogger.debug('Applying Dock visibility setting...');
      await _applyDockVisibility(_settings.dockVisibilityMode);

      // Set up status bar event handlers
      AppLogger.debug('Setting up status bar event handlers...');
      _setupStatusBarHandlers();

      // Update status bar menu with current volume duck state
      AppLogger.debug('Updating status bar volume duck state...');
      await _statusBarService.setVolumeDuckState(_settings.duckVolumeDuringRecording);
      await _syncDeviceDuckMenuItem(await registerCurrentOutputDevice());

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

      // Meeting events first. The service claims only what belongs to a live
      // meeting and returns false otherwise, so dictation keeps its handlers.
      if (_meetingService.handleEvent(envelope.type, envelope.data)) {
        return;
      }

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

    // Register toggle recording hotkey (paste only, no Enter)
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

    // Register toggle recording + Enter hotkey (paste, then press Enter)
    if (_settings.toggleRecordEnterHotkey.isNotEmpty) {
      AppLogger.hotkey(
        'Registering toggle recording + Enter hotkey: ${_settings.toggleRecordEnterHotkey}',
      );
      try {
        await _hotkeyService.registerHotkey(
          _settings.toggleRecordEnterHotkey,
          onPressed: () {
            AppLogger.hotkey('Toggle recording + Enter hotkey PRESSED');
            toggleRecording(pressEnter: true);
          },
        );
        AppLogger.success('Toggle recording + Enter hotkey registered successfully');
      } catch (e) {
        AppLogger.error('Failed to register toggle recording + Enter hotkey', e);
      }
    } else {
      AppLogger.warning('No toggle recording + Enter hotkey configured');
    }

    AppLogger.success('Hotkey setup completed');
  }

  Future<void> startRecording() async {
    AppLogger.audio('startRecording() called');
    AppLogger.debug('Current recording state: ${_state.recordingState}');

    // Dictation and a meeting both want the microphone through the same
    // AudioService, and the second caller would silently get nothing. Refusing
    // is the honest outcome; the meeting is the session with something to lose.
    if (isMeetingRecording) {
      AppLogger.warning('Dictation is unavailable while a meeting is recording');
      return;
    }

    if (_state.recordingState != RecordingState.idle) {
      AppLogger.warning(
        'Cannot start recording - not in idle state (current: ${_state.recordingState})',
      );
      return;
    }

    try {
      AppLogger.audio('Starting new recording session...');

      // Duck volume if enabled
      if (_settings.duckVolumeDuringRecording) {
        final skipDuck = await _resolveSkipDuckForCurrentDevice();
        if (skipDuck) {
          AppLogger.debug('Skipping volume duck for the current output device');
        } else {
          AppLogger.debug(
            'Ducking system volume to ${(_settings.volumeDuckPercentage * 100).toStringAsFixed(0)}%',
          );
          await _volumeControlService.duckVolumeForRecording(
            percentage: _settings.volumeDuckPercentage,
            persistent: true,
          );
        }
      }

      // Bring window to front during recording if enabled
      if (_settings.bringToFrontDuringRecording) {
        await _bringWindowToFront();
      }

      // Play audio cue to indicate recording start
      await _audioCueService.playRecordingStartCue();

      _currentSessionId = _uuid.v4();
      AppLogger.debug('Generated session ID: $_currentSessionId');

      // Send start session command to backend — language is always auto-detected
      final startCommand = StartSessionCommand(
        sessionId: _currentSessionId!,
        enablePartial: true,
        language: 'auto',
        post: PostProcessingOptions(
          smartCaps: _settings.smartCapitalization,
          punctuation: _settings.punctuation,
          disfluencyCleanup: _settings.disfluencyCleanup,
          customTerms: _settings.customTerms.isNotEmpty ? _settings.customTerms : null,
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
      AppLogger.audio('Starting audio recording...');
      await _audioService.startRecording();
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

      // Update status bar to show recording state
      await _statusBarService.setRecordingState(true);

      AppLogger.success('Recording started successfully!');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to start recording', e);
      AppLogger.debug('Stack trace: $stackTrace');

      // Restore volume if we ducked it before the error occurred
      if (_settings.duckVolumeDuringRecording) {
        AppLogger.debug('Restoring system volume after start error');
        await _volumeControlService.restoreVolumeAfterRecording();
      }

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

      // Update status bar to show idle state
      await _statusBarService.setRecordingState(false);

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

      // Restore volume even if there was an error
      if (_settings.duckVolumeDuringRecording) {
        AppLogger.debug('Restoring system volume after error');
        await _volumeControlService.restoreVolumeAfterRecording();
      }

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

  Future<void> toggleRecording({bool pressEnter = false}) async {
    AppLogger.audio('toggleRecording() called with pressEnter: $pressEnter');
    AppLogger.debug('Current state: ${_state.recordingState}');

    if (_state.recordingState == RecordingState.idle) {
      AppLogger.info('Toggling from idle to recording');
      _pressEnterOnPaste = pressEnter;
      await startRecording();
    } else if (_state.recordingState == RecordingState.recording) {
      AppLogger.info('Toggling from recording to stop');
      // The hotkey that stops the recording decides whether Enter follows the
      // paste, so starting with ⌥⇧E and stopping with ⌥⇧R pastes without Enter.
      _pressEnterOnPaste = pressEnter;
      await stopRecording();
    } else {
      AppLogger.warning(
        'Cannot toggle recording in current state: ${_state.recordingState}',
      );
    }
  }

  void _handleFinalTranscription(String text) async {
    debugPrint('');
    debugPrint('════════════════════════════════════════');
    debugPrint('🎤 FINAL TRANSCRIPTION RECEIVED');
    debugPrint('Text: "$text"');
    debugPrint('Length: ${text.length} characters');
    debugPrint('Press Enter after paste: $_pressEnterOnPaste');
    debugPrint('════════════════════════════════════════');

    _updateState(
      _state.copyWith(
        recordingState: RecordingState.idle,
        finalText: text,
        partialText: null,
      ),
    );

    AppLogger.info('✅ Final transcription: $text');

    // Restore system volume if it was ducked
    if (_settings.duckVolumeDuringRecording) {
      AppLogger.debug('Restoring system volume');
      await _volumeControlService.restoreVolumeAfterRecording();
    }

    // Send window to back before pasting if we brought it to front
    if (_settings.bringToFrontDuringRecording) {
      await _sendWindowToBack();
    }

    // Perform paste action
    try {
      debugPrint('Attempting to perform paste action...');
      await _pasteService.performPasteAction(
        text,
        pressEnter: _pressEnterOnPaste,
        keepOnClipboard: _settings.keepTranscriptOnClipboard,
      );
      debugPrint('Paste action completed successfully');
    } catch (e) {
      debugPrint('❌ Failed to perform paste action: $e');
      AppLogger.error('Paste action failed: $e');
    }

    _currentSessionId = null;
    _pressEnterOnPaste = false;
  }

  void _handleTranscriptionError(String error) async {
    _updateState(
      _state.copyWith(
        recordingState: RecordingState.error,
        errorMessage: error,
      ),
    );

    // Restore volume if it was ducked
    if (_settings.duckVolumeDuringRecording) {
      AppLogger.debug('Restoring system volume after transcription error');
      await _volumeControlService.restoreVolumeAfterRecording();
    }

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

  // MARK: - Per-device volume ducking
  //
  // Ducking used to be decided by transport: skip on Bluetooth, duck otherwise.
  // That conflates headphones with a Bluetooth speaker, which want opposite
  // answers. A device is remembered the first time it is used — seeded from the
  // old transport rule — and from then on its own row decides.

  /// Ensure the current output device has a remembered row, and return it.
  ///
  /// Returns null when there is no device or it has no UID: such a device
  /// cannot be keyed, so callers fall back to the transport heuristic rather
  /// than accumulating unkeyed rows.
  Future<AudioDevicePref?> registerCurrentOutputDevice() async {
    final device = await _volumeControlService.getOutputDeviceInfo();
    _lastOutputDeviceUid = device?.uid.isNotEmpty == true ? device!.uid : null;
    if (device == null || device.uid.isEmpty) {
      if (device != null) {
        AppLogger.debug(
          'Output device "${device.displayName}" has no UID; not remembering it',
        );
      }
      return null;
    }

    final prefs = List<AudioDevicePref>.from(_settings.audioDevicePrefs);
    final index = prefs.indexWhere((pref) => pref.uid == device.uid);

    if (index >= 0) {
      final existing = prefs[index];
      // Refresh the label so a renamed device does not read stale in Settings.
      if (existing.name != device.name || existing.isBluetooth != device.isBluetooth) {
        prefs[index] = existing.copyWith(
          name: device.name,
          isBluetooth: device.isBluetooth,
        );
        await _persistSettingsQuietly(
          _settings.copyWith(audioDevicePrefs: prefs),
        );
      }
      return prefs[index];
    }

    final added = AudioDevicePref(
      uid: device.uid,
      name: device.name,
      isBluetooth: device.isBluetooth,
      // Seeded from the rule this table replaces, so nothing changes behaviour
      // the first time a device is seen.
      skipDuck: device.isBluetooth && _settings.skipDuckWhenBluetooth,
    );
    prefs.add(added);
    await _persistSettingsQuietly(_settings.copyWith(audioDevicePrefs: prefs));
    AppLogger.info(
      'Remembered output device "${added.displayName}" (skipDuck: ${added.skipDuck})',
    );
    return added;
  }

  /// Whether ducking should be skipped for whatever is playing audio right now.
  Future<bool> _resolveSkipDuckForCurrentDevice() async {
    final pref = await registerCurrentOutputDevice();
    if (pref != null) {
      await _syncDeviceDuckMenuItem(pref);
      return pref.skipDuck;
    }

    // Unkeyable device: fall back to the transport rule.
    final device = await _volumeControlService.getOutputDeviceInfo();
    if (device == null) return false;
    return device.isBluetooth && _settings.skipDuckWhenBluetooth;
  }

  /// The remembered row for the last device we looked at, without going back to
  /// CoreAudio or creating one. Used to refresh the menu after a settings save:
  /// re-registering there would resurrect a row the user had just deleted.
  AudioDevicePref? _currentDevicePrefOrNull() {
    final uid = _lastOutputDeviceUid;
    if (uid == null) return null;
    for (final pref in _settings.audioDevicePrefs) {
      if (pref.uid == uid) return pref;
    }
    return null;
  }

  /// Persist settings without the full reconfiguration [updateSettings] does.
  ///
  /// Remembering a device happens as recording starts; running the usual path
  /// would tear down and re-register every hotkey mid-utterance.
  Future<void> _persistSettingsQuietly(Settings newSettings) async {
    _settings = newSettings;
    await _settingsService.saveSettings(newSettings);
    notifyListeners();
  }

  Future<void> _syncDeviceDuckMenuItem(AudioDevicePref? pref) async {
    await _statusBarService.setDeviceSkipDuckState(
      enabled: pref?.skipDuck ?? _settings.skipDuckWhenBluetooth,
      deviceName: pref?.displayName ?? '',
    );
  }

  Future<void> updateSettings(Settings newSettings) async {
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

    // Update Dock visibility if it changed
    if (oldSettings.dockVisibilityMode != newSettings.dockVisibilityMode) {
      await _applyDockVisibility(newSettings.dockVisibilityMode);
    }

    _meetingDetector
      ..enabled = newSettings.meetingAutoDetect
      ..neverList = newSettings.meetingNeverDetectBundleIds.toSet();

    // Update status bar menu checkmark if volume duck setting changed
    if (oldSettings.duckVolumeDuringRecording != newSettings.duckVolumeDuringRecording) {
      await _statusBarService.setVolumeDuckState(newSettings.duckVolumeDuringRecording);
    }
    if (oldSettings.skipDuckWhenBluetooth != newSettings.skipDuckWhenBluetooth ||
        oldSettings.audioDevicePrefs != newSettings.audioDevicePrefs) {
      await _syncDeviceDuckMenuItem(_currentDevicePrefOrNull());
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

  Future<void> _applyDockVisibility(DockVisibilityMode mode) async {
    try {
      final modeString = mode.toString().split('.').last;
      AppLogger.debug('Applying Dock visibility mode: $modeString');

      await _lifecycleChannel.invokeMethod('setDockVisibility', {
        'mode': modeString,
      });

      // Show/hide status bar based on mode
      if (mode == DockVisibilityMode.menuBarOnly || mode == DockVisibilityMode.both) {
        await _statusBarService.showStatusBar();
        AppLogger.debug('Status bar shown for mode: $modeString');
      } else if (mode == DockVisibilityMode.dockOnly) {
        await _statusBarService.hideStatusBar();
        AppLogger.debug('Status bar hidden for mode: $modeString');
      }

      AppLogger.success('Dock visibility mode applied: $modeString');
    } catch (e) {
      AppLogger.error('Failed to apply Dock visibility mode', e);
    }
  }

  void _setupStatusBarHandlers() {
    // Wire up status bar callbacks to app service methods
    _statusBarService.onStartRecording = () {
      AppLogger.info('Status bar: Start recording requested');
      if (_state.recordingState == RecordingState.idle) {
        startRecording();
      }
    };

    _statusBarService.onStopRecording = () {
      AppLogger.info('Status bar: Stop recording requested');
      if (_state.recordingState == RecordingState.recording) {
        stopRecording();
      }
    };

    _statusBarService.onToggleMeeting = () {
      AppLogger.info('Status bar: Meeting toggle requested');
      if (isMeetingRecording) {
        endMeeting();
      } else if (isMeetingActive) {
        // Ended but not yet discarded — the panel owns that decision, so just
        // put it back in front rather than starting a second meeting.
        _setMeetingWindow(true);
      } else {
        startMeeting();
      }
    };

    _statusBarService.onOpenSettings = () {
      AppLogger.info('Status bar: Open settings requested');
      _settingsWindowService.openSettingsWindow();
    };

    _statusBarService.onRestart = () async {
      AppLogger.info('Status bar: Restart requested');
      // Restart the app by cleaning up and relaunching
      await cleanup();
      // Platform-specific restart code would go here
      // For now, just exit and let the system restart
      await Future.delayed(const Duration(milliseconds: 100));
      // This would require platform-specific implementation
    };

    _statusBarService.onCheckForUpdates = () {
      AppLogger.info('Status bar: Check for updates requested');
      // TODO: Implement update check functionality
      // This is a placeholder for future Sparkle integration
      AppLogger.warning('Update check not yet implemented');
    };

    _statusBarService.onQuit = () async {
      AppLogger.info('Status bar: Quit requested');
      await cleanup();
      // Give a brief moment for cleanup to complete
      await Future.delayed(const Duration(milliseconds: 100));
      // Exit the application
      exit(0);
    };

    _statusBarService.onToggleVolumeDuck = () async {
      AppLogger.info('Status bar: Volume duck toggle requested');
      // Toggle the setting
      final newValue = !_settings.duckVolumeDuringRecording;
      final newSettings = _settings.copyWith(duckVolumeDuringRecording: newValue);
      await updateSettings(newSettings);
      AppLogger.info('Volume duck toggled to: $newValue');
    };

    _statusBarService.onToggleSkipDuckWhenBluetooth = () async {
      AppLogger.info('Status bar: Skip-duck toggle requested for current device');
      // Re-resolve the device on click rather than trusting the menu title:
      // the output can change while the menu sits idle, and acting on a stale
      // name would write the preference onto the wrong device.
      final pref = await registerCurrentOutputDevice();
      if (pref == null) {
        // No keyable device — fall back to flipping the global default.
        final newValue = !_settings.skipDuckWhenBluetooth;
        await updateSettings(_settings.copyWith(skipDuckWhenBluetooth: newValue));
        AppLogger.info('Skip-duck-when-Bluetooth default toggled to: $newValue');
        return;
      }

      final prefs = List<AudioDevicePref>.from(_settings.audioDevicePrefs);
      final index = prefs.indexWhere((entry) => entry.uid == pref.uid);
      if (index < 0) return;
      prefs[index] = prefs[index].copyWith(skipDuck: !prefs[index].skipDuck);
      await updateSettings(_settings.copyWith(audioDevicePrefs: prefs));
      AppLogger.info(
        'Skip-duck for "${prefs[index].displayName}" toggled to: ${prefs[index].skipDuck}',
      );
    };

    AppLogger.success('Status bar event handlers configured');
  }

  // MARK: - Meetings
  //
  // A meeting is a long, two-track session that runs alongside dictation
  // rather than through it: the microphone is "me", the meeting app's own
  // output — captured with a Core Audio process tap — is "them". Attribution
  // is physical, so nothing here diarizes. See docs/MEETING_PROTOCOL.md.

  void _wireMeetingCapture() {
    _micActivityService.onSystemAudio = (pcm) => _meetingService.sendSystemAudio(pcm);
    _micActivityService.onSystemAudioSilent = _handleSystemAudioSilent;
    _micActivityService.onMicActivityChanged = (active) {
      AppLogger.debug('Microphone in use: $active');
      _meetingDetector.micActivityChanged(active);
    };

    _meetingDetector
      ..enabled = _settings.meetingAutoDetect
      ..neverList = _settings.meetingNeverDetectBundleIds.toSet()
      ..onMeetingLikely = _handleMeetingDetected;

    // The meeting owns its own state; this only forwards it to the widgets,
    // which observe AppService.
    _meetingService.addListener(_onMeetingChanged);

    unawaited(_micActivityService.startMicMonitoring());
  }

  void _onMeetingChanged() {
    // Summarize once the backend has drained the last window and moved the
    // meeting to `ended`. Doing it the instant `end()` is called would race
    // those windows and summarize a transcript missing its final minute.
    if (_autoSummarizePending &&
        _meetingService.phase == MeetingPhase.ended &&
        _meetingService.canSummarize) {
      _autoSummarizePending = false;
      // Write the transcript BEFORE asking for notes. Summarization needs
      // Ollama and can fail or hang; the words already said must be on disk
      // regardless of what happens next.
      unawaited(_saveMeeting());
      summarizeMeeting();
    }

    // A note arriving is the second and last thing worth writing.
    if (_meetingService.phase == MeetingPhase.summarized &&
        _meetingService.summary != null &&
        !_savedNoteForCurrentMeeting) {
      _savedNoteForCurrentMeeting = true;
      unawaited(_saveMeeting());
    }

    notifyListeners();
  }

  void _handleSystemAudioSilent() {
    if (_meetingSystemAudioSilent) return;
    _meetingSystemAudioSilent = true;
    AppLogger.warning(
      'The "them" track is digital silence — System Audio Recording is '
      'probably not granted. The meeting continues as mic-only.',
    );
    notifyListeners();
  }

  void _handleMeetingDetected(MeetingCandidate candidate) {
    if (isMeetingActive || _pendingMeetingPrompt != null) return;
    AppLogger.info('Meeting likely in $candidate');
    _pendingMeetingPrompt = candidate;
    notifyListeners();
    unawaited(_setMeetingWindow(true));
  }

  /// "Record" on the detection prompt.
  Future<void> acceptMeetingPrompt() async {
    final candidate = _pendingMeetingPrompt;
    _pendingMeetingPrompt = null;
    if (candidate == null) return;
    await startMeeting(target: candidate);
  }

  /// "Not now" (session cooldown) or "Never for this app" (persisted).
  Future<void> dismissMeetingPrompt({bool never = false}) async {
    final candidate = _pendingMeetingPrompt;
    _pendingMeetingPrompt = null;
    if (candidate == null) {
      notifyListeners();
      return;
    }

    if (never) {
      final bundleId = _meetingDetector.never(candidate);
      if (bundleId != null &&
          !_settings.meetingNeverDetectBundleIds.contains(bundleId)) {
        await updateSettings(_settings.copyWith(
          meetingNeverDetectBundleIds: [
            ..._settings.meetingNeverDetectBundleIds,
            bundleId,
          ],
        ));
      }
    } else {
      _meetingDetector.snooze(candidate);
    }

    if (!isMeetingActive) await _setMeetingWindow(false);
    notifyListeners();
  }

  /// Begin recording a meeting.
  ///
  /// [target] is the process to tap for "them". When it is null the running
  /// processes are scanned for one that is both capturing the mic and playing
  /// audio; if none is found the meeting runs mic-only, which the protocol
  /// supports rather than treats as broken.
  Future<void> startMeeting({MeetingCandidate? target}) async {
    if (isMeetingActive) {
      AppLogger.warning('A meeting is already in progress');
      return;
    }
    if (_state.recordingState == RecordingState.recording) {
      AppLogger.warning('Cannot start a meeting while dictation is recording');
      return;
    }

    try {
      final resolved = target ?? await _findMeetingProcess();
      _meetingTarget = resolved;
      _meetingSystemAudioSilent = false;
      _autoSummarizePending = false;
      _savedNoteForCurrentMeeting = false;
      _meetingDuration = Duration.zero;
      _meetingStartedAt = DateTime.now();
      _lastSavedMeetingFiles = const [];
      _meetingDetector.suppressed = true;

      _meetingService.start(
        meetingId: _uuid.v4(),
        language: 'auto',
        title: resolved?.name,
      );

      // "Them" first: if the tap is going to be refused outright, better to
      // know before the microphone is live.
      if (resolved != null) {
        final failure = await _micActivityService.startSystemCapture([resolved.pid]);
        if (failure != null) {
          AppLogger.warning(
            'Could not tap ${resolved.name} ($failure); recording mic only',
          );
          _meetingSystemAudioSilent = true;
        }
      } else {
        AppLogger.info('No meeting process found — recording mic only');
        _meetingSystemAudioSilent = true;
      }

      // "Me": a second subscription on the same broadcast stream, kept apart
      // from the dictation one so neither path has to know about the other.
      // Deliberately no volume ducking — the user has to hear the meeting.
      await _audioService.startRecording();
      _meetingAudioSubscription = _audioService.audioStream.listen(
        (pcm) => _meetingService.sendMicAudio(pcm),
        onError: (error) => AppLogger.error('Meeting mic stream error', error),
      );

      _meetingTimer?.cancel();
      _meetingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _meetingDuration = Duration(seconds: timer.tick);
        notifyListeners();
      });

      await _statusBarService.setMeetingState(true);
      await _setMeetingWindow(true);
      AppLogger.success('Meeting started (${resolved ?? 'mic only'})');
      notifyListeners();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to start meeting', e);
      AppLogger.debug('Stack trace: $stackTrace');
      await cancelMeeting();
    }
  }

  /// Stop recording. The transcript stays on screen and the backend keeps the
  /// session alive so notes can still be generated.
  Future<void> endMeeting({bool summarize = true}) async {
    if (!isMeetingRecording) return;

    _meetingTimer?.cancel();
    _meetingTimer = null;
    await _meetingAudioSubscription?.cancel();
    _meetingAudioSubscription = null;

    await _audioService.stopRecording();
    await _micActivityService.stopSystemCapture();

    _autoSummarizePending = summarize;
    _meetingService.end();

    await _statusBarService.setMeetingState(false);
    _meetingDetector.suppressed = false;
    AppLogger.success('Meeting ended after ${_meetingDuration.inSeconds}s');
    notifyListeners();
  }

  /// Generate notes for the meeting just recorded. Safe to call again — that is
  /// the intended way to retry with a bigger model after a weak note.
  void summarizeMeeting({String? model}) {
    if (!_meetingService.canSummarize) {
      AppLogger.warning('Nothing to summarize yet');
      return;
    }
    _meetingService.summarize(model: model ?? _settings.meetingSummaryModel);
  }

  /// Write the current meeting to the configured folder.
  ///
  /// Called twice per meeting by design — once when recording stops, once when
  /// the note arrives — so the transcript is never contingent on Ollama. The
  /// second write overwrites the first, since the filename is derived from the
  /// meeting's start time.
  Future<void> _saveMeeting() async {
    if (!_settings.saveMeetingTranscripts) return;

    _lastSavedMeetingFiles = await TranscriptArchive.save(
      directory: _settings.meetingSaveDirectory,
      transcript: _meetingService.transcript,
      transcriptText: _meetingService.transcriptText,
      title: _meetingTarget?.name,
      noteMarkdown: _meetingService.summary?.markdown,
      when: _meetingStartedAt,
    );
    notifyListeners();
  }

  /// Save on demand, for a "Save now" affordance or a retried note.
  Future<void> saveMeetingNow() => _saveMeeting();

  /// Drop the meeting and free the backend session.
  Future<void> cancelMeeting() async {
    _meetingTimer?.cancel();
    _meetingTimer = null;
    await _meetingAudioSubscription?.cancel();
    _meetingAudioSubscription = null;

    if (_audioService.isRecording && _state.recordingState != RecordingState.recording) {
      await _audioService.stopRecording();
    }
    await _micActivityService.stopSystemCapture();

    _meetingService.cancel();
    _autoSummarizePending = false;
    _meetingTarget = null;
    _meetingSystemAudioSilent = false;
    _meetingDuration = Duration.zero;
    _meetingDetector.suppressed = false;

    await _statusBarService.setMeetingState(false);
    await _setMeetingWindow(false);
    notifyListeners();
  }

  /// The first process that is both capturing the mic and playing audio.
  ///
  /// The same rule the detector uses, applied on demand so a meeting started
  /// by hand still gets its "them" track chosen automatically.
  Future<MeetingCandidate?> _findMeetingProcess() async {
    final processes = await _micActivityService.listAudioProcesses();
    for (final process in processes) {
      if (process['runningInput'] != true || process['runningOutput'] != true) {
        continue;
      }
      final processPid = process['pid'];
      if (processPid is! int || processPid == pid) continue;
      return MeetingCandidate(
        pid: processPid,
        name: (process['name'] ?? 'pid $processPid').toString(),
        bundleId: process['bundleId'] as String?,
      );
    }
    return null;
  }

  /// Grow the overlay window into a readable panel, and shrink it back after.
  ///
  /// The main window is a 360x100 dictation overlay; a live transcript needs
  /// more than that, and the app is LSUIElement so there is no Dock icon to
  /// click when a prompt appears.
  Future<void> _setMeetingWindow(bool expanded) async {
    if (_meetingWindowExpanded == expanded) return;
    _meetingWindowExpanded = expanded;
    try {
      await windowManager.setSize(
        expanded
            ? const Size(420, 520)
            : Size(_settings.overlayWidth, _settings.overlayHeight),
      );
      if (expanded) {
        await windowManager.show();
        await windowManager.focus();
      }
    } catch (e) {
      AppLogger.error('Failed to resize window for the meeting panel', e);
    }
  }

  void _updateState(AppState newState) {
    _state = newState;
    notifyListeners();
  }

  Future<void> cleanup() async {
    AppLogger.info('Cleaning up AppService...');
    _recordingTimer?.cancel();
    _audioStreamSubscription?.cancel();

    // The tap owns a real aggregate audio device. Leaving it behind would keep
    // the meeting app's output routed through a device nothing is reading.
    _meetingTimer?.cancel();
    await _meetingAudioSubscription?.cancel();
    _meetingAudioSubscription = null;
    _meetingDetector.dispose();
    await _micActivityService.stopSystemCapture();
    await _micActivityService.stopMicMonitoring();

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
    _meetingTimer?.cancel();
    _meetingAudioSubscription?.cancel();
    _meetingDetector.dispose();
    _meetingService.removeListener(_onMeetingChanged);

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
