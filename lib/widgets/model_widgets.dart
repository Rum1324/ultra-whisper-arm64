import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import '../models/model_catalog.dart';
import '../theme/focus_theme.dart';

/// `1.6 GB`, `412 MB`.
String formatBytes(num bytes) {
  if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
  if (bytes >= 1e6) return '${(bytes / 1e6).round()} MB';
  return '${(bytes / 1e3).round()} KB';
}

String formatGb(double gb) => '${gb.toStringAsFixed(gb < 10 ? 1 : 0)} GB';

/// One download or pull, as reported by the main engine's ModelManager.
class TaskView {
  TaskView(Map raw)
      : state = raw['state'] as String? ?? 'downloading',
        received = (raw['received'] as num?)?.toInt() ?? 0,
        total = (raw['total'] as num?)?.toInt() ?? 0,
        error = raw['error'] as String?;

  final String state;
  final int received;
  final int total;
  final String? error;

  bool get isActive => state == 'downloading' || state == 'verifying' || state == 'installing';
  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
}

/// A snapshot of `models_status`.
class ModelsStatus {
  ModelsStatus(this._raw);

  final Map _raw;

  Map get _speech => _raw['speech'] as Map? ?? const {};
  Map get _tasks => _raw['tasks'] as Map? ?? const {};
  Map get _ollama => _raw['ollama'] as Map? ?? const {};

  bool speechInstalled(String id) => (_speech[id] as Map?)?['installed'] == true;
  bool speechDeletable(String id) => (_speech[id] as Map?)?['deletable'] == true;

  TaskView? task(String taskId) {
    final raw = _tasks[taskId];
    return raw is Map ? TaskView(raw) : null;
  }

  TaskView? speechTask(String id) => task('speech:$id');
  TaskView? pullTask(String tag) => task('pull:$tag');
  TaskView? get runtimeTask => task('runtime');

  bool get anyActive => _tasks.values.whereType<Map>().any((raw) => TaskView(raw).isActive);

  /// `none`, `external` (the user's own Ollama) or `managed` (ours).
  String get ollamaMode => _ollama['mode'] as String? ?? 'none';
  bool get ollamaAvailable => ollamaMode != 'none';
  bool get runtimeInstalled => _ollama['runtimeInstalled'] == true;
  int get runtimeBytes => (_ollama['runtimeBytes'] as num?)?.toInt() ?? 0;

  bool ollamaHas(String tag) {
    final models = (_ollama['models'] as List? ?? const []).cast<Object?>();
    final latest = tag.contains(':') ? tag : '$tag:latest';
    return models.contains(tag) || models.contains(latest);
  }

  int? get freeDiskBytes => (_raw['freeDiskBytes'] as num?)?.toInt();
}

/// The setup and settings windows' view of the downloads running in the main
/// engine. Polls once a second, which only costs anything while one of those
/// windows is open.
class ModelsClient extends ChangeNotifier {
  ModelsStatus? status;
  Timer? _timer;

  void start() {
    unawaited(refresh(ollama: true));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (status?.anyActive ?? false) refresh();
    });
  }

  Future<void> refresh({bool ollama = false}) async {
    try {
      final raw = await DesktopMultiWindow.invokeMethod(
        0,
        'models_status',
        {'refreshOllama': ollama},
      );
      if (raw is Map) {
        status = ModelsStatus(raw);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('models_status failed: $e');
    }
  }

  Future<void> _send(String method, [Object? arguments]) async {
    await DesktopMultiWindow.invokeMethod(0, method, arguments);
    // The action has started in the main engine; show it straight away.
    await refresh();
  }

  Future<void> downloadSpeech(String id) => _send('download_speech_model', id);
  Future<void> cancel(String taskId) => _send('cancel_task', taskId);
  Future<void> installOllama() => _send('install_ollama');
  Future<void> pull(OllamaModelChoice model) =>
      _send('pull_ollama_model', {'tag': model.tag, 'label': model.label});
  Future<void> deleteOllama(String tag) => _send('delete_ollama_model', tag);

  /// False when [id] is the model in use, which is never deleted from under
  /// the backend.
  Future<bool> deleteSpeech(String id) async {
    final deleted = await DesktopMultiWindow.invokeMethod(0, 'delete_speech_model', id);
    await refresh();
    return deleted == true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// `●●●●○` for a 1–5 rating.
class RatingDots extends StatelessWidget {
  const RatingDots({super.key, required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final c = FocusColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: FocusText.caption.copyWith(fontSize: 12, color: c.ink2)),
        const SizedBox(width: 6),
        for (var i = 1; i <= 5; i++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i <= value ? c.ink : c.line,
              ),
            ),
          ),
      ],
    );
  }
}

