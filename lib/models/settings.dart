import 'package:json_annotation/json_annotation.dart';

part 'settings.g.dart';

enum DockVisibilityMode {
  menuBarOnly,
  dockOnly,
  both
}

@JsonSerializable()
class Settings {
  // Audio settings
  final int sampleRate;
  final int chunkSizeMs;
  final bool duckVolumeDuringRecording;
  final double volumeDuckPercentage;

  // Model settings
  final String modelStoragePath;

  // Hotkeys (stored as key combinations)
  final String toggleRecordHotkey;
  final String toggleRecordEnterHotkey; // Toggle record, then paste + press Enter

  // Advanced settings
  final bool smartCapitalization;
  final bool punctuation;
  final bool disfluencyCleanup;
  final List<String> customTerms; // Custom dictionary for domain-specific terms

  // UI settings (not exposed in UI, used internally)
  final double overlayWidth;
  final double overlayHeight;

  // Appearance settings
  final double glassOpacity;
  final String glassEffect; // 'hudWindow', 'sidebar', 'menu', 'popover', 'titlebar'
  final bool alwaysOnTop;
  final bool bringToFrontDuringRecording;
  final DockVisibilityMode dockVisibilityMode;

  const Settings({
    this.sampleRate = 16000,
    this.chunkSizeMs = 30,
    this.duckVolumeDuringRecording = true,
    this.volumeDuckPercentage = 0.1,

    this.modelStoragePath = '',

    this.toggleRecordHotkey = '⌥⇧R',
    this.toggleRecordEnterHotkey = '⌥⇧E',

    this.smartCapitalization = true,
    this.punctuation = true,
    this.disfluencyCleanup = true,
    this.customTerms = const [],

    this.overlayWidth = 360.0,
    this.overlayHeight = 100.0,

    this.glassOpacity = 0.05,
    this.glassEffect = 'hudWindow',
    this.alwaysOnTop = false,
    this.bringToFrontDuringRecording = false,
    this.dockVisibilityMode = DockVisibilityMode.menuBarOnly,
  });

  factory Settings.fromJson(Map<String, dynamic> json) => _$SettingsFromJson(json);
  Map<String, dynamic> toJson() => _$SettingsToJson(this);

  Settings copyWith({
    int? sampleRate,
    int? chunkSizeMs,
    bool? duckVolumeDuringRecording,
    double? volumeDuckPercentage,
    String? modelStoragePath,
    String? toggleRecordHotkey,
    String? toggleRecordEnterHotkey,
    bool? smartCapitalization,
    bool? punctuation,
    bool? disfluencyCleanup,
    List<String>? customTerms,
    double? overlayWidth,
    double? overlayHeight,
    double? glassOpacity,
    String? glassEffect,
    bool? alwaysOnTop,
    bool? bringToFrontDuringRecording,
    DockVisibilityMode? dockVisibilityMode,
  }) {
    return Settings(
      sampleRate: sampleRate ?? this.sampleRate,
      chunkSizeMs: chunkSizeMs ?? this.chunkSizeMs,
      duckVolumeDuringRecording: duckVolumeDuringRecording ?? this.duckVolumeDuringRecording,
      volumeDuckPercentage: volumeDuckPercentage ?? this.volumeDuckPercentage,
      modelStoragePath: modelStoragePath ?? this.modelStoragePath,
      toggleRecordHotkey: toggleRecordHotkey ?? this.toggleRecordHotkey,
      toggleRecordEnterHotkey: toggleRecordEnterHotkey ?? this.toggleRecordEnterHotkey,
      smartCapitalization: smartCapitalization ?? this.smartCapitalization,
      punctuation: punctuation ?? this.punctuation,
      disfluencyCleanup: disfluencyCleanup ?? this.disfluencyCleanup,
      customTerms: customTerms ?? this.customTerms,
      overlayWidth: overlayWidth ?? this.overlayWidth,
      overlayHeight: overlayHeight ?? this.overlayHeight,
      glassOpacity: glassOpacity ?? this.glassOpacity,
      glassEffect: glassEffect ?? this.glassEffect,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      bringToFrontDuringRecording: bringToFrontDuringRecording ?? this.bringToFrontDuringRecording,
      dockVisibilityMode: dockVisibilityMode ?? this.dockVisibilityMode,
    );
  }
}
