import 'dart:io';

import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import '../models/notes_model_presets.dart';
import '../models/settings.dart';
import '../theme/focus_theme.dart';
import '../widgets/focus_controls.dart';
import '../widgets/hotkey_recorder.dart';

/// Entry point for the settings window
/// This is called when a new settings window is created
void settingsWindowMain() {
  runApp(const SettingsWindowApp());
}

class SettingsWindowApp extends StatefulWidget {
  const SettingsWindowApp({super.key});

  @override
  State<SettingsWindowApp> createState() => _SettingsWindowAppState();
}

class _SettingsWindowAppState extends State<SettingsWindowApp> {
  Settings? _settings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      // Request settings from main window instead of using platform channels
      final settingsJson = await DesktopMultiWindow.invokeMethod(0, 'get_settings');
      debugPrint('Received settings from main window: $settingsJson');
      debugPrint('Settings type: ${settingsJson.runtimeType}');

      if (settingsJson != null && settingsJson is Map) {
        // Convert from Map<Object?, Object?> to Map<String, dynamic>
        final convertedSettings = Map<String, dynamic>.from(settingsJson);
        setState(() {
          _settings = Settings.fromJson(convertedSettings);
          _isLoading = false;
        });
      } else {
        // Fallback to default settings
        debugPrint('Settings is null or not a Map, using defaults');
        setState(() {
          _settings = const Settings();
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Error loading settings: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() {
        _settings = const Settings();
        _isLoading = false;
      });
    }
  }

  void _handleSettingsSave(Settings newSettings) async {
    debugPrint('=== SAVE SETTINGS START ===');
    debugPrint('_SettingsWindowAppState: _handleSettingsSave called');
    debugPrint('_SettingsWindowAppState: newSettings = ${newSettings.toJson()}');
    try {
      debugPrint('_SettingsWindowAppState: Calling save_settings on main window...');
      final result = await DesktopMultiWindow.invokeMethod(0, 'save_settings', newSettings.toJson());
      debugPrint('_SettingsWindowAppState: save_settings returned: $result');

      debugPrint('_SettingsWindowAppState: Now calling _closeWindow...');
      await _closeWindow();
      debugPrint('_SettingsWindowAppState: _closeWindow completed');
      debugPrint('=== SAVE SETTINGS END (SUCCESS) ===');
    } catch (e, stackTrace) {
      debugPrint('=== SAVE SETTINGS ERROR ===');
      debugPrint('ERROR in _handleSettingsSave: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('=== SAVE SETTINGS END (ERROR) ===');
    }
  }

  Future<void> _closeWindow() async {
    // Notify main window that settings window is closing
    try {
      await DesktopMultiWindow.invokeMethod(0, 'settings_window_closed');
      debugPrint('Notified main window of settings closure');
    } catch (e) {
      debugPrint('Error notifying main window: $e');
    }
    // The main window will close this window via settingsWindowService
  }

  @override
  Widget build(BuildContext context) {
    // The settings window follows the system appearance; the overlay and the
    // meeting panel are the always-black island instead.
    return MaterialApp(
      title: 'Settings - UltraWhisper',
      debugShowCheckedModeBanner: false,
      theme: focusTheme(Brightness.light),
      darkTheme: focusTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : SettingsWindowContent(
                settings: _settings!,
                onSave: _handleSettingsSave,
              ),
      ),
    );
  }
}

class SettingsWindowContent extends StatefulWidget {
  final Settings settings;
  final ValueChanged<Settings> onSave;

  const SettingsWindowContent({
    super.key,
    required this.settings,
    required this.onSave,
  });

  @override
  State<SettingsWindowContent> createState() => _SettingsWindowContentState();
}

class _SettingsWindowContentState extends State<SettingsWindowContent> {
  late Settings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _handleSettingsUpdate(Settings newSettings) {
    setState(() {
      _settings = newSettings;
    });
  }

  void _handleSave() {
    debugPrint('SettingsWindowContent: Save button clicked, saving settings...');
    debugPrint('SettingsWindowContent: Current settings: ${_settings.toJson()}');
    widget.onSave(_settings);
  }

