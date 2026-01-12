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
          _buildLabel('Input Device'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _settings.inputDevice,
            onChanged: (value) {
              if (value != null) {
                _updateSettings(_settings.copyWith(inputDevice: value));
              }
            },
            dropdownColor: const Color(0xFF2D2D2D),
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(),
            items: const [
              DropdownMenuItem(
                value: 'default',
                child: Text('Built-in Microphone'),
              ),
              DropdownMenuItem(
                value: 'blackhole',
                child: Text('BlackHole 2ch'),
              ),
            ],
          ),

          const SizedBox(height: 24),

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
          _buildLabel('Whisper Model'),
          const SizedBox(height: 8),
          DropdownButtonFormField<WhisperModel>(
            value: _settings.model,
            onChanged: (value) {
              if (value != null) {
                _updateSettings(_settings.copyWith(model: value));
              }
            },
            dropdownColor: const Color(0xFF2D2D2D),
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(),
            items: WhisperModel.values.map((model) {
              return DropdownMenuItem(
                value: model,
                child: Text(_modelToString(model)),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          _buildLabel('Compute Device'),
          const SizedBox(height: 8),
          DropdownButtonFormField<ComputeDevice>(
            value: _settings.device,
            onChanged: (value) {
              if (value != null) {
                _updateSettings(_settings.copyWith(device: value));
              }
            },
            dropdownColor: const Color(0xFF2D2D2D),
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(),
            items: ComputeDevice.values.map((device) {
              return DropdownMenuItem(
                value: device,
                child: Text(_deviceToString(device)),
              );
            }).toList(),
          ),

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

          // LANGUAGE SECTION
          _buildSectionHeader('Language'),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text(
              'Auto-detect Language',
              style: TextStyle(color: Colors.white),
            ),
            value: _settings.autoDetectLanguage,
            onChanged: (value) {
              _updateSettings(_settings.copyWith(
                autoDetectLanguage: value ?? true,
              ));
            },
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),

          if (!_settings.autoDetectLanguage) ...[
            const SizedBox(height: 16),
            _buildLabel('Manual Language Override'),
            const SizedBox(height: 8),
            DropdownButtonFormField<Language>(
              value: _settings.manualLanguage,
              onChanged: (value) {
                if (value != null) {
                  _updateSettings(_settings.copyWith(manualLanguage: value));
                }
              },
              dropdownColor: const Color(0xFF2D2D2D),
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(),
              items: Language.values.map((lang) {
                return DropdownMenuItem(
                  value: lang,
                  child: Text(_languageToString(lang)),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 32),

          // SHORTCUTS SECTION
          _buildSectionHeader('Keyboard Shortcuts'),
          const SizedBox(height: 16),
          HotkeyRecorder(
            label: 'Hold-to-talk',
            initialValue: _settings.holdToTalkHotkey,
            onChanged: (value) {
              _updateSettings(_settings.copyWith(holdToTalkHotkey: value));
            },
          ),

          const SizedBox(height: 16),

          HotkeyRecorder(
            label: 'Toggle Record',
            initialValue: _settings.toggleRecordHotkey,
            onChanged: (value) {
              _updateSettings(_settings.copyWith(toggleRecordHotkey: value));
            },
          ),

          const SizedBox(height: 32),

          // APPEARANCE SECTION
          _buildSectionHeader('Appearance'),
          const SizedBox(height: 16),

          _buildLabel('Blur Radius'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _settings.glassBlurRadius,
                  min: 0,
                  max: 50,
                  divisions: 50,
                  label: _settings.glassBlurRadius.round().toString(),
                  onChanged: (value) {
                    _updateSettings(_settings.copyWith(glassBlurRadius: value));
                  },
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '${_settings.glassBlurRadius.round()}px',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),

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

          const SizedBox(height: 16),

          _buildLabel('Border Opacity'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _settings.borderOpacity,
                  min: 0.0,
                  max: 1.0,
                  divisions: 100,
                  label: '${(_settings.borderOpacity * 100).round()}%',
                  onChanged: (value) {
                    _updateSettings(_settings.copyWith(borderOpacity: value));
                  },
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '${(_settings.borderOpacity * 100).round()}%',
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
          _buildLabel('Logging Level'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _settings.loggingLevel,
            onChanged: (value) {
              if (value != null) {
                _updateSettings(_settings.copyWith(loggingLevel: value));
              }
            },
            dropdownColor: const Color(0xFF2D2D2D),
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(),
            items: const [
              DropdownMenuItem(value: 'DEBUG', child: Text('Debug')),
              DropdownMenuItem(value: 'INFO', child: Text('Info')),
              DropdownMenuItem(value: 'WARNING', child: Text('Warning')),
              DropdownMenuItem(value: 'ERROR', child: Text('Error')),
            ],
          ),

          const SizedBox(height: 24),

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

          const SizedBox(height: 32),

          _buildLabel('Default Paste Action'),
          const SizedBox(height: 8),
          DropdownButtonFormField<PasteAction>(
            value: _settings.defaultAction,
            onChanged: (value) {
              if (value != null) {
                _updateSettings(_settings.copyWith(defaultAction: value));
              }
            },
            dropdownColor: const Color(0xFF2D2D2D),
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(),
            items: PasteAction.values.map((action) {
              return DropdownMenuItem(
                value: action,
                child: Text(_pasteActionToString(action)),
              );
            }).toList(),
          ),
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

  String _pasteActionToString(PasteAction action) {
    switch (action) {
      case PasteAction.paste:
        return 'Paste';
      case PasteAction.pasteWithEnter:
        return 'Paste + Enter';
      case PasteAction.clipboardOnly:
        return 'Clipboard Only';
    }
  }

  String _modelToString(WhisperModel model) {
    switch (model) {
      case WhisperModel.small:
        return 'small';
      case WhisperModel.medium:
        return 'medium';
      case WhisperModel.large:
        return 'large';
      case WhisperModel.largeV3:
        return 'large-v3';
      case WhisperModel.largeV3Turbo:
        return 'large-v3-turbo';
    }
  }

  String _deviceToString(ComputeDevice device) {
    switch (device) {
      case ComputeDevice.auto:
        return 'Auto';
      case ComputeDevice.metal:
        return 'Metal (GPU)';
      case ComputeDevice.cpu:
        return 'CPU';
    }
  }

  String _languageToString(Language language) {
    switch (language) {
      case Language.auto:
        return 'Auto-detect';
      case Language.english:
        return 'English';
      case Language.japanese:
        return 'Japanese';
    }
  }
}
