import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../utils/logger.dart';

class BackendService {
  Process? _backendProcess;
  int? _port;
  static const int _backendPort = 8082;  // Fixed port for v3
  static File? _lockFile;
  static File? _pidFile;
  
  Future<void> initialize() async {
    try {
      AppLogger.info('Initializing backend service...');

      // Clean up any orphaned processes from previous runs
      await _cleanupOrphanedProcesses();

      await _startBackendProcess();
      AppLogger.success('Backend service initialized on port $_port');
    } catch (e) {
      AppLogger.error('Failed to initialize backend', e);
      throw Exception('Backend initialization failed: $e');
    }
  }

  Future<void> _cleanupOrphanedProcesses() async {
    try {
      AppLogger.debug('Checking for orphaned backend processes...');

      // Initialize lock and PID files
      final tempDir = Directory.systemTemp.path;
      _lockFile = File(path.join(tempDir, 'ultrawhisper_backend.lock'));
      _pidFile = File(path.join(tempDir, 'ultrawhisper_backend.pid'));

      // Check if there's a stale lock file from a previous crash
      if (await _lockFile!.exists()) {
        AppLogger.warning('Found stale lock file, checking if process is still running...');

        // Try to read PID from file
        if (await _pidFile!.exists()) {
          try {
            final pidStr = await _pidFile!.readAsString();
            final pid = int.tryParse(pidStr.trim());

            if (pid != null) {
              // Check if process is still running
              final result = await Process.run('kill', ['-0', pid.toString()]);
              if (result.exitCode == 0) {
                AppLogger.info('Found running backend process with PID $pid, killing it...');
                await Process.run('kill', ['-9', pid.toString()]);
                await Future.delayed(const Duration(seconds: 1));
              }
            }
          } catch (e) {
            AppLogger.debug('Could not read PID file: $e');
          }
        }

        // Remove stale lock file
        await _lockFile!.delete();
        AppLogger.info('Removed stale lock file');
      }

      // Check if there's a process using our backend port
      if (await _isPortInUse(_backendPort)) {
        AppLogger.warning('Found process using backend port $_backendPort, attempting to clean up...');

        // Try to find and kill Python processes that might be our backend
        if (Platform.isMacOS) {
          try {
            // Find processes actually listening on the port (excludes sockets
            // that merely reference it, e.g. our own outbound probe connection
            // from _isPortInUse, which would otherwise show up in TIME_WAIT).
            final result = await Process.run('lsof', ['-i', ':$_backendPort', '-sTCP:LISTEN', '-t']);
            if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
              final pids = result.stdout.toString().trim().split('\n');
              final myPid = pid;
              for (final pidStr in pids) {
                final trimmed = pidStr.trim();
                if (trimmed.isEmpty) continue;
                final candidatePid = int.tryParse(trimmed);
                if (candidatePid == null || candidatePid == myPid) {
                  AppLogger.warning('Skipping cleanup kill for suspicious/self PID: $trimmed');
                  continue;
                }
                AppLogger.debug('Killing orphaned process with PID: $trimmed');
                await Process.run('kill', ['-9', trimmed]);
              }

              // Wait a moment for the port to be released
              await Future.delayed(const Duration(seconds: 1));

              if (!await _isPortInUse(_backendPort)) {
                AppLogger.success('Successfully cleaned up orphaned backend process');
              }
            }
          } catch (e) {
            AppLogger.warning('Could not clean up orphaned process: $e');
          }
        }
      }

      // Clean up PID file if it exists
      if (await _pidFile!.exists()) {
        await _pidFile!.delete();
      }
    } catch (e) {
      AppLogger.warning('Error during orphaned process cleanup: $e');
      // Don't fail initialization just because cleanup had issues
    }
  }

  Future<void> _startBackendProcess() async {
    try {
      // Always try to launch the backend process
      // Check if backend is already running on the configured port
      if (await _isPortInUse(_backendPort)) {
        AppLogger.debug('Backend already running on port $_backendPort, using existing instance');
        _port = _backendPort;

        // Initialize lock files even when reusing existing backend
        final tempDir = Directory.systemTemp.path;
        _lockFile = File(path.join(tempDir, 'ultrawhisper_backend.lock'));
        _pidFile = File(path.join(tempDir, 'ultrawhisper_backend.pid'));

        AppLogger.success('Connected to existing backend on port $_port');
        return;
      }

      AppLogger.debug('Starting new backend process...');

      // Production code would launch the embedded backend here
      // Get the path to the backend script
      final backendPath = await _getBackendPath();
      AppLogger.debug('Backend path: $backendPath');

      if (!await File(backendPath).exists()) {
        throw Exception('Backend script not found at: $backendPath');
      }

      // Get the path to Python executable (bundled or system)
      final pythonPath = await _getPythonPath();
      AppLogger.debug('Python path: $pythonPath');

      // Set up environment with library paths for GGML dependencies
      final environment = await _getBackendEnvironment();
      AppLogger.debug('Backend environment: $environment');

      // Start the Python backend process with configured port
      AppLogger.debug('Starting backend process...');
      _backendProcess = await Process.start(
        pythonPath,
        [backendPath, '--port', '$_backendPort', '--host', '127.0.0.1'],
        mode: ProcessStartMode.normal,
        environment: environment,
      );

      if (_backendProcess == null) {
        throw Exception('Failed to start backend process');
      }

      AppLogger.debug('Backend process started, waiting for port...');

      // Wait for the backend to report its port
      _port = await _readPortFromBackend();

      if (_port == null || _port != _backendPort) {
        throw Exception('Failed to get correct port from backend, expected $_backendPort, got $_port');
      }

      // Create lock file and store PID
      await _createLockFiles();

      AppLogger.success('Backend started successfully on port $_port');
    } catch (e) {
      AppLogger.error('Error starting backend process', e);
      await _cleanup();
      rethrow;
    }
  }
  
  Future<bool> _isPortInUse(int port) async {
    try {
      final socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(seconds: 2));
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// The directory holding the running executable.
  ///
  /// Every path below is derived from this rather than from
  /// `Directory.current`. The working directory is the project root under
  /// `flutter run` but `/` when the app is launched by Finder or `open` — so a
  /// cwd-relative debug path resolved to `/backend/server.py`, the backend
  /// never started, and the app came up in its error state showing red
  /// waveform bars. Launching with `open` is not an edge case: it is the only
  /// way to test macOS permissions, because TCC attributes a grant to the
  /// responsible process, which for a shell launch is the terminal.
  String get _executableDir => File(Platform.resolvedExecutable).parent.path;

  /// `Contents/Resources/backend` inside the app bundle. Populated on every
  /// build, Debug included, by macos/Scripts/copy_backend.sh.
  String get _bundledBackendRoot =>
      path.normalize(path.join(_executableDir, '..', 'Resources', 'backend'));

  String? _backendRoot;

  /// The checkout this build came from, or null for an installed copy.
  ///
  /// Found by walking up from the executable — a Debug build sits at
  /// `build/macos/Build/Products/Debug/UltraWhisper.app/Contents/MacOS` inside
  /// the project — and matching on marker files rather than counting parents,
  /// so a changed build layout does not silently pick the wrong directory.
  Future<String?> _findSourceRoot() async {
    var dir = Directory(_executableDir);
    for (var depth = 0; depth < 12; depth++) {
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
      if (await File(path.join(dir.path, 'pubspec.yaml')).exists() &&
          await File(path.join(dir.path, 'backend', 'server.py')).exists()) {
        return dir.path;
      }
    }
    return null;
  }

  /// The directory containing `server.py`, whichever copy is actually present.
  ///
  /// In Debug the checkout wins so backend edits take effect on an app restart
  /// without a full rebuild; otherwise the bundled copy is used. The working
  /// directory is consulted last and only as a safety net.
  Future<String> _resolveBackendRoot() async {
    if (_backendRoot != null) return _backendRoot!;

    final candidates = <String>[
      if (kDebugMode)
        ...[
          for (final root in [await _findSourceRoot()])
            if (root != null) path.join(root, 'backend'),
        ],
      _bundledBackendRoot,
      path.join(Directory.current.path, 'backend'),
    ];

    for (final candidate in candidates) {
      if (await File(path.join(candidate, 'server.py')).exists()) {
        AppLogger.debug('Resolved backend root: $candidate');
        _backendRoot = candidate;
        return candidate;
      }
    }

    throw Exception(
      'Backend script not found. Looked in: ${candidates.join(", ")}',
    );
  }

  Future<String> _getBackendPath() async =>
      path.join(await _resolveBackendRoot(), 'server.py');

  Future<String> _getPythonPath() async {
    // The bundled interpreter carries websockets and numpy, so preferring it in
    // Debug too means the app runs the same Python it ships with instead of
    // whatever `python3` happens to be first on PATH.
    final bundledPython =
        path.normalize(path.join(_executableDir, '..', 'Resources', 'python', 'bin', 'python3'));

    if (await File(bundledPython).exists()) {
      AppLogger.debug('Using bundled Python: $bundledPython');
      return bundledPython;
    }

    AppLogger.warning(
      'Bundled Python not found at $bundledPython, falling back to system Python',
    );
    return 'python3';
  }

  Future<Map<String, String>> _getBackendEnvironment() async {
    final environment = <String, String>{};

    // The libraries have to come from the same tree as the server.py being
    // run, so this follows whatever _resolveBackendRoot settled on. The bundle
    // is the fallback because a fresh checkout has no whisper.cpp/build —
    // those artifacts are untracked and usually symlinked in.
    var backendBase =
        path.join(await _resolveBackendRoot(), 'whisper.cpp', 'build');
    if (!await Directory(path.join(backendBase, 'src')).exists()) {
      AppLogger.warning(
        'No whisper.cpp build under $backendBase; using the bundled libraries',
      );
      backendBase = path.join(_bundledBackendRoot, 'whisper.cpp', 'build');
    }

    // DYLD_LIBRARY_PATH rather than @rpath alone: the ggml dylibs reference
    // each other by @rpath, and the Python process loading them has no rpath
    // of its own to resolve against.
    final libraryPaths = [
      path.join(backendBase, 'src'),                        // libwhisper
      path.join(backendBase, 'ggml', 'src'),                // main GGML libs
      path.join(backendBase, 'ggml', 'src', 'ggml-blas'),   // GGML BLAS
      path.join(backendBase, 'ggml', 'src', 'ggml-metal'),  // GGML Metal
    ].join(':');

    environment['DYLD_LIBRARY_PATH'] = libraryPaths;
    AppLogger.debug('Setting DYLD_LIBRARY_PATH to: $libraryPaths');

    // Keep Python's bytecode cache OUT of the app bundle.
    //
    // This is not a tidiness measure. The bundled interpreter's stdlib and
    // site-packages live in Contents/Resources/python, and those .pyc files are
    // SEALED RESOURCES. Python rewrites one whenever the recorded source
    // mtime/size no longer matches — which the build's own copy step
    // guarantees — and the moment it does, `codesign -v` fails with "a sealed
    // resource is missing or invalid".
    //
    // What that costs is not obvious and cost this project days: TCC matches a
    // running app against the code requirement it stored when the permission
    // was granted, and a broken seal matches nothing. So the app keeps its
    // grant in System Settings, `auth_value` stays 2 in TCC.db, and every
    // gated capability fails anyway. For Core Audio process taps that failure
    // is digital silence rather than an error, which is why the "them" track
    // read as a permission problem for so long. Verified 2026-08-25: the
    // signature passed on a fresh build and failed after the first launch,
    // with the modified .pyc files named in `codesign --verify --verbose=4`.
    //
    // PYTHONPYCACHEPREFIX rather than PYTHONDONTWRITEBYTECODE so caching still
    // happens, just somewhere writable that is not sealed.
    final cacheRoot = path.join(
      Platform.environment['HOME'] ?? '/tmp',
      'Library', 'Caches', 'UltraWhisper', 'pycache',
    );
    environment['PYTHONPYCACHEPREFIX'] = cacheRoot;
    AppLogger.debug('Setting PYTHONPYCACHEPREFIX to: $cacheRoot');

    return environment;
  }
  
  Future<int?> _readPortFromBackend() async {
    if (_backendProcess == null) return null;
    
    try {
      // Listen to stdout for port information
      final completer = Completer<int?>();
      
      _backendProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        // Only log port-related lines; Python backend already prints its own output
        if (line.startsWith('SERVER_PORT:')) {
          AppLogger.debug('Backend: $line');
        }
        
        // Look for port information in the format "SERVER_PORT:8080"
        if (line.startsWith('SERVER_PORT:')) {
          final portStr = line.substring('SERVER_PORT:'.length);
          final port = int.tryParse(portStr);
          if (port != null && !completer.isCompleted) {
            AppLogger.debug('Found backend port: $port');
            completer.complete(port);
          }
        }
      });
      
      // Collect stderr for better error reporting
      final stderrBuffer = StringBuffer();
      _backendProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stderrBuffer.writeln(line);

        // Only surface critical library loading errors; routine stderr already visible
        if (line.contains('dyld') || line.contains('Library not loaded') ||
            line.contains('libggml') || line.contains('libwhisper')) {
          AppLogger.error('CRITICAL: Dynamic library loading error detected!');
          AppLogger.error('This likely means GGML libraries are missing from the app bundle.');
        }
      });
      
      // Monitor process exit
      _backendProcess!.exitCode.then((exitCode) {
        if (exitCode != 0) {
          AppLogger.error('Backend process exited with code: $exitCode');
          if (stderrBuffer.isNotEmpty) {
            AppLogger.error('Backend stderr:\n$stderrBuffer');
          }
        }
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });
      
      // Timeout after 30 seconds (backend needs time to download models)
      Timer(const Duration(seconds: 30), () {
        if (!completer.isCompleted) {
          AppLogger.error('Timeout waiting for backend port');
          completer.complete(null);
        }
      });
      
      return await completer.future;
    } catch (e) {
      AppLogger.error('Error reading port from backend', e);
      return null;
    }
  }
  
  int? getPort() {
    return _port;
  }
  
  bool get isRunning => _backendProcess != null && _port != null;
  
  Future<void> restart() async {
    AppLogger.info('Restarting backend...');
    await stop();
    await _startBackendProcess();
  }
  
  Future<void> stop() async {
    if (_backendProcess != null) {
      AppLogger.info('Stopping backend process...');
      
      // First try graceful shutdown
      _backendProcess!.kill(ProcessSignal.sigterm);
      
      // Wait for process to exit with timeout
      try {
        await _backendProcess!.exitCode.timeout(const Duration(seconds: 5));
        AppLogger.success('Backend process terminated gracefully');
      } catch (e) {
        // If it doesn't exit gracefully, force kill
        AppLogger.warning('Backend didn\'t respond to SIGTERM, force killing...');
        _backendProcess!.kill(ProcessSignal.sigkill);
        await _backendProcess!.exitCode;
        AppLogger.info('Backend process force killed');
      }
      
      await _cleanup();
    } else {
      AppLogger.debug('No backend process to stop');
    }
  }
  
  Future<void> _createLockFiles() async {
    try {
      if (_backendProcess != null) {
        // Create lock file
        if (_lockFile != null) {
          await _lockFile!.writeAsString('locked');
          AppLogger.debug('Created lock file: ${_lockFile!.path}');
        }

        // Store backend process PID
        if (_pidFile != null && _backendProcess!.pid > 0) {
          await _pidFile!.writeAsString(_backendProcess!.pid.toString());
          AppLogger.debug('Created PID file with PID: ${_backendProcess!.pid}');
        }
      }
    } catch (e) {
      AppLogger.warning('Could not create lock/PID files: $e');
      // Don't fail if we can't create these files
    }
  }

  Future<void> _removeLockFiles() async {
    try {
      // Remove lock file
      if (_lockFile != null && await _lockFile!.exists()) {
        await _lockFile!.delete();
        AppLogger.debug('Removed lock file');
      }

      // Remove PID file
      if (_pidFile != null && await _pidFile!.exists()) {
        await _pidFile!.delete();
        AppLogger.debug('Removed PID file');
      }
    } catch (e) {
      AppLogger.warning('Could not remove lock/PID files: $e');
    }
  }

  Future<void> _cleanup() async {
    // Remove lock files on cleanup
    await _removeLockFiles();

    _backendProcess = null;
    _port = null;
  }
  
  void dispose() {
    AppLogger.info('Disposing BackendService...');
    // Note: This is called synchronously, backend cleanup should happen in cleanup() method
    if (_backendProcess != null) {
      AppLogger.warning('Backend process still running during dispose, force killing...');
      _backendProcess!.kill(ProcessSignal.sigkill);
    }
  }
}