  void _handleCancel() async {
    // Notify main window that settings window is closing
    try {
      await DesktopMultiWindow.invokeMethod(0, 'settings_window_closed');
    } catch (e) {
      debugPrint('Error notifying main window: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FocusColors.of(context);
    return Column(
      children: [
        // Header, padded down past the traffic-light buttons.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 36, 12, 12),
          child: Row(
            children: [
              Text('Settings', style: FocusText.sheetTitle.copyWith(color: c.ink)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Close',
                onPressed: _handleCancel,
              ),
            ],
          ),
        ),

        // Settings content
        Expanded(
          child: SettingsWindowBody(
            settings: _settings,
            onSettingsChanged: _handleSettingsUpdate,
          ),
        ),

        Divider(color: c.line),

        // Footer buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _handleCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _handleSave,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Widget that contains the actual settings form
/// This is a simplified version of SettingsWindow for the standalone window
class SettingsWindowBody extends StatefulWidget {
  final Settings settings;
  final ValueChanged<Settings> onSettingsChanged;

  const SettingsWindowBody({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsWindowBody> createState() => _SettingsWindowBodyState();
}

class _SettingsWindowBodyState extends State<SettingsWindowBody> {
  late Settings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  @override
  void didUpdateWidget(SettingsWindowBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      setState(() {
        _settings = widget.settings;
      });
    }
  }

  void _updateSettings(Settings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    widget.onSettingsChanged(newSettings);
  }

  static const _sectionGap = SizedBox(height: 28);
  static const _groupGap = SizedBox(height: 16);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Center(
        child: ConstrainedBox(
          // Focus `measure`: one column, never wider than 640px.
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._audioSection(),
              _sectionGap,
              ..._modelSection(),
              _sectionGap,
              ..._shortcutsSection(),
              _sectionGap,
              ..._appearanceSection(),
              _sectionGap,
              ..._meetingsSection(),
              _sectionGap,
              ..._advancedSection(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _audioSection() {
    return [
      const FocusLabel('Audio'),
      FocusGroup(
        children: [
          FocusSettingRow(
            title: 'Reduce system volume while recording',
            subtitle: 'Lowers other audio so it does not bleed into the '
                'microphone. The volume comes back when recording stops.',
            value: _settings.duckVolumeDuringRecording,
            onChanged: (value) => _updateSettings(
              _settings.copyWith(duckVolumeDuringRecording: value),
            ),
          ),
          if (_settings.duckVolumeDuringRecording) ...[
            FocusSettingRow(
              title: 'Skip new Bluetooth devices by default',
              subtitle: "System audio can't bleed into the mic through "
                  'headphones. This only sets the starting value for a device '
                  'the first time it is used — the table below decides after '
                  'that.',
              value: _settings.skipDuckWhenBluetooth,
              onChanged: (value) => _updateSettings(
                _settings.copyWith(skipDuckWhenBluetooth: value),
              ),
            ),
            _buildSliderRow(
              title: 'Volume while recording',
              value: _settings.volumeDuckPercentage,
              max: 0.3,
              divisions: 30,
              onChanged: (value) => _updateSettings(
                _settings.copyWith(volumeDuckPercentage: value),
              ),
            ),
          ],
        ],
      ),
      if (_settings.duckVolumeDuringRecording) ...[
        _groupGap,
        const FocusLabel('Output devices'),
        const FocusCaption(
          'Devices are remembered as you use them. Turn a device on to leave '
          'its volume alone while recording — right for headphones, wrong '
          'for a speaker the mic can hear.',
        ),
        _buildDeviceTable(),
      ],
    ];
  }

  List<Widget> _modelSection() {
    final c = FocusColors.of(context);
    return [
      const FocusLabel('Transcription model'),
      FocusGroup(
        children: [
          FocusRow(
            title: 'Model storage',
            subtitle: _settings.modelStoragePath,
            trailing: Icon(Icons.folder_open, size: 18, color: c.ink3),
          ),
        ],
      ),
    ];
  }

  List<Widget> _shortcutsSection() {
    return [
      const FocusLabel('Keyboard shortcuts'),
      const FocusCaption(
        'Language is always auto-detected — no need to pick English or '
        'Japanese.',
      ),
      FocusGroup(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: HotkeyRecorder(
              label: 'Toggle record',
              initialValue: _settings.toggleRecordHotkey,
              onChanged: (value) {
                _updateSettings(_settings.copyWith(toggleRecordHotkey: value));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: HotkeyRecorder(
              label: 'Toggle record, then press Enter',
              initialValue: _settings.toggleRecordEnterHotkey,
              onChanged: (value) {
                _updateSettings(
                    _settings.copyWith(toggleRecordEnterHotkey: value));
              },
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _appearanceSection() {
    final c = FocusColors.of(context);
    return [
      const FocusLabel('Window'),
      FocusGroup(
        children: [
          FocusSettingRow(
            title: 'Show the island while dictating',
            subtitle: 'A small black pill with the orb and the time appears '
                'at the top of the screen while you dictate. Off: nothing '
                'appears, and the menu bar icon shows that recording is on.',
            value: _settings.showDictationOverlay,
            onChanged: (value) =>
                _updateSettings(_settings.copyWith(showDictationOverlay: value)),
          ),
          FocusRow(
            title: 'Orb expressiveness',
            subtitle: 'How strongly the orb reacts to your voice.',
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<OrbExpressiveness>(
                value: _settings.orbExpressiveness,
                onChanged: (value) {
                  if (value != null) {
                    _updateSettings(
                        _settings.copyWith(orbExpressiveness: value));
                  }
                },
                dropdownColor: c.surface,
                borderRadius: const BorderRadius.all(FocusRadius.r12),
                style: FocusText.control.copyWith(color: c.ink),
                iconEnabledColor: c.ink2,
                items: const [
                  DropdownMenuItem(
                    value: OrbExpressiveness.low,
                    child: Text('Low'),
                  ),
                  DropdownMenuItem(
                    value: OrbExpressiveness.high,
                    child: Text('High'),
                  ),
                ],
              ),
            ),
          ),
          FocusRow(
            title: 'App icon',
            subtitle: 'Where the app icon appears.',
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<DockVisibilityMode>(
                value: _settings.dockVisibilityMode,
                onChanged: (value) {
                  if (value != null) {
                    _updateSettings(
                        _settings.copyWith(dockVisibilityMode: value));
                  }
                },
                dropdownColor: c.surface,
                borderRadius: const BorderRadius.all(FocusRadius.r12),
                style: FocusText.control.copyWith(color: c.ink),
                iconEnabledColor: c.ink2,
                items: const [
                  DropdownMenuItem(
                    value: DockVisibilityMode.menuBarOnly,
                    child: Text('Menu bar only'),
                  ),
                  DropdownMenuItem(
                    value: DockVisibilityMode.dockOnly,
                    child: Text('Dock only'),
                  ),
                  DropdownMenuItem(
                    value: DockVisibilityMode.both,
                    child: Text('Menu bar and Dock'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _meetingsSection() {
    return [
      const FocusLabel('Meetings'),
      FocusGroup(
        children: [
          FocusSettingRow(
            title: 'Detect meetings automatically',
            subtitle: 'Offer to record when one app is using the microphone '
                'and playing audio at the same time.',
            value: _settings.meetingAutoDetect,
            onChanged: (value) =>
                _updateSettings(_settings.copyWith(meetingAutoDetect: value)),
          ),
          FocusSettingRow(
            title: 'Save transcripts and notes',
            subtitle: 'The transcript is written when recording stops, before '
                'notes are generated.',
            value: _settings.saveMeetingTranscripts,
            onChanged: (value) => _updateSettings(
              _settings.copyWith(saveMeetingTranscripts: value),
            ),
          ),
          _buildSaveLocationField(),
        ],
      ),
      _groupGap,
      const FocusLabel('Notes model (Ollama)'),
      const FocusCaption(
        'Notes need Ollama running locally with this model pulled. '
        'Transcription is unaffected if it is missing.',
      ),
      _buildSummaryModelField(),
    ];
  }

  List<Widget> _advancedSection() {
    return [
      const FocusLabel('Post-processing'),
      FocusGroup(
        children: [
          FocusSettingRow(
            title: 'Smart capitalization',
            value: _settings.smartCapitalization,
            onChanged: (value) =>
                _updateSettings(_settings.copyWith(smartCapitalization: value)),
          ),
          FocusSettingRow(
            title: 'Punctuation',
            value: _settings.punctuation,
            onChanged: (value) =>
                _updateSettings(_settings.copyWith(punctuation: value)),
          ),
          FocusSettingRow(
            title: 'Disfluency cleanup',
            subtitle: 'Remove filler words like "um" and "uh".',
            value: _settings.disfluencyCleanup,
            onChanged: (value) =>
                _updateSettings(_settings.copyWith(disfluencyCleanup: value)),
          ),
          FocusSettingRow(
            title: 'AI formatting (local)',
            subtitle: 'Polishes each dictation with gemma4:e4b via Ollama — '
                'fillers, natural punctuation, numbers, Japanese 、。. Adds '
                'about a second. Needs Ollama with `ollama pull gemma4:e4b`; '
                'without it the options above are used as before.',
            value: _settings.aiFormatting,
            onChanged: (value) =>
                _updateSettings(_settings.copyWith(aiFormatting: value)),
          ),
        ],
      ),
      _groupGap,
      const FocusLabel('Pasting'),
      FocusGroup(
        children: [
          FocusSettingRow(
            title: 'Keep transcript on clipboard',
            subtitle: 'Leave the transcript on the clipboard after pasting, '
                'so you can paste it again. Turn off to put your previous '
                'clipboard back.',
            value: _settings.keepTranscriptOnClipboard,
            onChanged: (value) => _updateSettings(
              _settings.copyWith(keepTranscriptOnClipboard: value),
            ),
          ),
        ],
      ),
      _groupGap,
      const FocusLabel('Custom dictionary'),
      const FocusCaption(
        'Add domain-specific terms for better recognition, like "MacBook" or '
        '"Kubernetes".',
      ),
      _buildCustomTermsField(),
    ];
  }

  /// A slider row with its value in tabular figures at the end.
  Widget _buildSliderRow({
    required String title,
    required double value,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final c = FocusColors.of(context);
    final percent = '${(value * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: FocusText.body.copyWith(fontSize: 14.4, color: c.ink),
                ),
              ),
              Text(percent, style: FocusText.detail.copyWith(color: c.ink2)),
            ],
          ),
          Slider(
            value: value,
            min: 0.0,
            max: max,
            divisions: divisions,
            label: percent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildSaveLocationField() {
    final configured = _settings.meetingSaveDirectory.trim();
    final shown = configured.isEmpty ? _defaultSaveDirectory : configured;

    return FocusRow(
      title: 'Save location',
      subtitle: shown,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (configured.isNotEmpty)
            TextButton(
              onPressed: () =>
                  _updateSettings(_settings.copyWith(meetingSaveDirectory: '')),
              child: const Text('Default'),
            ),
          OutlinedButton(
            onPressed: _pickSaveLocation,
            child: const Text('Choose…'),
          ),
        ],
      ),
    );
  }

  /// Ask the main window to run an NSOpenPanel. This window has its own Flutter
  /// engine and cannot reach the native channels registered on the main one.
  Future<void> _pickSaveLocation() async {
    try {
      final chosen = await DesktopMultiWindow.invokeMethod(
        0,
        'pick_directory',
        _settings.meetingSaveDirectory.trim().isEmpty
            ? _defaultSaveDirectory
            : _settings.meetingSaveDirectory,
      );
      // null means the panel was cancelled, which must not clear the setting.
      if (chosen is String && chosen.isNotEmpty) {
        _updateSettings(_settings.copyWith(meetingSaveDirectory: chosen));
      }
    } catch (e) {
      debugPrint('Could not open the folder picker: $e');
    }
  }

  String get _defaultSaveDirectory {
    final home = Platform.environment['HOME'] ?? '~';
    return '$home/Documents/UltraWhisper';
  }

  Widget _buildSummaryModelField() {
    final c = FocusColors.of(context);
    final active = presetForTag(_settings.meetingSummaryModel);

    return FocusGroup(
      children: [
        // Size is shown because it is the thing the user actually feels — the
        // difference between a note and an unusable laptop for two minutes.
        ...kNotesModelPresets.map(
          (preset) => RadioListTile<String>(
            value: preset.tag,
            groupValue: active?.tag,
            onChanged: (value) {
              if (value != null) {
                _updateSettings(_settings.copyWith(meetingSummaryModel: value));
              }
            },
            title: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: preset.label),
                  TextSpan(
                    text: '  ~${preset.approxGigabytes.toStringAsFixed(1)} GB',
                    style: FocusText.detail.copyWith(color: c.ink2),
                  ),
                ],
              ),
              style: FocusText.body.copyWith(fontSize: 14.4, color: c.ink),
            ),
            subtitle: Text(
              preset.note,
              style: FocusText.caption.copyWith(fontSize: 12.8, color: c.ink2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (active == null)
                Text(
                  'Custom tag',
                  style: FocusText.caption.copyWith(color: c.ink2),
                )
              else
                SelectableText.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Pull it once with '),
                      TextSpan(
                        text: active.pullCommand,
                        style: FocusText.mono.copyWith(color: c.ink),
                      ),
                    ],
                  ),
                  style: FocusText.caption.copyWith(color: c.ink2),
                ),
              const SizedBox(height: 8),
              _buildSummaryModelTagField(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryModelTagField() {
    final c = FocusColors.of(context);
    return TextFormField(
      // Keyed on the value: `initialValue` is only read on the first build, so
      // without this, picking a preset above would leave a stale tag showing.
      key: ValueKey(_settings.meetingSummaryModel),
      initialValue: _settings.meetingSummaryModel,
      style: FocusText.mono.copyWith(fontSize: 13, color: c.ink),
      decoration: const InputDecoration(
        hintText: 'hf.co/unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q3_K_XL',
      ),
      onChanged: (value) => _updateSettings(
        _settings.copyWith(meetingSummaryModel: value.trim()),
      ),
    );
  }

  /// Table of remembered output devices, one row per device.
  ///
  /// Deleting a row forgets the device rather than pinning a decision: it comes
  /// back with the default the next time it is actually used, so the table
  /// stays as short as the user wants it.
  Widget _buildDeviceTable() {
    final devices = _settings.audioDevicePrefs;

    if (devices.isEmpty) {
      return const FocusGroup(
        children: [
          FocusRow(
            title: 'No devices remembered yet.',
            subtitle: 'Record once and the device you were listening on will '
                'appear here.',
          ),
        ],
      );
    }

    return FocusGroup(
      children: [
        for (int i = 0; i < devices.length; i++)
          _buildDeviceRow(devices[i], i),
      ],
    );
  }

  Widget _buildDeviceRow(AudioDevicePref device, int index) {
    final kind = device.isBluetooth ? 'Bluetooth' : 'Wired or built-in';
    return FocusRow(
      title: device.displayName,
      subtitle: device.skipDuck
          ? '$kind. Volume is left alone.'
          : '$kind. Volume is lowered while recording.',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FocusSwitch(
            value: device.skipDuck,
            onChanged: (value) {
              final updated =
                  List<AudioDevicePref>.from(_settings.audioDevicePrefs);
              updated[index] = device.copyWith(skipDuck: value);
              _updateSettings(_settings.copyWith(audioDevicePrefs: updated));
            },
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Forget this device',
            onPressed: () {
              final updated =
                  List<AudioDevicePref>.from(_settings.audioDevicePrefs)
                    ..removeAt(index);
              _updateSettings(_settings.copyWith(audioDevicePrefs: updated));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCustomTermsField() {
    final textController = TextEditingController();

    void addTerm(String raw) {
      final value = raw.trim();
      if (value.isNotEmpty && !_settings.customTerms.contains(value)) {
        final updatedTerms = List<String>.from(_settings.customTerms)
          ..add(value);
        _updateSettings(_settings.copyWith(customTerms: updatedTerms));
        textController.clear();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current terms as chips
        if (_settings.customTerms.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _settings.customTerms.map((term) {
              return Chip(
                label: Text(term),
                deleteIcon: const Icon(Icons.close, size: 14),
                deleteButtonTooltipMessage: 'Remove',
                onDeleted: () {
                  final updatedTerms = List<String>.from(_settings.customTerms)
                    ..remove(term);
                  _updateSettings(_settings.copyWith(customTerms: updatedTerms));
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],

        // Input field to add new terms
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: textController,
                decoration: const InputDecoration(hintText: 'Add a term'),
                onSubmitted: addTerm,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => addTerm(textController.text),
              child: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }
}
