import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../utils/app_paths.dart';
import '../utils/logger.dart';
import 'file_downloader.dart';

/// Which Ollama the AI features talk to.
enum OllamaMode {
  /// Neither the user's own Ollama nor the private copy is available.
  none,

  /// The user's own Ollama, on its default port.
  external,

  /// The copy UltraWhisper downloaded into Application Support.
  managed,
}

/// Running total of an `ollama pull`.
///
/// A pull streams one progress line per layer, and every layer carries its own
/// `total` and `completed`. Summing over digests is the only way to get one
/// honest bar: the last line alone would jump back to 0% at each new layer.
class PullProgress {
  final Map<String, int> _totals = {};
  final Map<String, int> _completed = {};
  String status = 'starting';

  int get total => _totals.values.fold(0, (a, b) => a + b);
  int get completed => _completed.values.fold(0, (a, b) => a + b);
  bool get isDone => status == 'success';

  /// Fold in one line of the stream. Throws on an `error` line, which is how
  /// Ollama reports a tag that does not exist or a registry that is down.
  void apply(Map<String, dynamic> line) {
    final error = line['error'];
    if (error != null) throw Exception(error.toString());
    status = (line['status'] ?? status).toString();
    final digest = line['digest'];
    if (digest is String) {
      final total = line['total'];
      final completed = line['completed'];
      if (total is int) _totals[digest] = total;
      if (completed is int) _completed[digest] = completed;
    }
  }
}

/// The local Ollama behind AI formatting and meeting notes.
///
/// Prefers the user's own Ollama when one is running. Otherwise it can download
/// a pinned Ollama release into Application Support and run it headless on a
/// private port — no Ollama.app, no menu bar icon, nothing for a friend to
/// install by hand. Either way it is never a dependency: transcription works
/// without it, and every AI feature falls back to the rule-based text.
class OllamaService {
  static const version = 'v0.40.0';
  static final archiveUrl = Uri.parse(
    'https://github.com/ollama/ollama/releases/download/$version/ollama-darwin.tgz',
  );
  // GitHub's own digest for the release asset.
  static const archiveSha256 =
      'b490b4925a95c5f3dfcd889e566cf3dcd727848d59057fb00b03f1d6630326dc';
  static const archiveBytes = 167494179;

  static const defaultExternalHost = 'http://127.0.0.1:11434';

  OllamaService({this.externalHost = defaultExternalHost});

  /// Where the user's own Ollama would be. Overridable so a test can exercise
  /// the private copy on a Mac that also runs Ollama.
  final String externalHost;

  /// Not 11434, so the private copy never fights the user's own Ollama for a
  /// port if they install it later.
  static const managedPort = 11435;
  static const managedHost = 'http://127.0.0.1:$managedPort';

  OllamaMode _mode = OllamaMode.none;
  Process? _process;
  Future<void>? _starting;

  OllamaMode get mode => _mode;

  /// Where to send requests, or null when no Ollama is available.
  String? get host => switch (_mode) {
        OllamaMode.external => externalHost,
        OllamaMode.managed => managedHost,
        OllamaMode.none => null,
      };

  String get _installDir => '${AppPaths.runtimeDir}/ollama-$version';
  String get _binary => '$_installDir/ollama';
  String get _logPath => '${AppPaths.home}/Library/Logs/UltraWhisper/ollama.log';

  bool get runtimeInstalled => File(_binary).existsSync();

  /// Work out which Ollama to use, starting the private one if that is it.
  Future<OllamaMode> refresh() async {
    if (await _responds(externalHost)) {
      _mode = OllamaMode.external;
    } else if (runtimeInstalled) {
      await (_starting ??= _startManaged().whenComplete(() => _starting = null));
      _mode = await _responds(managedHost) ? OllamaMode.managed : OllamaMode.none;
    } else {
      _mode = OllamaMode.none;
    }
    return _mode;
  }

