import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'models/app_state.dart';
import 'models/settings.dart';
import 'services/app_service.dart';
import 'services/audio_service.dart';
import 'services/settings_service.dart';
import 'services/backend_service.dart';
import 'services/hotkey_service.dart';
import 'services/paste_service.dart';
import 'services/audio_cue_service.dart';
import 'services/settings_window_service.dart';
import 'services/volume_control_service.dart';
import 'services/status_bar_service.dart';
import 'theme/focus_theme.dart';
import 'widgets/app_content.dart';
import 'windows/settings_window_entry.dart';
import 'windows/setup_window_entry.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Handle window routing for desktop_multi_window
  if (args.firstOrNull == 'multi_window') {
    // args[1] is the window ID, args[2] is the argument
    final argument = args[2];

    // Route to appropriate window based on argument
    if (argument == 'settings') {
      settingsWindowMain();
      return;
    }
    if (argument == 'setup') {
      setupWindowMain();
      return;
    }
  }

  // Initialize window manager for overlay functionality
  await windowManager.ensureInitialized();

  // Initialize acrylic for glass effects
  await Window.initialize();

  runApp(const UltraWhisperApp());
}

class UltraWhisperApp extends StatefulWidget {
  const UltraWhisperApp({super.key});

  @override
  State<UltraWhisperApp> createState() => _UltraWhisperAppState();
}

