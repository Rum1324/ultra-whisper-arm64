import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'services/app_service.dart';
import 'services/audio_service.dart';
import 'services/settings_service.dart';
import 'services/backend_service.dart';
import 'services/hotkey_service.dart';
import 'services/paste_service.dart';
import 'services/audio_cue_service.dart';
import 'services/settings_window_service.dart';
import 'widgets/app_content.dart';
import 'windows/settings_window_entry.dart';

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

  @override
  void initState() {
    super.initState();
    _initializeApp();
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

    _appService = AppService(
      audioService: audioService,
      settingsService: settingsService,
      backendService: backendService,
      hotkeyService: hotkeyService,
      pasteService: pasteService,
      audioCueService: audioCueService,
      settingsWindowService: settingsWindowService,
    );

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

    // Set up message handler for multi-window communication
    DesktopMultiWindow.setMethodHandler(_handleMethodCall);

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
      windowButtonVisibility: true,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // Keep normal window behavior - no frameless, no workspace visibility
      await windowManager.setAlwaysOnTop(settings.alwaysOnTop);

      // Position window in top-right corner - hardcoded for now
      await windowManager.setPosition(const Offset(1000, 40));

      await windowManager.show();
    });

    // Enable acrylic effects using settings
    await Window.setEffect(
      effect: _getWindowEffect(settings.glassEffect),
      color: Colors.black.withValues(alpha: settings.glassOpacity),
    );

    windowManager.addListener(this);
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
    // Settings window is now shown as a dialog overlay,
    // so we don't need to reconfigure the main window
    if (!_isInitialized) return;
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
              color: Colors.blue.withValues(alpha: 0.7),
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
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ), 
          useMaterial3: true,
        ),
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
