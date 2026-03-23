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
            // Find processes using the port
            final result = await Process.run('lsof', ['-i', ':$_backendPort', '-t']);
            if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
              final pids = result.stdout.toString().trim().split('\n');
              for (final pid in pids) {
                if (pid.trim().isNotEmpty) {
                  AppLogger.debug('Killing orphaned process with PID: $pid');
                  await Process.run('kill', ['-9', pid.trim()]);
                }
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
  
  Future<String> _getBackendPath() async {
    // In development, we'll assume the backend is in a relative path
    // In production, it would be embedded in the app bundle
    if (kDebugMode) {
      // Development path - look for backend relative to project root
      // You may need to adjust this path based on your project location
      final currentDir = Directory.current.path;
      return '$currentDir/backend/server.py';
    } else {
      // Production path - embedded in app bundle
      // Get the path to the executable to determine bundle location
      final executablePath = Platform.resolvedExecutable;
      final executableDir = File(executablePath).parent.path;

      // In a macOS app bundle: Contents/MacOS/executable
      // We need to go to: Contents/Resources/backend/server.py (v3 uses root backend dir)
      final backendPath = '$executableDir/../Resources/backend/server.py';

      AppLogger.debug('Resolved backend path: $backendPath');
      return backendPath;
    }
  }

  Future<String> _getPythonPath() async {
    // Try bundled Python first (for self-contained distribution)
    if (!kDebugMode) {
      // Production: Use bundled Python
      final executablePath = Platform.resolvedExecutable;
      final executableDir = File(executablePath).parent.path;
      final bundledPython = '$executableDir/../Resources/python/bin/python3';

      if (await File(bundledPython).exists()) {
        AppLogger.debug('Using bundled Python: $bundledPython');
        return bundledPython;
      } else {
        AppLogger.warning('Bundled Python not found at $bundledPython, falling back to system Python');
      }
    }

    // Development or fallback: Use system Python
    AppLogger.debug('Using system Python: python3');
    return 'python3';
  }

  Future<Map<String, String>> _getBackendEnvironment() async {
    final environment = <String, String>{};

    if (!kDebugMode) {
      // Production: Set DYLD_LIBRARY_PATH for all whisper.cpp and GGML dependencies
      final executablePath = Platform.resolvedExecutable;
      final executableDir = File(executablePath).parent.path;
      final backendBase = '$executableDir/../Resources/backend/whisper.cpp/build';

      // Include all library directories
      final libraryPaths = [
        '$backendBase/src',                          // libwhisper
        '$backendBase/ggml/src',                     // main GGML libs
        '$backendBase/ggml/src/ggml-blas',          // GGML BLAS
        '$backendBase/ggml/src/ggml-metal',         // GGML Metal
      ].join(':');

      environment['DYLD_LIBRARY_PATH'] = libraryPaths;
      AppLogger.debug('Setting DYLD_LIBRARY_PATH to: $libraryPaths');
    } else {
      // Development: Use current working directory for library paths
      final currentDir = Directory.current.path;
      final backendBase = '$currentDir/backend/whisper.cpp/build';

      final libraryPaths = [
        '$backendBase/src',
        '$backendBase/ggml/src',
        '$backendBase/ggml/src/ggml-blas',
        '$backendBase/ggml/src/ggml-metal',
      ].join(':');

      environment['DYLD_LIBRARY_PATH'] = libraryPaths;
      AppLogger.debug('Setting DYLD_LIBRARY_PATH to: $libraryPaths');
    }

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
        AppLogger.debug('Backend stdout: $line');
        
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
        AppLogger.error('Backend stderr: $line');
        stderrBuffer.writeln(line);

        // Check for common library loading errors
        if (line.contains('dyld') || line.contains('Library not loaded') ||
            line.contains('libggml') || line.contains('libwhisper')) {
          AppLogger.error('⚠️ CRITICAL: Dynamic library loading error detected!');
          AppLogger.error('This likely means GGML libraries are missing from the app bundle.');
        }
      });
      
      // Monitor process exit
      _backendProcess!.exitCode.then((exitCode) {
        AppLogger.error('Backend process exited with code: $exitCode');
        if (exitCode != 0 && stderrBuffer.isNotEmpty) {
          AppLogger.error('Backend stderr output:');
          AppLogger.error(stderrBuffer.toString());
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