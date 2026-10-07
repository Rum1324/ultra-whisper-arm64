import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import '../models/model_catalog.dart';
import '../models/notes_model_presets.dart';
import '../models/settings.dart';
import '../services/hardware_probe.dart';
import '../theme/focus_theme.dart';
import '../widgets/focus_controls.dart';
import '../widgets/hotkey_recorder.dart';
import '../widgets/model_widgets.dart';

/// First-run setup: what the app does, permissions, shortcuts, and which
/// models this Mac should download.
///
/// Like Settings this is its own Flutter engine with no plugins, so anything
/// native — permissions, downloads, saving — goes through the main window.
/// Downloads run there too, so they keep going if this window closes.
void setupWindowMain() {
  runApp(const SetupWindowApp());
}

class SetupWindowApp extends StatelessWidget {
  const SetupWindowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Welcome to UltraWhisper',
      debugShowCheckedModeBanner: false,
      theme: focusTheme(Brightness.light),
      darkTheme: focusTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const Scaffold(body: SetupFlow()),
    );
  }
}

enum _Page { welcome, permissions, shortcuts, models, download }

class SetupFlow extends StatefulWidget {
  const SetupFlow({super.key});

  @override
  State<SetupFlow> createState() => _SetupFlowState();
}

class _SetupFlowState extends State<SetupFlow> {
  _Page _page = _Page.welcome;
  Settings _settings = const Settings();

  HardwareInfo? _hardware;
  SetupRecommendation? _recommendation;

  // What will be downloaded. Seeded from the recommendation.
  String _speechModelId = kDefaultSpeechModelId;
  bool _aiFormatting = false;
  String? _notesTag;

  Map<String, dynamic> _permissions = const {};
  Timer? _permissionTimer;

  final ModelsClient _models = ModelsClient();