/// A progress bar with "412 MB of 1.6 GB" and a cancel button.
class TaskProgress extends StatelessWidget {
  const TaskProgress({super.key, required this.task, required this.onCancel});

  final TaskView task;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = FocusColors.of(context);
    final label = switch (task.state) {
      'verifying' => 'Checking the download…',
      'installing' => 'Installing…',
      _ => task.total > 0
          ? '${formatBytes(task.received)} of ${formatBytes(task.total)}'
          : 'Starting…',
    };
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.all(FocusRadius.pill),
                child: LinearProgressIndicator(
                  value: task.state == 'downloading' ? task.fraction : null,
                  minHeight: 4,
                  backgroundColor: c.fill,
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: FocusText.detail.copyWith(color: c.ink2)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (task.state == 'downloading')
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }
}

/// The trailing control for anything downloadable: a button, a progress bar,
/// or a check mark.
class DownloadControl extends StatelessWidget {
  const DownloadControl({
    super.key,
    required this.installed,
    required this.task,
    required this.sizeLabel,
    required this.onDownload,
    required this.onCancel,
    this.onDelete,
  });

  final bool installed;
  final TaskView? task;
  final String sizeLabel;
  final VoidCallback? onDownload;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = FocusColors.of(context);
    final running = task;
    if (running != null && running.isActive) {
      return SizedBox(width: 220, child: TaskProgress(task: running, onCancel: onCancel));
    }
    if (installed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 16, color: c.ok),
          const SizedBox(width: 4),
          Text('Downloaded', style: FocusText.detail.copyWith(color: c.ink2)),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              tooltip: 'Delete to free $sizeLabel',
              onPressed: onDelete,
            ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: onDownload,
          child: Text('Download $sizeLabel'),
        ),
        if (running?.state == 'failed' && running?.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              width: 220,
              child: Text(
                running!.error!,
                textAlign: TextAlign.end,
                style: FocusText.detail.copyWith(color: c.bad),
              ),
            ),
          ),
      ],
    );
  }
}

/// A whisper model with its ratings, selectable once it is on disk.
class SpeechModelTile extends StatelessWidget {
  const SpeechModelTile({
    super.key,
    required this.model,
    required this.status,
    required this.selected,
    required this.onSelect,
    required this.client,
    this.recommended = false,
    this.allowDelete = true,
  });

  final SpeechModel model;
  final ModelsStatus? status;
  final bool selected;
  final ValueChanged<String> onSelect;
  final ModelsClient client;
  final bool recommended;
  final bool allowDelete;