  Future<bool> _responds(String base) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 700);
    try {
      final request = await client.getUrl(Uri.parse('$base/api/version'));
      final response = await request.close().timeout(const Duration(seconds: 2));
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _startManaged() async {
    // An earlier run's copy can still be up if its watchdog never got the
    // chance to notice; it serves the same models, so adopt it.
    if (await _responds(managedHost)) return;

    await File(_logPath).parent.create(recursive: true);
    await Directory(AppPaths.ollamaModelsDir).create(recursive: true);

    // The shell is a watchdog. `ollama serve` does not exit with its parent,
    // and a force-quit or a crash skips every Dart cleanup path — the same
    // reason the Python backend takes --parent-pid. A 5 s poll costs nothing
    // measurable at idle.
    //
    // `sleep & wait`, not a bare `sleep`: sh runs a trap only once the
    // foreground command returns, so a TERM arriving mid-sleep waited up to
    // 5 s — long enough for [stop] to fall back to SIGKILL, which no trap
    // survives, and `ollama serve` was orphaned. `wait` is interrupted by the
    // signal, so the trap runs at once.
    const script = r'''
"$1" serve >"$3" 2>&1 &
child=$!
trap 'kill $child 2>/dev/null; exit 0' TERM INT
while kill -0 "$2" 2>/dev/null && kill -0 $child 2>/dev/null; do
  sleep 5 & wait $!
done
kill $child 2>/dev/null
''';

    AppLogger.info('Starting the private Ollama on port $managedPort');
    _process = await Process.start(
      '/bin/sh',
      ['-c', script, 'ollama-watchdog', _binary, '$pid', _logPath],
      // A clean environment, never the app's: Ollama ships libggml*.dylib under
      // the same names as whisper.cpp, and a DYLD_LIBRARY_PATH pointing at
      // whisper's copies would make it load the wrong ones (see CLAUDE.md).
      includeParentEnvironment: false,
      environment: {
        'HOME': AppPaths.home,
        'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
        'OLLAMA_HOST': '127.0.0.1:$managedPort',
        'OLLAMA_MODELS': AppPaths.ollamaModelsDir,
      },
    );
    unawaited(_process!.stdout.drain<void>());
    unawaited(_process!.stderr.drain<void>());

    // Metal discovery makes the first start take ~5 s.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      if (await _responds(managedHost)) return;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    AppLogger.warning('The private Ollama did not answer within 20 s; see $_logPath');
  }

  /// Download, verify and unpack the pinned Ollama release, then start it.
  Future<void> installRuntime({
    void Function(int received, int total)? onProgress,
    void Function()? onVerifying,
    DownloadCancel? cancel,
  }) async {
    final archive = '${AppPaths.runtimeDir}/ollama-darwin-$version.tgz';
    await FileDownloader.download(
      url: archiveUrl,
      destination: archive,
      sha256: archiveSha256,
      expectedBytes: archiveBytes,
      onProgress: onProgress,
      onVerifying: onVerifying,
      cancel: cancel,
    );

    // Unpack beside the final location and rename, so a half-extracted runtime
    // is never mistaken for an installed one.
    final staging = Directory('$_installDir.partial');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    final tar = await Process.run('/usr/bin/tar', ['-xzf', archive, '-C', staging.path]);
    if (tar.exitCode != 0) {
      throw Exception('Could not unpack Ollama: ${tar.stderr}');
    }
    if (!await File('${staging.path}/ollama').exists()) {
      throw Exception('The Ollama archive did not contain an ollama binary');
    }
    final installed = Directory(_installDir);
    if (await installed.exists()) await installed.delete(recursive: true);
    await staging.rename(_installDir);
    await File(archive).delete();
    await _removeOtherVersions();

    await refresh();
  }

  /// Older pinned versions left behind by an app update.
  Future<void> _removeOtherVersions() async {
    final dir = Directory(AppPaths.runtimeDir);
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      final name = entry.path.split('/').last;
      if (entry is Directory && name.startsWith('ollama-') && entry.path != _installDir) {
        await entry.delete(recursive: true);
      }
    }
  }

  /// Tags the current Ollama has pulled, or empty when there is none.
  Future<Set<String>> listModels() async {
    final base = host;
    if (base == null) return {};
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$base/api/tags'));
      final response = await request.close().timeout(const Duration(seconds: 3));
      final body = await response.transform(utf8.decoder).join();
      final models = (jsonDecode(body) as Map<String, dynamic>)['models'] as List? ?? [];
      return {
        for (final model in models)
          if (model is Map && model['name'] is String) model['name'] as String,
      };
    } catch (e) {
      AppLogger.warning('Could not list Ollama models: $e');
      return {};
    } finally {
      client.close(force: true);
    }
  }

  /// Whether [tag] is among [installed], treating a bare name as `:latest`.
  static bool hasModel(Set<String> installed, String tag) {
    final wanted = tag.contains(':') ? tag : '$tag:latest';
    return installed.contains(tag) || installed.contains(wanted);
  }

  /// `ollama pull`, with progress. Ollama keeps finished layers, so pulling
  /// again after a cancel picks up where it stopped.
  Future<void> pull(
    String tag, {
    void Function(PullProgress progress)? onProgress,
    DownloadCancel? cancel,
  }) async {
    final base = host;
    if (base == null) throw Exception('Ollama is not available');
    final client = HttpClient();
    cancel?.attach(client);
    try {
      final request = await client.postUrl(Uri.parse('$base/api/pull'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'model': tag, 'stream': true}));
      final response = await request.close();
      final progress = PullProgress();
      await for (final line in response
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        progress.apply(jsonDecode(line) as Map<String, dynamic>);
        onProgress?.call(progress);
      }
      if (cancel?.isCancelled ?? false) throw DownloadCancelledException();
      if (!progress.isDone) throw Exception('Pull of $tag ended early');
    } catch (e) {
      if (cancel?.isCancelled ?? false) throw DownloadCancelledException();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> deleteModel(String tag) async {
    final base = host;
    if (base == null) return;
    final client = HttpClient();
    try {
      final request = await client.openUrl('DELETE', Uri.parse('$base/api/delete'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'model': tag}));
      final response = await request.close();
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
  }

  /// Stop the private Ollama. The user's own is never touched.
  Future<void> stop() async {
    final process = _process;
    _process = null;
    if (process == null) return;
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    }
  }
}
