import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import '../models/settings.dart';
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
    if (_isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A1A),
          body: Center(
            child: CircularProgressIndicator(
              color: Colors.blue.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Settings - UltraWhisper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: SettingsWindowContent(
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
    return Column(
      children: [
        // Header with padding for traffic light buttons
        Container(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
          child: Row(
            children: [
              const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: _handleCancel,
              ),
            ],
          ),
        ),

        const Divider(color: Colors.white12, height: 1),

        // Settings content
        Expanded(
          child: SettingsWindowBody(
            settings: _settings,
            onSettingsChanged: _handleSettingsUpdate,
          ),
        ),

        const Divider(color: Colors.white12, height: 1),

        // Footer buttons
        Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _handleCancel,
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _handleSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AUDIO SECTION
          _buildSectionHeader('Audio'),
          const SizedBox(height: 16),
          _buildLabel('Volume Control During Recording'),
          const SizedBox(height: 8),
          CheckboxListTile(
            title: const Text(
              'Reduce system volume during recording',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Automatically lower system volume to minimize background audio interference',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _settings.duckVolumeDuringRecording,
            onChanged: (value) {
              _updateSettings(_settings.copyWith(
                duckVolumeDuringRecording: value ?? true,
              ));
            },
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),

          if (_settings.duckVolumeDuringRecording) ...[
            Padding(
              padding: const EdgeInsets.only(left: 24.0),
              child: CheckboxListTile(
                title: const Text(
                  'Skip when Bluetooth headphones are connected',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  "System audio can't bleed into the mic through headphones. "
                  'Turn this off if you use a Bluetooth speaker.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                value: _settings.skipDuckWhenBluetooth,
                onChanged: (value) {
                  _updateSettings(_settings.copyWith(
                    skipDuckWhenBluetooth: value ?? true,
                  ));
                },
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),

            const SizedBox(height: 16),
            _buildLabel('Volume level during recording'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _settings.volumeDuckPercentage,
                    min: 0.0,
                    max: 0.3,
                    divisions: 30,
                    label: '${(_settings.volumeDuckPercentage * 100).round()}%',
                    onChanged: (value) {
                      _updateSettings(_settings.copyWith(volumeDuckPercentage: value));
                    },
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '${(_settings.volumeDuckPercentage * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 12.0),
              child: Text(
                'Original volume will be automatically restored after recording',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // MODEL SECTION
          _buildSectionHeader('Transcription Model'),
          const SizedBox(height: 16),
          _buildLabel('Model Storage Path (Read-only)'),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: _settings.modelStoragePath,
            readOnly: true,
            style: const TextStyle(color: Colors.white70),
            decoration: _inputDecoration().copyWith(
              suffixIcon: const Icon(Icons.folder_open, color: Colors.white30),
            ),
          ),

          const SizedBox(height: 32),

          // SHORTCUTS SECTION
          _buildSectionHeader('Keyboard Shortcuts'),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: Text(
              'Language is always auto-detected — no need to pick English or Japanese.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          HotkeyRecorder(
            label: 'Toggle Record',
            initialValue: _settings.toggleRecordHotkey,
            onChanged: (value) {
              _updateSettings(_settings.copyWith(toggleRecordHotkey: value));
            },
          ),

          const SizedBox(height: 16),

          HotkeyRecorder(
            label: 'Toggle Record + Enter',
            initialValue: _settings.toggleRecordEnterHotkey,
            onChanged: (value) {
              _updateSettings(_settings.copyWith(toggleRecordEnterHotkey: value));
            },
          ),

          const SizedBox(height: 32),

          // APPEARANCE SECTION
          _buildSectionHeader('Appearance'),
          const SizedBox(height: 16),

          _buildLabel('Glass Opacity'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _settings.glassOpacity,
                  min: 0.0,
                  max: 1.0,
                  divisions: 100,
                  label: '${(_settings.glassOpacity * 100).round()}%',
                  onChanged: (value) {
                    _updateSettings(_settings.copyWith(glassOpacity: value));
                  },
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '${(_settings.glassOpacity * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          _buildLabel('Window Behavior'),
          const SizedBox(height: 8),
          CheckboxListTile(
            title: const Text(
              'Always on Top',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Keep window above other applications',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _settings.alwaysOnTop,
            onChanged: (value) {
              _updateSettings(_settings.copyWith(alwaysOnTop: value ?? false));
            },
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),

          CheckboxListTile(
            title: const Text(
              'Bring to Front During Recording',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Bring window to front when recording starts',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _settings.bringToFrontDuringRecording,
            onChanged: (value) {
              _updateSettings(_settings.copyWith(
                bringToFrontDuringRecording: value ?? false,
              ));
            },
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),

          const SizedBox(height: 16),

          _buildLabel('App Visibility'),
          const SizedBox(height: 8),
          DropdownButtonFormField<DockVisibilityMode>(
            value: _settings.dockVisibilityMode,
            onChanged: (value) {
              if (value != null) {
                _updateSettings(_settings.copyWith(dockVisibilityMode: value));
              }
            },
            dropdownColor: const Color(0xFF2D2D2D),
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(),
            items: const [
              DropdownMenuItem(
                value: DockVisibilityMode.menuBarOnly,
                child: Text('Menu Bar Only'),
              ),
              DropdownMenuItem(
                value: DockVisibilityMode.dockOnly,
                child: Text('Dock Only'),
              ),
              DropdownMenuItem(
                value: DockVisibilityMode.both,
                child: Text('Both Menu Bar and Dock'),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8.0, left: 12.0),
            child: Text(
              'Choose where the app icon appears',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),

          const SizedBox(height: 32),

          // ADVANCED SECTION
          _buildSectionHeader('Advanced'),
          const SizedBox(height: 16),
          _buildLabel('Post-processing Options'),
          const SizedBox(height: 8),
          CheckboxListTile(
            title: const Text(
              'Smart Capitalization',
              style: TextStyle(color: Colors.white),
            ),
            value: _settings.smartCapitalization,
            onChanged: (value) {
              _updateSettings(_settings.copyWith(
                smartCapitalization: value ?? true,
              ));
            },
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),

          CheckboxListTile(
            title: const Text(
              'Punctuation',
              style: TextStyle(color: Colors.white),
            ),
            value: _settings.punctuation,
            onChanged: (value) {
              _updateSettings(_settings.copyWith(punctuation: value ?? true));
            },
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),

          CheckboxListTile(
            title: const Text(
              'Disfluency Cleanup',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Remove filler words like "um", "uh", etc.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _settings.disfluencyCleanup,
            onChanged: (value) {
              _updateSettings(_settings.copyWith(
                disfluencyCleanup: value ?? true,
              ));
            },
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),

          const SizedBox(height: 24),

          _buildLabel('Custom Dictionary'),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(left: 12.0, bottom: 8.0),
            child: Text(
              'Add domain-specific terms for better recognition (e.g., "MacBook", "Kubernetes")',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          _buildCustomTermsField(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white70,
      ),
    );
  }

  Widget _buildCustomTermsField() {
    final textController = TextEditingController();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Display current terms as chips
        if (_settings.customTerms.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _settings.customTerms.map((term) {
              return Chip(
                label: Text(term, style: const TextStyle(color: Colors.white)),
                deleteIcon: const Icon(Icons.close, size: 18, color: Colors.white70),
                onDeleted: () {
                  final updatedTerms = List<String>.from(_settings.customTerms);
                  updatedTerms.remove(term);
                  _updateSettings(_settings.copyWith(customTerms: updatedTerms));
                },
                backgroundColor: const Color(0xFF3D3D3D),
              );
            }).toList(),
          ),
        if (_settings.customTerms.isNotEmpty) const SizedBox(height: 12),

        // Input field to add new terms
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: textController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration().copyWith(
                  hintText: 'Add a custom term...',
                  hintStyle: const TextStyle(color: Colors.white38),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty && !_settings.customTerms.contains(value.trim())) {
                    final updatedTerms = List<String>.from(_settings.customTerms);
                    updatedTerms.add(value.trim());
                    _updateSettings(_settings.copyWith(customTerms: updatedTerms));
                    textController.clear();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                final value = textController.text;
                if (value.trim().isNotEmpty && !_settings.customTerms.contains(value.trim())) {
                  final updatedTerms = List<String>.from(_settings.customTerms);
                  updatedTerms.add(value.trim());
                  _updateSettings(_settings.copyWith(customTerms: updatedTerms));
                  textController.clear();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _inputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFF2D2D2D),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.blue),
      ),
    );
  }

}