  @override
  Widget build(BuildContext context) {
    final c = FocusColors.of(context);
    final installed = status?.speechInstalled(model.id) ?? false;
    final deletable = allowDelete && !selected && (status?.speechDeletable(model.id) ?? false);

    return InkWell(
      onTap: () => onSelect(model.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Radio<String>(
              value: model.id,
              groupValue: selected ? model.id : null,
              onChanged: (_) => onSelect(model.id),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(model.label, style: FocusText.body.copyWith(fontSize: 14.4, color: c.ink)),
                      const SizedBox(width: 8),
                      Text(formatBytes(model.bytes), style: FocusText.detail.copyWith(color: c.ink2)),
                      if (recommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: c.accentTint,
                            borderRadius: const BorderRadius.all(FocusRadius.pill),
                          ),
                          child: Text('Recommended', style: FocusText.tag.copyWith(color: c.accent)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(model.note, style: FocusText.caption.copyWith(fontSize: 12.8, color: c.ink2)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      RatingDots(label: 'Accuracy', value: model.accuracy),
                      RatingDots(label: 'Speed', value: model.speed),
                      Text(
                        '~${formatGb(model.approxMemoryGb)} memory',
                        style: FocusText.caption.copyWith(fontSize: 12, color: c.ink2),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: DownloadControl(
                installed: installed,
                task: status?.speechTask(model.id),
                sizeLabel: formatBytes(model.bytes),
                onDownload: status == null ? null : () => client.downloadSpeech(model.id),
                onCancel: () => client.cancel('speech:${model.id}'),
                onDelete: deletable ? () => client.deleteSpeech(model.id) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the AI features' Ollama comes from, with an install button for the
/// private copy when there is none.
class OllamaRuntimeRow extends StatelessWidget {
  const OllamaRuntimeRow({super.key, required this.status, required this.client});

  final ModelsStatus? status;
  final ModelsClient client;

  @override
  Widget build(BuildContext context) {
    final c = FocusColors.of(context);
    final s = status;
    final (title, subtitle) = switch (s?.ollamaMode) {
      'external' => ('Using your Ollama', 'Models are pulled into the Ollama you already run.'),
      'managed' => (
          'Built-in Ollama',
          'Runs in the background only while UltraWhisper is open. Stored in '
              '~/Library/Application Support/UltraWhisper.'
        ),
      _ => (
          'Ollama is not installed',
          'UltraWhisper can download its own copy. It runs in the background '
              'only while UltraWhisper is open.'
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: FocusText.body.copyWith(fontSize: 14.4, color: c.ink)),
                const SizedBox(height: 2),
                Text(subtitle, style: FocusText.caption.copyWith(fontSize: 12.8, color: c.ink2)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (s != null && !s.ollamaAvailable)
            DownloadControl(
              installed: false,
              task: s.runtimeTask,
              sizeLabel: formatBytes(s.runtimeBytes),
              onDownload: client.installOllama,
              onCancel: () => client.cancel('runtime'),
            ),
        ],
      ),
    );
  }
}

/// An Ollama model behind one of the AI features, with its download state.
class OllamaModelRow extends StatelessWidget {
  const OllamaModelRow({
    super.key,
    required this.model,
    required this.title,
    required this.status,
    required this.client,
    this.allowDelete = true,
  });

  final OllamaModelChoice model;
  final String title;
  final ModelsStatus? status;
  final ModelsClient client;

  /// Off in setup: deleting 10 GB from the user's own Ollama is not a
  /// first-run decision.
  final bool allowDelete;

  @override
  Widget build(BuildContext context) {
    final c = FocusColors.of(context);
    final s = status;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: FocusText.body.copyWith(fontSize: 14.4, color: c.ink)),
                const SizedBox(height: 2),
                Text(
                  '${model.label} · ${formatGb(model.downloadGb)} download · '
                  '~${formatGb(model.memoryGb)} memory while running',
                  style: FocusText.caption.copyWith(fontSize: 12.8, color: c.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (s == null)
            const SizedBox.shrink()
          else if (!s.ollamaAvailable && !(s.pullTask(model.tag)?.isActive ?? false))
            Text('Needs Ollama', style: FocusText.detail.copyWith(color: c.ink3))
          else
            DownloadControl(
              installed: s.ollamaHas(model.tag),
              task: s.pullTask(model.tag),
              sizeLabel: formatGb(model.downloadGb),
              onDownload: () => client.pull(model),
              onCancel: () => client.cancel('pull:${model.tag}'),
              onDelete: allowDelete ? () => client.deleteOllama(model.tag) : null,
            ),
        ],
      ),
    );
  }
}