  /// Downloads this page has already asked for, so a failed one waits for the
  /// user's retry instead of being restarted every second.
  final Set<String> _requested = {};

  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _models
      ..addListener(_onModelsChanged)
      ..start();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await DesktopMultiWindow.invokeMethod(0, 'get_settings');
      if (raw is Map) _settings = Settings.fromJson(Map<String, dynamic>.from(raw));
    } catch (e) {
      debugPrint('Setup could not load settings: $e');
    }
    final hardware = await HardwareInfo.probe();
    if (!mounted) return;
    setState(() {
      _hardware = hardware;
      _applyRecommendation(recommendSetup(hardware));
    });
  }

  void _applyRecommendation(SetupRecommendation recommendation) {
    _recommendation = recommendation;
    _speechModelId = speechModelById(recommendation.speechModelId) != null
        ? recommendation.speechModelId
        : kDefaultSpeechModelId;
    _aiFormatting = recommendation.aiFormatting && _formattingAllowed;
    _notesTag = _notesAllowed ? recommendation.notesModelTag : null;
  }

  bool get _formattingAllowed => (_hardware?.memoryGb ?? 0) >= kMinMemoryGbForFormatting;
  bool get _notesAllowed => (_hardware?.memoryGb ?? 0) >= kMinMemoryGbForNotes;
  bool get _wantsOllama => _aiFormatting || _notesTag != null;

  void _onModelsChanged() {
    if (!mounted) return;
    if (_page == _Page.download) _driveDownloads();
    setState(() {});
  }

  @override
  void dispose() {
    _permissionTimer?.cancel();
    _models
      ..removeListener(_onModelsChanged)
      ..dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _go(_Page page) {
    setState(() => _page = page);
    _permissionTimer?.cancel();
    if (page == _Page.permissions) {
      // Permissions change in System Settings, outside this window, so the
      // page watches for them while it is showing — and only then.
      _refreshPermissions();
      _permissionTimer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _refreshPermissions(),
      );
    }
    if (page == _Page.download) {
      _models.refresh(ollama: true).then((_) => _driveDownloads());
    }
  }

  Future<void> _refreshPermissions() async {
    try {
      final raw = await DesktopMultiWindow.invokeMethod(0, 'permissions_status');
      if (raw is Map && mounted) {
        setState(() => _permissions = Map<String, dynamic>.from(raw));
      }
    } catch (e) {
      debugPrint('permissions_status failed: $e');
    }
  }

  /// Start whatever the choices need and is not on disk yet. Called on every
  /// status update while the download page shows; the Ollama models wait for
  /// an Ollama to pull them into.
  void _driveDownloads() {
    final status = _models.status;
    if (status == null) return;

    void once(String key, Future<void> Function() start) {
      if (_requested.add(key)) unawaited(start());
    }

    if (!status.speechInstalled(_speechModelId)) {
      once('speech:$_speechModelId', () => _models.downloadSpeech(_speechModelId));
    }
    if (!_wantsOllama) return;
    if (!status.ollamaAvailable) {
      once('runtime', _models.installOllama);
      return;
    }
    for (final model in _chosenOllamaModels) {
      if (!status.ollamaHas(model.tag)) {
        once('pull:${model.tag}', () => _models.pull(model));
      }
    }
  }

  List<OllamaModelChoice> get _chosenOllamaModels => [
        if (_aiFormatting) kFormattingModel,
        for (final notes in kNotesModelChoices)
          if (notes.tag == _notesTag) notes,
      ];

  Future<void> _finish() async {
    setState(() => _finishing = true);
    final chosen = _settings.copyWith(
      speechModelId: _speechModelId,
      aiFormatting: _aiFormatting,
      meetingSummaryModel: _notesTag ?? _settings.meetingSummaryModel,
    );
    try {
      await DesktopMultiWindow.invokeMethod(0, 'finish_setup', chosen.toJson());
    } catch (e) {
      debugPrint('finish_setup failed: $e');
      if (mounted) setState(() => _finishing = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = FocusColors.of(context);
    final index = _Page.values.indexOf(_page);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 8),
          child: Row(
            children: [
              for (var i = 0; i < _Page.values.length; i++)
                Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i <= index ? c.accent : c.line,
                      borderRadius: const BorderRadius.all(FocusRadius.pill),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: switch (_page) {
                    _Page.welcome => _welcome(),
                    _Page.permissions => _permissionsPage(),
                    _Page.shortcuts => _shortcuts(),
                    _Page.models => _modelsPage(),
                    _Page.download => _downloadPage(),
                  },
                ),
              ),
            ),
          ),
        ),
        Divider(color: c.line, height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
          child: Row(
            children: [
              if (index > 0)
                TextButton(
                  onPressed: () => _go(_Page.values[index - 1]),
                  child: const Text('Back'),
                ),
              const Spacer(),
              if (_page == _Page.download)
                FilledButton(
                  onPressed: _canFinish && !_finishing ? _finish : null,
                  child: Text(_finishing ? 'Starting…' : 'Start using UltraWhisper'),
                )
              else
                FilledButton(
                  onPressed: _page == _Page.models && _hardware == null
                      ? null
                      : () => _go(_Page.values[index + 1]),
                  child: Text(_page == _Page.models ? 'Download' : 'Continue'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  bool get _canFinish => _models.status?.speechInstalled(_speechModelId) ?? false;

  Widget _title(String text, [String? lead]) {
    final c = FocusColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: FocusText.title.copyWith(fontSize: 22, color: c.ink)),
          if (lead != null) ...[
            const SizedBox(height: 6),
            Text(lead, style: FocusText.body.copyWith(fontSize: 14.4, color: c.ink2)),
          ],
        ],
      ),
    );
  }

  static const _gap = SizedBox(height: 20);

  // ---------------------------------------------------------------------------
  // Pages
  // ---------------------------------------------------------------------------

  List<Widget> _welcome() {
    final record = _settings.toggleRecordHotkey;
    final enter = _settings.toggleRecordEnterHotkey;
    return [
      _title(
        'Welcome to UltraWhisper',
        'Speak instead of typing, in any app. Everything runs on this Mac — '
            'no audio or text ever leaves it.',
      ),
      FocusGroup(
        children: [
          FocusRow(
            title: 'Press $record to start, press it again to stop',
            subtitle: 'What you said is typed into whatever app you are in, '
                'and stays on the clipboard in case you need it again.',
            trailing: const Icon(Icons.keyboard_voice_outlined, size: 20),
          ),
          FocusRow(
            title: 'Press $enter to dictate and send',
            subtitle: 'The same, then presses Return — for chats and AI prompts.',
            trailing: const Icon(Icons.send_outlined, size: 20),
          ),
          const FocusRow(
            title: 'English and Japanese, detected automatically',
            subtitle: 'No language to pick. Japanese gets 、。 punctuation.',
            trailing: Icon(Icons.translate, size: 20),
          ),
          const FocusRow(
            title: 'Meetings, recorded both ways',
            subtitle: 'When a call starts, UltraWhisper offers to transcribe '
                'your side and theirs. macOS asks for System Audio Recording '
                'the first time.',
            trailing: Icon(Icons.groups_outlined, size: 20),
          ),
          const FocusRow(
            title: 'Optional local AI',
            subtitle: 'Tidier dictation and meeting notes from a model on this '
                'Mac. You decide on the next pages whether it is worth the '
                'download.',
            trailing: Icon(Icons.auto_awesome_outlined, size: 20),
          ),
        ],
      ),
      _gap,
      const FocusCaption('Setup takes about two minutes, plus the download.'),
    ];
  }

  List<Widget> _permissionsPage() {
    final c = FocusColors.of(context);
    final microphone = _permissions['microphone'] as String?;
    final accessibility = _permissions['accessibility'] == true;

    Widget granted() => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 16, color: c.ok),
            const SizedBox(width: 4),
            Text('Allowed', style: FocusText.detail.copyWith(color: c.ink2)),
          ],
        );

    return [
      _title(
        'Two permissions',
        'macOS asks for these once. You can change them later in System '
            'Settings → Privacy & Security.',
      ),
      FocusGroup(
        children: [
          FocusRow(
            title: 'Microphone',
            subtitle: microphone == 'denied'
                ? 'Turned off. Open System Settings, find UltraWhisper under '
                    'Microphone, and switch it on.'
                : 'To hear what you dictate. Audio is transcribed on this Mac '
                    'and then discarded.',
            trailing: switch (microphone) {
              'granted' => granted(),
              'denied' => OutlinedButton(
                  onPressed: () => _openPrivacyPane('Privacy_Microphone'),
                  child: const Text('Open System Settings'),
                ),
              null => const SizedBox.shrink(),
              _ => FilledButton(
                  onPressed: () async {
                    await DesktopMultiWindow.invokeMethod(0, 'request_microphone');
                    _refreshPermissions();
                  },
                  child: const Text('Allow'),
                ),
            },
          ),
          FocusRow(
            title: 'Accessibility',
            subtitle: accessibility
                ? 'Lets UltraWhisper type the transcript into the app you are in.'
                : 'Lets UltraWhisper type the transcript into the app you are '
                    'in. Click Allow, then switch UltraWhisper on in the list '
                    'that opens. Without it, text is only copied.',
            trailing: accessibility
                ? granted()
                : FilledButton(
                    onPressed: () async {
                      await DesktopMultiWindow.invokeMethod(0, 'request_accessibility');
                      _openPrivacyPane('Privacy_Accessibility');
                    },
                    child: const Text('Allow'),
                  ),
          ),
        ],
      ),
      _gap,
      const FocusCaption(
        'You can continue without them and grant them later; dictation just '
        'will not work until the microphone is allowed.',
      ),
    ];
  }

  /// Opens System Settings at a Privacy & Security pane. `open` works from any
  /// engine, so this needs no round trip through the main window.
  void _openPrivacyPane(String anchor) {
    Process.run('/usr/bin/open', [
      'x-apple.systempreferences:com.apple.preference.security?$anchor',
    ]);
  }

  List<Widget> _shortcuts() {
    return [
      _title(
        'Your shortcuts',
        'Click a shortcut, press the keys you want, then press Return. Pick '
            'something no other app uses.',
      ),
      FocusGroup(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: HotkeyRecorder(
              label: 'Start and stop dictation',
              initialValue: _settings.toggleRecordHotkey,
              onChanged: (value) => setState(
                () => _settings = _settings.copyWith(toggleRecordHotkey: value),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: HotkeyRecorder(
              label: 'Dictate, then press Return',
              initialValue: _settings.toggleRecordEnterHotkey,
              onChanged: (value) => setState(
                () => _settings = _settings.copyWith(toggleRecordEnterHotkey: value),
              ),
            ),
          ),
        ],
      ),
      _gap,
      const FocusCaption(
        'The stop key decides: start with either one, and stopping with the '
        'second also presses Return.',
      ),
    ];
  }

  List<Widget> _modelsPage() {
    final c = FocusColors.of(context);
    final hardware = _hardware;
    final recommendation = _recommendation;
    final status = _models.status;

    if (hardware == null || recommendation == null) {
      return [
        _title('Looking at your Mac…'),
        const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ];
    }

    final download = _plannedDownloadBytes(status);
    final free = hardware.freeDiskBytes ?? status?.freeDiskBytes;
    final tight = free != null && download > free - 5e9;

    return [
      _title('Models for this Mac', hardware.summary),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.accentTint,
          borderRadius: const BorderRadius.all(FocusRadius.r16),
        ),
        child: Row(
          children: [
            Icon(Icons.recommend_outlined, color: c.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                recommendation.reason,
                style: FocusText.body.copyWith(fontSize: 14.4, color: c.ink),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _applyRecommendation(recommendation)),
              child: const Text('Use recommended'),
            ),
          ],
        ),
      ),
      _gap,
      const FocusLabel('Speech model'),
      const FocusCaption(
        'Turns your voice into text. Bigger is more accurate and uses more '
        'memory. You can switch in Settings at any time.',
      ),
      FocusGroup(
        children: [
          for (final model in kSpeechModels)
            SpeechModelTile(
              model: model,
              status: status,
              client: _models,
              selected: _speechModelId == model.id,
              recommended: model.id == recommendation.speechModelId,
              allowDelete: false,
              onSelect: (id) => setState(() => _speechModelId = id),
            ),
        ],
      ),
      _gap,
      const FocusLabel('Local AI (optional)'),
      FocusCaption(
        status?.ollamaMode == 'external'
            ? 'Uses the Ollama already on this Mac.'
            : 'UltraWhisper downloads its own copy of Ollama '
                '(${formatBytes(status?.runtimeBytes ?? 0)}) the first time '
                'you turn one of these on.',
      ),
      FocusGroup(
        children: [
          _aiSwitch(
            title: 'AI formatting',
            subtitle: _formattingAllowed
                ? '${kFormattingModel.note} ${formatGb(kFormattingModel.downloadGb)} download.'
                : 'Needs at least $kMinMemoryGbForFormatting GB of memory; this '
                    'Mac has ${hardware.memoryGb} GB.',
            value: _aiFormatting,
            onChanged: _formattingAllowed ? (v) => setState(() => _aiFormatting = v) : null,
          ),
          _aiSwitch(
            title: 'Meeting notes',
            subtitle: _notesAllowed
                ? 'A summary with decisions and action items after each '
                    'meeting. The model is large and works hard while it writes.'
                : 'Needs at least $kMinMemoryGbForNotes GB of memory; this Mac '
                    'has ${hardware.memoryGb} GB. Meetings are still transcribed.',
            value: _notesTag != null,
            onChanged: _notesAllowed
                ? (v) => setState(() => _notesTag = v ? kNotesModelPresets.last.tag : null)
                : null,
          ),
          if (_notesTag != null)
            for (final preset in kNotesModelPresets)
              RadioListTile<String>(
                value: preset.tag,
                groupValue: _notesTag,
                onChanged: (tag) => setState(() => _notesTag = tag),
                dense: true,
                title: Text(
                  '${preset.label}  ·  ${formatGb(preset.approxGigabytes)}',
                  style: FocusText.body.copyWith(fontSize: 14, color: c.ink),
                ),
                subtitle: Text(
                  preset.note,
                  style: FocusText.caption.copyWith(fontSize: 12.5, color: c.ink2),
                ),
              ),
        ],
      ),
      _gap,
      Text(
        download == 0
            ? 'Everything you picked is already downloaded.'
            : 'About ${formatBytes(download)} to download'
                '${free == null ? '' : ' · ${formatBytes(free)} free on this Mac'}.',
        style: FocusText.detail.copyWith(color: tight ? c.bad : c.ink2),
      ),
    ];
  }

  Widget _aiSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return FocusRow(
      title: title,
      subtitle: subtitle,
      onTap: onChanged == null ? null : () => onChanged(!value),
      trailing: FocusSwitch(value: value, onChanged: onChanged),
    );
  }

  int _plannedDownloadBytes(ModelsStatus? status) {
    var bytes = 0;
    final speech = speechModelById(_speechModelId);
    if (speech != null && !(status?.speechInstalled(speech.id) ?? false)) {
      bytes += speech.bytes;
    }
    if (_wantsOllama && !(status?.ollamaAvailable ?? false)) {
      bytes += status?.runtimeBytes ?? 0;
    }
    for (final model in _chosenOllamaModels) {
      if (!(status?.ollamaHas(model.tag) ?? false)) {
        bytes += (model.downloadGb * 1e9).round();
      }
    }
    return bytes;
  }

  List<Widget> _downloadPage() {
    final status = _models.status;
    final speech = speechModelById(_speechModelId)!;
    final speechReady = status?.speechInstalled(speech.id) ?? false;

    return [
      _title(
        speechReady ? 'Ready when you are' : 'Downloading',
        speechReady
            ? 'The speech model is in place. Anything still downloading below '
                'carries on in the background after you start.'
            : 'You can start as soon as the speech model is done. Closing this '
                'window does not stop the download.',
      ),
      FocusGroup(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Speech model · ${speech.label}',
                    style: FocusText.body.copyWith(fontSize: 14.4),
                  ),
                ),
                DownloadControl(
                  installed: speechReady,
                  task: status?.speechTask(speech.id),
                  sizeLabel: formatBytes(speech.bytes),
                  onDownload: () => _models.downloadSpeech(speech.id),
                  onCancel: () => _models.cancel('speech:${speech.id}'),
                ),
              ],
            ),
          ),
          if (_wantsOllama) OllamaRuntimeRow(status: status, client: _models),
          if (_aiFormatting)
            OllamaModelRow(
              model: kFormattingModel,
              title: 'AI formatting',
              status: status,
              client: _models,
              allowDelete: false,
            ),
          for (final notes in kNotesModelChoices)
            if (notes.tag == _notesTag)
              OllamaModelRow(
                model: notes,
                title: 'Meeting notes',
                status: status,
                client: _models,
                allowDelete: false,
              ),
        ],
      ),
    ];
  }
}
