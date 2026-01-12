import 'package:json_annotation/json_annotation.dart';

part 'settings.g.dart';

enum PasteAction {
  paste,
  pasteWithEnter,
  clipboardOnly
}

enum WhisperModel {
  small,
  medium,
  large,
  largeV3,
  largeV3Turbo
}

enum ComputeDevice {
  auto,
  metal,
  cpu
}

enum ComputeType {
  int8Float16,
  int8Float32,
  float16,
  int8,
  float32
}

enum Language {
  auto,
  english,
  japanese
}

enum DockVisibilityMode {
  menuBarOnly,
  dockOnly,
  both
}

@JsonSerializable()
class Settings {
  // General settings
  final PasteAction defaultAction;

  // Audio settings
  final String inputDevice;
  final int sampleRate;
  final int chunkSizeMs;
  final bool duckVolumeDuringRecording;
  final double volumeDuckPercentage;

  // Model settings
  final WhisperModel model;
  final ComputeDevice device;
  final ComputeType computeType;
  final String modelStoragePath;

  // Language settings
  final bool autoDetectLanguage;
  final Language manualLanguage;

  // Hotkeys (stored as key combinations)
  final String holdToTalkHotkey;
  final String toggleRecordHotkey;
  final String holdToTalkJapaneseHotkey;  // New: Japanese-specific hotkey
  final String toggleRecordJapaneseHotkey;  // New: Japanese-specific hotkey

  // Advanced settings
  final String loggingLevel;
  final bool smartCapitalization;
  final bool punctuation;
  final bool disfluencyCleanup;
  final List<String> customTerms; // Custom dictionary for domain-specific terms

  // UI settings (not exposed in UI, used internally)
  final double overlayWidth;
  final double overlayHeight;

  // Appearance settings
  final double glassBlurRadius;
  final double glassOpacity;
  final String glassEffect; // 'hudWindow', 'sidebar', 'menu', 'popover', 'titlebar'
  final double borderOpacity;
  final bool alwaysOnTop;
  final bool bringToFrontDuringRecording;
  final DockVisibilityMode dockVisibilityMode;
  
  const Settings({
    this.defaultAction = PasteAction.paste,

    this.inputDevice = 'default',
    this.sampleRate = 16000,
    this.chunkSizeMs = 30,
    this.duckVolumeDuringRecording = true,
    this.volumeDuckPercentage = 0.1,

    this.model = WhisperModel.largeV3Turbo,
    this.device = ComputeDevice.auto,
    this.computeType = ComputeType.int8Float32,
    this.modelStoragePath = '',

    this.autoDetectLanguage = true,
    this.manualLanguage = Language.english,

    this.holdToTalkHotkey = 'Right ⌥',
    this.toggleRecordHotkey = '⌥⇧R',
    this.holdToTalkJapaneseHotkey = '⌥T',  // Option+T for Japanese
    this.toggleRecordJapaneseHotkey = '⌥⇧T',  // Option+Shift+T for Japanese toggle

    this.loggingLevel = 'INFO',
    this.smartCapitalization = true,
    this.punctuation = true,
    this.disfluencyCleanup = true,
    this.customTerms = const [],

    this.overlayWidth = 360.0,
    this.overlayHeight = 100.0,

    this.glassBlurRadius = 20.0,
    this.glassOpacity = 0.05,
    this.glassEffect = 'hudWindow',
    this.borderOpacity = 0.2,
    this.alwaysOnTop = false,
    this.bringToFrontDuringRecording = false,
    this.dockVisibilityMode = DockVisibilityMode.menuBarOnly,
  });
  
  factory Settings.fromJson(Map<String, dynamic> json) => _$SettingsFromJson(json);
  Map<String, dynamic> toJson() => _$SettingsToJson(this);
  
  Settings copyWith({
    PasteAction? defaultAction,
    String? inputDevice,
    int? sampleRate,
    int? chunkSizeMs,
    bool? duckVolumeDuringRecording,
    double? volumeDuckPercentage,
    WhisperModel? model,
    ComputeDevice? device,
    ComputeType? computeType,
    String? modelStoragePath,
    bool? autoDetectLanguage,
    Language? manualLanguage,
    String? holdToTalkHotkey,
    String? toggleRecordHotkey,
    String? holdToTalkJapaneseHotkey,
    String? toggleRecordJapaneseHotkey,
    String? loggingLevel,
    bool? smartCapitalization,
    bool? punctuation,
    bool? disfluencyCleanup,
    List<String>? customTerms,
    double? overlayWidth,
    double? overlayHeight,
    double? glassBlurRadius,
    double? glassOpacity,
    String? glassEffect,
    double? borderOpacity,
    bool? alwaysOnTop,
    bool? bringToFrontDuringRecording,
    DockVisibilityMode? dockVisibilityMode,
  }) {
    return Settings(
      defaultAction: defaultAction ?? this.defaultAction,
      inputDevice: inputDevice ?? this.inputDevice,
      sampleRate: sampleRate ?? this.sampleRate,
      chunkSizeMs: chunkSizeMs ?? this.chunkSizeMs,
      duckVolumeDuringRecording: duckVolumeDuringRecording ?? this.duckVolumeDuringRecording,
      volumeDuckPercentage: volumeDuckPercentage ?? this.volumeDuckPercentage,
      model: model ?? this.model,
      device: device ?? this.device,
      computeType: computeType ?? this.computeType,
      modelStoragePath: modelStoragePath ?? this.modelStoragePath,
      autoDetectLanguage: autoDetectLanguage ?? this.autoDetectLanguage,
      manualLanguage: manualLanguage ?? this.manualLanguage,
      holdToTalkHotkey: holdToTalkHotkey ?? this.holdToTalkHotkey,
      toggleRecordHotkey: toggleRecordHotkey ?? this.toggleRecordHotkey,
      holdToTalkJapaneseHotkey: holdToTalkJapaneseHotkey ?? this.holdToTalkJapaneseHotkey,
      toggleRecordJapaneseHotkey: toggleRecordJapaneseHotkey ?? this.toggleRecordJapaneseHotkey,
      loggingLevel: loggingLevel ?? this.loggingLevel,
      smartCapitalization: smartCapitalization ?? this.smartCapitalization,
      punctuation: punctuation ?? this.punctuation,
      disfluencyCleanup: disfluencyCleanup ?? this.disfluencyCleanup,
      customTerms: customTerms ?? this.customTerms,
      overlayWidth: overlayWidth ?? this.overlayWidth,
      overlayHeight: overlayHeight ?? this.overlayHeight,
      glassBlurRadius: glassBlurRadius ?? this.glassBlurRadius,
      glassOpacity: glassOpacity ?? this.glassOpacity,
      glassEffect: glassEffect ?? this.glassEffect,
      borderOpacity: borderOpacity ?? this.borderOpacity,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      bringToFrontDuringRecording: bringToFrontDuringRecording ?? this.bringToFrontDuringRecording,
      dockVisibilityMode: dockVisibilityMode ?? this.dockVisibilityMode,
    );
  }
}