class _UltraWhisperAppState extends State<UltraWhisperApp>
    with WindowListener {
  late AppService _appService;
  bool _isInitialized = false;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // Every NSApplication termination — ⌘Q, the Dock's Quit, logout, and
    // `osascript -e 'quit app "UltraWhisper"'` — reaches Dart as
    // System.requestAppExit. Without a handler the framework answers "exit"
    // at once and cleanup never runs. The backend's own parent-pid watchdog
    // covers crashes; this covers the orderly path.
    _lifecycleListener = AppLifecycleListener(onExitRequested: _onExitRequested);
    _initializeApp();
  }

  Future<AppExitResponse> _onExitRequested() async {
    if (_isInitialized) {
      try {
        await _appService.cleanup();
      } catch (e) {
        debugPrint('Cleanup before exit failed: $e');
      }
    }
    return AppExitResponse.exit;
  }

  Future<void> _initializeApp() async {
    // Initialize services
    final audioService = AudioService();
    final settingsService = SettingsService();
    final backendService = BackendService();
    final hotkeyService = HotkeyService();
    final pasteService = PasteService();
    final audioCueService = AudioCueService.instance;
    final settingsWindowService = SettingsWindowService();
    final volumeControlService = VolumeControlService();
    final statusBarService = StatusBarService();

    _appService = AppService(
      audioService: audioService,
      settingsService: settingsService,
      backendService: backendService,
      hotkeyService: hotkeyService,
      pasteService: pasteService,
      audioCueService: audioCueService,
      settingsWindowService: settingsWindowService,
      volumeControlService: volumeControlService,
      statusBarService: statusBarService,
    );

    // Before initialize: on first launch it opens the setup window, which
    // talks to this engine straight away.
    DesktopMultiWindow.setMethodHandler(_handleMethodCall);

    // Initialize audio cue service
    await audioCueService.initialize();

    // Initialize the app service
    await _appService.initialize();

    // Configure window properties
    await _configureWindow();

    // Set up signal handlers for graceful shutdown
    _setupSignalHandlers();

    // Listen for settings window state changes
    _appService.addListener(_handleAppServiceChanges);

    setState(() {
      _isInitialized = true;
    });
  }

  Future<void> _configureWindow() async {
    if (!mounted) return;

    // Get settings for window configuration
    final settings = _appService.settings;

    // Configure main window to be hidden by default (menu bar only)
    WindowOptions windowOptions = WindowOptions(
      size: Size(settings.overlayWidth, settings.overlayHeight),
      center: false,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // A normal window, on every Space and over full-screen apps. It is not
      // pinned on top: a recording raises it once (AppService._raiseOverlay)
      // and clicking another app lets that app cover it again. Idle it draws
      // nothing and lets clicks through.
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setVisibleOnAllWorkspaces(
        true,
        visibleOnFullScreen: true,
      );

      // Top centre of the screen under the cursor, just below the menu bar —
      // on a notched Mac that is right under the notch, since the visible
      // area starts where the menu bar ends. Drag the island to move it.
      await windowManager.setAlignment(Alignment.topCenter);

      await windowManager.show();
    });

    // No frame: the window is fully clear, so the only thing on screen is
    // the island the overlay draws (and nothing at all while idle).
    WindowManipulator.makeWindowFullyTransparent();
    WindowManipulator.hideCloseButton();
    WindowManipulator.hideMiniaturizeButton();
    WindowManipulator.hideZoomButton();
    await _syncMouseEvents();

    windowManager.addListener(this);
  }

  void _setupSignalHandlers() {
    // Handle SIGTERM and SIGINT for graceful shutdown
    ProcessSignal.sigterm.watch().listen((_) async {
      debugPrint('Received SIGTERM, cleaning up...');
      await _cleanupAndExit();
    });

    ProcessSignal.sigint.watch().listen((_) async {
      debugPrint('Received SIGINT, cleaning up...');
      await _cleanupAndExit();
    });
  }

  Future<void> _cleanupAndExit() async {
    if (_isInitialized) {
      await _appService.cleanup();
    }
    exit(0);
  }

  void _handleAppServiceChanges() async {
    if (!_isInitialized) return;
    await _syncMouseEvents();
  }

  bool? _ignoringMouse;

  /// While nothing is drawn, clicks pass through the clear window to whatever
  /// is under it; the island and the meeting panel take them back.
  Future<void> _syncMouseEvents() async {
    final idle = _appService.state.recordingState == RecordingState.idle &&
        _appService.pendingMeetingPrompt == null &&
        !_appService.isMeetingActive;
    if (idle == _ignoringMouse) return;
    _ignoringMouse = idle;
    await windowManager.setIgnoreMouseEvents(idle);
  }

  /// Handle method calls from other windows (e.g., settings window)
  Future<dynamic> _handleMethodCall(
      MethodCall call, int fromWindowId) async {
    debugPrint('Received method call from window $fromWindowId: ${call.method}');

    switch (call.method) {
      case 'settings_window_closed':
        // Settings window notifies that it's closing
        // Close it from the main window and update state
        await _appService.settingsWindowService.closeSettingsWindow();
        return true;

      case 'get_settings':
        // Settings window requests current settings. Register the device in use
        // first, so the per-device ducking table is never empty on a machine
        // that simply has not recorded yet.
        debugPrint('Settings window requesting current settings');
        await _appService.registerCurrentOutputDevice();
        return _appService.settings.toJson();

      case 'pick_directory':
        // The settings window is a desktop_multi_window child with its own
        // engine, so it has no route to the native channels registered on the
        // main engine. It asks; this forwards.
        try {
          const channel = MethodChannel('com.ultrawhisper.folder_picker');
          return await channel.invokeMethod<String>('pickDirectory', {
            'initialPath': call.arguments is String ? call.arguments : '',
          });
        } catch (e) {
          debugPrint('Folder picker failed: $e');
          return null;
        }

      case 'setup_window_closed':
        await _appService.settingsWindowService.closeSetupWindow();
        return true;

      case 'open_setup':
        await _appService.settingsWindowService.closeSettingsWindow();
        await _appService.openSetupWindow();
        return true;

      case 'finish_setup':
        final chosen = Settings.fromJson(Map<String, dynamic>.from(call.arguments as Map));
        await _appService.finishSetup(chosen);
        return true;

      case 'permissions_status':
        return _appService.permissionsStatus();

      case 'request_microphone':
        return _appService.requestMicrophone();

      case 'request_accessibility':
        await _appService.requestAccessibility();
        return true;

      // Models. Downloads run here, in the main engine, so they outlive the
      // window that asked for them; the windows poll models_status.
      case 'models_status':
        final args = call.arguments is Map ? call.arguments as Map : const {};
        if (args['refreshOllama'] == true) {
          await _appService.modelManager.refreshOllama();
        }
        return _appService.modelManager.statusJson();

      case 'download_speech_model':
        unawaited(_appService.modelManager.downloadSpeechModel(call.arguments as String));
        return true;

      case 'delete_speech_model':
        return _appService.deleteSpeechModel(call.arguments as String);

      case 'cancel_task':
        _appService.modelManager.cancel(call.arguments as String);
        return true;

      case 'install_ollama':
        unawaited(_appService.modelManager.installOllamaRuntime());
        return true;

      case 'pull_ollama_model':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        unawaited(_appService.modelManager.pullOllamaModel(
          args['tag'] as String,
          label: args['label'] as String?,
        ));
        return true;

      case 'delete_ollama_model':
        await _appService.modelManager.deleteOllamaModel(call.arguments as String);
        return true;

      // The Anthropic key lives in the Keychain, reachable only from this
      // engine. The settings window may save or remove it, and learns only
      // whether one is saved — the key never travels back to it.
      case 'anthropic_key_status':
        return _appService.anthropicKeys.hasKey();

      case 'save_anthropic_key':
        return _appService.anthropicKeys.save(call.arguments as String);

      case 'delete_anthropic_key':
        return _appService.anthropicKeys.delete();

      case 'save_settings':
        // Settings window wants to save new settings
        // Convert from platform channel Map<Object?, Object?> to Map<String, dynamic>
        final settingsJson = Map<String, dynamic>.from(call.arguments as Map);
        debugPrint('Settings window saving new settings');
        final newSettings = Settings.fromJson(settingsJson);
        await _appService.updateSettings(newSettings);
        return true;

      default:
        debugPrint('Unknown method call: ${call.method}');
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: FocusIsland.ink2,
            ),
          ),
        ),
        debugShowCheckedModeBanner: false,
      );
    }

    return ChangeNotifierProvider<AppService>.value(
      value: _appService,
      child: MaterialApp(
        title: 'UltraWhisper',
        // The overlay and the meeting panel draw themselves as the black
        // Focus island; the dark theme only reaches their popup menu.
        theme: focusTheme(Brightness.dark),
        home: const UltraWhisperHome(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }

  @override
  void onWindowClose() async {
    // Clean up backend process before closing
    await _appService.cleanup();
    await windowManager.destroy();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    windowManager.removeListener(this);
    _appService.removeListener(_handleAppServiceChanges);
    _appService.dispose();
    super.dispose();
  }
}

class UltraWhisperHome extends StatelessWidget {
  const UltraWhisperHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppService>(
      builder: (context, appService, child) {
        return const AppContent();
      },
    );
  }
}
