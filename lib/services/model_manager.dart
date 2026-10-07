import 'dart:async';
import 'dart:io';

import '../models/model_catalog.dart';
import '../utils/app_paths.dart';
import '../utils/logger.dart';
import 'file_downloader.dart';
import 'ollama_service.dart';

/// One download or pull in flight, as the windows show it.
class ModelTask {
  ModelTask(this.label);

  final String label;
  String state = 'downloading'; // downloading | verifying | installing | done | failed | cancelled
  int received = 0;
  int total = 0;
  String? error;

  bool get isActive => state == 'downloading' || state == 'verifying' || state == 'installing';

  Map<String, dynamic> toJson() => {
        'label': label,
        'state': state,
        'received': received,
        'total': total,
        'error': error,
      };
}

/// Everything the app downloads: whisper models, the private Ollama, and the
/// Ollama models behind the AI features.
///
/// Lives in the main engine on purpose. The setup and settings windows are
/// separate engines that come and go; a 1.6 GB download must survive the
/// window that started it being closed. The windows ask for [statusJson] and
/// send actions; nothing here pushes to them.
class ModelManager {
  ModelManager({required this.ollama, this.fallbackModelDirs = _noDirs});

  final OllamaService ollama;

  /// Other places a model may already sit — the source checkout in a debug
  /// build, or the bundle of an older release that still shipped one.
  final Future<List<String>> Function() fallbackModelDirs;

  static Future<List<String>> _noDirs() async => const [];

  final Map<String, ModelTask> _tasks = {};
  final Map<String, DownloadCancel> _cancels = {};
  Set<String> _ollamaModels = {};

  /// Called whenever a task finishes, so the app can react — start the
  /// backend once the first speech model lands, for one.
  void Function(String taskId)? onTaskFinished;

  static String speechTaskId(String id) => 'speech:$id';
  static String pullTaskId(String tag) => 'pull:$tag';
  static const runtimeTaskId = 'runtime';

  bool get hasActiveTasks => _tasks.values.any((task) => task.isActive);

  // ---------------------------------------------------------------------------
  // Speech models
  // ---------------------------------------------------------------------------

  String downloadedPath(SpeechModel model) => '${AppPaths.modelsDir}/${model.fileName}';

  /// The file to load for [id], or null when it is not on this Mac.
  Future<String?> resolveSpeechModel(String id) async {
    final model = speechModelById(id);
    if (model == null) return null;
    final candidates = [
      downloadedPath(model),
      for (final dir in await fallbackModelDirs()) '$dir/${model.fileName}',
    ];
    for (final candidate in candidates) {
      final file = File(candidate);
      // Size, not checksum: hashing 1.6 GB on every launch is not worth it, and
      // a downloaded file was already verified before it was renamed in.
      if (await file.exists() && await file.length() == model.bytes) return candidate;
    }
    return null;
  }

  Future<void> downloadSpeechModel(String id) async {
    final model = speechModelById(id);
    if (model == null) throw ArgumentError('Unknown speech model $id');
    final taskId = speechTaskId(id);
    if (_tasks[taskId]?.isActive ?? false) return;

    final task = ModelTask(model.label)..total = model.bytes;
    final cancel = DownloadCancel();
    _tasks[taskId] = task;
    _cancels[taskId] = cancel;

    try {
      await FileDownloader.download(
        url: Uri.parse(model.url),
        destination: downloadedPath(model),
        sha256: model.sha256,
        expectedBytes: model.bytes,
        onProgress: (received, total) => task
          ..received = received
          ..total = total,
        onVerifying: () => task.state = 'verifying',
        cancel: cancel,
      );
      task
        ..state = 'done'
        ..received = task.total;
      AppLogger.success('Downloaded ${model.fileName}');
    } on DownloadCancelledException {
      task.state = 'cancelled';
    } catch (e) {
      task
        ..state = 'failed'
        ..error = _describe(e);
      AppLogger.error('Download of ${model.fileName} failed', e);
    } finally {
      _cancels.remove(taskId);
      onTaskFinished?.call(taskId);
    }
  }

  /// Remove a downloaded model. Copies outside Application Support are not
  /// ours to delete.
  Future<void> deleteSpeechModel(String id) async {
    final model = speechModelById(id);
    if (model == null) return;
    for (final path in [downloadedPath(model), '${downloadedPath(model)}.part']) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    _tasks.remove(speechTaskId(id));
  }

