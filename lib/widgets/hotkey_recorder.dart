import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/focus_theme.dart';

class HotkeyRecorder extends StatefulWidget {
  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final String hintText;

  const HotkeyRecorder({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.hintText = 'Click and press keys, then Enter to confirm',
  });

  @override
  State<HotkeyRecorder> createState() => _HotkeyRecorderState();
}

class _HotkeyRecorderState extends State<HotkeyRecorder> {
  late String _currentValue;
  bool _isRecording = false;
  final List<String> _pressedKeys = [];
  final Set<LogicalKeyboardKey> _pressedModifiers = {};
  FocusNode? _focusNode;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue;
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode?.dispose();
    super.dispose();
  }

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _pressedKeys.clear();
      _pressedModifiers.clear();
    });
    
    // Force focus and ensure it's captured
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode?.requestFocus();
      print('Hotkey recorder started recording, focus requested');
    });
  }


  void _confirmHotkey() {
    String hotkeyString = _buildHotkeyString();
    
    // Special case: if only one modifier is pressed, use it as the key
    if (hotkeyString.isEmpty && _pressedModifiers.length == 1) {
      hotkeyString = _getKeyDisplayName(_pressedModifiers.first);
    }
    
    if (hotkeyString.isNotEmpty) {
      setState(() {
        _currentValue = hotkeyString;
        _isRecording = false;
      });
      widget.onChanged(_currentValue);
      _focusNode?.unfocus();
    }
  }

  void _cancelRecording() {
    setState(() {
      _isRecording = false;
      _pressedKeys.clear();
      _pressedModifiers.clear();
    });
    _focusNode?.unfocus();
  }

  String _buildHotkeyString() {
    if (_pressedKeys.isEmpty && _pressedModifiers.isEmpty) {
      return '';
    }

    List<String> parts = [];
    
    // Add modifiers in consistent order
    if (_pressedModifiers.contains(LogicalKeyboardKey.controlLeft) || 
        _pressedModifiers.contains(LogicalKeyboardKey.controlRight)) {
      parts.add('⌃');
    }
    if (_pressedModifiers.contains(LogicalKeyboardKey.altLeft) || 
        _pressedModifiers.contains(LogicalKeyboardKey.altRight)) {
      parts.add('⌥');
    }
    if (_pressedModifiers.contains(LogicalKeyboardKey.shiftLeft) || 
        _pressedModifiers.contains(LogicalKeyboardKey.shiftRight)) {
      parts.add('⇧');
    }
    if (_pressedModifiers.contains(LogicalKeyboardKey.metaLeft) || 
        _pressedModifiers.contains(LogicalKeyboardKey.metaRight)) {
      parts.add('⌘');
    }
    
    // Add non-modifier keys
    parts.addAll(_pressedKeys);
    
    return parts.join('');
  }

  String _getKeyDisplayName(LogicalKeyboardKey key) {
    // Special keys with symbols
    if (key == LogicalKeyboardKey.space) return 'Space';
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.backspace) return 'Backspace';
    if (key == LogicalKeyboardKey.delete) return 'Delete';
    if (key == LogicalKeyboardKey.arrowUp) return '↑';
    if (key == LogicalKeyboardKey.arrowDown) return '↓';
    if (key == LogicalKeyboardKey.arrowLeft) return '←';
    if (key == LogicalKeyboardKey.arrowRight) return '→';
    
    // Function keys
    if (key == LogicalKeyboardKey.f1) return 'F1';
    if (key == LogicalKeyboardKey.f2) return 'F2';
    if (key == LogicalKeyboardKey.f3) return 'F3';
    if (key == LogicalKeyboardKey.f4) return 'F4';
    if (key == LogicalKeyboardKey.f5) return 'F5';
    if (key == LogicalKeyboardKey.f6) return 'F6';
    if (key == LogicalKeyboardKey.f7) return 'F7';
    if (key == LogicalKeyboardKey.f8) return 'F8';
    if (key == LogicalKeyboardKey.f9) return 'F9';
    if (key == LogicalKeyboardKey.f10) return 'F10';
    if (key == LogicalKeyboardKey.f11) return 'F11';
    if (key == LogicalKeyboardKey.f12) return 'F12';
    
    // Handle modifier keys when pressed alone
    if (key == LogicalKeyboardKey.altLeft) return 'Left ⌥';
    if (key == LogicalKeyboardKey.altRight) return 'Right ⌥';
    if (key == LogicalKeyboardKey.controlLeft) return 'Left ⌃';
    if (key == LogicalKeyboardKey.controlRight) return 'Right ⌃';
    if (key == LogicalKeyboardKey.shiftLeft) return 'Left ⇧';
    if (key == LogicalKeyboardKey.shiftRight) return 'Right ⇧';
    if (key == LogicalKeyboardKey.metaLeft) return 'Left ⌘';
    if (key == LogicalKeyboardKey.metaRight) return 'Right ⌘';
    
    // For letter keys, use the label if available
    if (key.keyLabel.isNotEmpty) {
      return key.keyLabel.toUpperCase();
    }
    
    // Fallback to debug name
    return key.debugName ?? key.toString();
  }

  bool _isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  String _getRecordingDisplayText() {
    final hotkeyString = _buildHotkeyString();
    if (hotkeyString.isNotEmpty) {
      return hotkeyString;
    }
    
    // Show single modifier if only one is pressed
    if (_pressedModifiers.length == 1) {
      return _getKeyDisplayName(_pressedModifiers.first);
    }
    
    return 'Press keys...';
  }

  @override
  Widget build(BuildContext context) {
    final c = FocusColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: FocusText.body.copyWith(fontSize: 14.4, color: c.ink),
        ),
        const SizedBox(height: 8),
        
        Focus(
          focusNode: _focusNode!,
          onKeyEvent: (FocusNode node, KeyEvent event) {
            print('Key event received: ${event.runtimeType}, recording: $_isRecording, key: ${event.logicalKey}');
            
            if (!_isRecording) return KeyEventResult.ignored;
            
            if (event is KeyDownEvent) {
              final key = event.logicalKey;
              print('Key down: ${key.debugName}');
              
              // Handle Enter to confirm
              if (key == LogicalKeyboardKey.enter) {
                print('Enter pressed - confirming hotkey');
                _confirmHotkey();
                return KeyEventResult.handled;
              }
              
              // Handle Escape to cancel
              if (key == LogicalKeyboardKey.escape) {
                print('Escape pressed - cancelling');
                _cancelRecording();
                return KeyEventResult.handled;
              }
              
              setState(() {
                if (_isModifierKey(key)) {
                  print('Adding modifier: ${key.debugName}');
                  _pressedModifiers.add(key);
                } else {
                  // Non-modifier key pressed
                  print('Adding key: ${_getKeyDisplayName(key)}');
                  _pressedKeys.clear();
                  _pressedKeys.add(_getKeyDisplayName(key));
                }
              });
              return KeyEventResult.handled;
            } else if (event is KeyUpEvent) {
              final key = event.logicalKey;
              if (_isModifierKey(key)) {
                print('Removing modifier: ${key.debugName}');
                setState(() {
                  _pressedModifiers.remove(key);
                });
              }
              return KeyEventResult.handled;
            }
            
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: () {
              if (!_isRecording) {
                _startRecording();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              constraints: const BoxConstraints(minHeight: 44),
              // Focus Field: sheet fill, line border, radius-10. While it is
              // listening for keys it is live, so it takes the accent.
              decoration: BoxDecoration(
                color: _isRecording ? c.accentTint : c.sheet,
                borderRadius: const BorderRadius.all(FocusRadius.r10),
                border: Border.all(
                  color: _isRecording ? c.accent : c.line,
                  width: _isRecording ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isRecording
                          ? _getRecordingDisplayText()
                          : (_currentValue.isEmpty
                              ? widget.hintText
                              : _currentValue),
                      style: FocusText.control.copyWith(
                        color: _isRecording
                            ? c.accent
                            : (_currentValue.isEmpty ? c.ink3 : c.ink),
                        fontWeight:
                            _currentValue.isEmpty && !_isRecording
                                ? FontWeight.w400
                                : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_isRecording) ...[
                    IconButton(
                      icon: Icon(Icons.check, color: c.ok),
                      onPressed: _confirmHotkey,
                      tooltip: 'Confirm (Enter)',
                      iconSize: 18,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _cancelRecording,
                      tooltip: 'Cancel (Esc)',
                      iconSize: 18,
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.keyboard, color: c.ink3, size: 18),
                    ),
                ],
              ),
            ),
          ),
        ),
        
        if (_isRecording) ...[
          const SizedBox(height: 8),
          Text(
            'Press Enter to confirm, or Esc to cancel.',
            style: FocusText.caption.copyWith(color: c.ink2),
          ),
        ],
      ],
    );
  }
}