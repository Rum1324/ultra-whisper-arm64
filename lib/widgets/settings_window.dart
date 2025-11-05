import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings.dart';
import '../services/app_service.dart';
import 'hotkey_recorder.dart';

class SettingsWindow extends StatefulWidget {
  const SettingsWindow({super.key});

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  late Settings _settings;

  @override
  void initState() {
    super.initState();
    _settings = context.read<AppService>().settings;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(20),
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
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),

        const Divider(color: Colors.white12, height: 1),

        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
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
                      setState(() {
                        _settings = _settings.copyWith(inputDevice: value);
                      });
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
                      setState(() {
                        _settings = _settings.copyWith(model: value);
                      });
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
                      setState(() {
                        _settings = _settings.copyWith(device: value);
                      });
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
                    setState(() {
                      _settings = _settings.copyWith(
                        autoDetectLanguage: value ?? true,
                      );
                    });
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
                        setState(() {
                          _settings = _settings.copyWith(manualLanguage: value);
                        });
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
                    setState(() {
                      _settings = _settings.copyWith(holdToTalkHotkey: value);
                    });
                  },
                ),

                const SizedBox(height: 16),

                HotkeyRecorder(
                  label: 'Toggle Record',
                  initialValue: _settings.toggleRecordHotkey,
                  onChanged: (value) {
                    setState(() {
                      _settings = _settings.copyWith(toggleRecordHotkey: value);
                    });
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
                          setState(() {
                            _settings = _settings.copyWith(glassBlurRadius: value);
                          });
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
                          setState(() {
                            _settings = _settings.copyWith(glassOpacity: value);
                          });
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
                          setState(() {
                            _settings = _settings.copyWith(borderOpacity: value);
                          });
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
                    setState(() {
                      _settings = _settings.copyWith(alwaysOnTop: value ?? false);
                    });
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
                    setState(() {
                      _settings = _settings.copyWith(
                        bringToFrontDuringRecording: value ?? false,
                      );
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
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
                      setState(() {
                        _settings = _settings.copyWith(loggingLevel: value);
                      });
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
                    setState(() {
                      _settings = _settings.copyWith(
                        smartCapitalization: value ?? true,
                      );
                    });
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
                    setState(() {
                      _settings = _settings.copyWith(punctuation: value ?? true);
                    });
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
                    setState(() {
                      _settings = _settings.copyWith(
                        disfluencyCleanup: value ?? true,
                      );
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                const SizedBox(height: 32),

                _buildLabel('Default Paste Action'),
                const SizedBox(height: 8),
                DropdownButtonFormField<PasteAction>(
                  value: _settings.defaultAction,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _settings = _settings.copyWith(defaultAction: value);
                      });
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
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _saveSettings,
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

  void _saveSettings() {
    context.read<AppService>().updateSettings(_settings);
    Navigator.of(context).pop();
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