  // ---------------------------------------------------------------------------
  // Ollama
  // ---------------------------------------------------------------------------

  Future<void> refreshOllama() async {
    await ollama.refresh();
    _ollamaModels = await ollama.listModels();
  }

  Future<void> installOllamaRuntime() async {
    if (_tasks[runtimeTaskId]?.isActive ?? false) return;
    final task = ModelTask('Ollama ${OllamaService.version}')..total = OllamaService.archiveBytes;
    final cancel = DownloadCancel();
    _tasks[runtimeTaskId] = task;
    _cancels[runtimeTaskId] = cancel;

    try {
      await ollama.installRuntime(
        onProgress: (received, total) => task
          ..received = received
          ..total = total,
        onVerifying: () => task.state = 'installing',
        cancel: cancel,
      );
      _ollamaModels = await ollama.listModels();
      task
        ..state = ollama.mode == OllamaMode.none ? 'failed' : 'done'
        ..error = ollama.mode == OllamaMode.none ? 'Installed, but it did not start' : null;
    } on DownloadCancelledException {
      task.state = 'cancelled';
    } catch (e) {
      task
        ..state = 'failed'
        ..error = _describe(e);
      AppLogger.error('Installing Ollama failed', e);
    } finally {
      _cancels.remove(runtimeTaskId);
      onTaskFinished?.call(runtimeTaskId);
    }
  }

  Future<void> pullOllamaModel(String tag, {String? label}) async {
    final taskId = pullTaskId(tag);
    if (_tasks[taskId]?.isActive ?? false) return;
    final task = ModelTask(label ?? tag);
    final cancel = DownloadCancel();
    _tasks[taskId] = task;
    _cancels[taskId] = cancel;

    try {
      if (ollama.host == null) await refreshOllama();
      await ollama.pull(
        tag,
        onProgress: (progress) {
          task
            ..received = progress.completed
            ..total = progress.total;
          if (progress.status.startsWith('verifying') || progress.status.startsWith('writing')) {
            task.state = 'verifying';
          }
        },
        cancel: cancel,
      );
      _ollamaModels = await ollama.listModels();
      task.state = 'done';
    } on DownloadCancelledException {
      task.state = 'cancelled';
    } catch (e) {
      task
        ..state = 'failed'
        ..error = _describe(e);
      AppLogger.error('Pulling $tag failed', e);
    } finally {
      _cancels.remove(taskId);
      onTaskFinished?.call(taskId);
    }
  }

  Future<void> deleteOllamaModel(String tag) async {
    await ollama.deleteModel(tag);
    _ollamaModels = await ollama.listModels();
    _tasks.remove(pullTaskId(tag));
  }

  // ---------------------------------------------------------------------------

  void cancel(String taskId) => _cancels[taskId]?.cancel();

  /// What the setup and settings windows render. Plain JSON types only — it
  /// crosses a platform channel.
  Future<Map<String, dynamic>> statusJson() async {
    return {
      'speech': {
        for (final model in kSpeechModels)
          model.id: {
            'installed': await resolveSpeechModel(model.id) != null,
            'deletable': await File(downloadedPath(model)).exists(),
          },
      },
      'tasks': {for (final entry in _tasks.entries) entry.key: entry.value.toJson()},
      'ollama': {
        'mode': ollama.mode.name,
        'runtimeInstalled': ollama.runtimeInstalled,
        'runtimeBytes': OllamaService.archiveBytes,
        'models': _ollamaModels.toList(),
      },
      'freeDiskBytes': await freeDiskBytes(),
    };
  }

  /// Free space on the volume holding Application Support.
  static Future<int?> freeDiskBytes() async {
    try {
      final result = await Process.run('/bin/df', ['-k', AppPaths.home]);
      final lines = (result.stdout as String).trim().split('\n');
      final fields = lines.last.split(RegExp(r'\s+'));
      return int.parse(fields[3]) * 1024;
    } catch (_) {
      return null;
    }
  }

  static String _describe(Object error) {
    if (error is SocketException) return 'No internet connection';
    if (error is HttpException) return error.message;
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }
}
