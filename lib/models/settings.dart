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
  /// Skip ducking when the output device is on a Bluetooth transport — audio
  /// through headphones cannot bleed into the microphone.
  final bool skipDuckWhenBluetooth;

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

  // Meeting settings
  /// Watch for a process that is capturing the mic and playing audio at the
  /// same time, and offer to record it. Off means meetings are started by hand.
  final bool meetingAutoDetect;

  /// Bundle IDs the user answered "Never for this app" to.
  final List<String> meetingNeverDetectBundleIds;

  /// Where meeting transcripts and notes are written when a meeting ends.
  ///
  /// Empty means the default, `~/Documents/UltraWhisper` — resolved lazily so a
  /// stored setting is never silently rewritten by a change of default.
  final String meetingSaveDirectory;

  /// Write the transcript and note to [meetingSaveDirectory] automatically.
  final bool saveMeetingTranscripts;

  /// Ollama tag used for meeting notes. Summarization is the one part of the
  /// app that is not self-contained, and it degrades to a plain transcript when
  /// this model is not pulled — see CLAUDE.md.
  final String meetingSummaryModel;

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
    this.skipDuckWhenBluetooth = true,

    this.modelStoragePath = '',

    this.toggleRecordHotkey = '⌥⇧R',
    this.toggleRecordEnterHotkey = '⌥⇧E',

    this.smartCapitalization = true,
    this.punctuation = true,
    this.disfluencyCleanup = true,
    this.customTerms = const [],

    this.meetingAutoDetect = true,
    this.meetingNeverDetectBundleIds = const [],
    this.meetingSummaryModel = 'gemma4:e2b',
    this.meetingSaveDirectory = '',
    this.saveMeetingTranscripts = true,

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
    bool? skipDuckWhenBluetooth,
    String? modelStoragePath,
    String? toggleRecordHotkey,
    String? toggleRecordEnterHotkey,
    bool? smartCapitalization,
    bool? punctuation,
    bool? disfluencyCleanup,
    List<String>? customTerms,
    bool? meetingAutoDetect,
    List<String>? meetingNeverDetectBundleIds,
    String? meetingSummaryModel,
    String? meetingSaveDirectory,
    bool? saveMeetingTranscripts,
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
      skipDuckWhenBluetooth: skipDuckWhenBluetooth ?? this.skipDuckWhenBluetooth,
      modelStoragePath: modelStoragePath ?? this.modelStoragePath,
      toggleRecordHotkey: toggleRecordHotkey ?? this.toggleRecordHotkey,
      toggleRecordEnterHotkey: toggleRecordEnterHotkey ?? this.toggleRecordEnterHotkey,
      smartCapitalization: smartCapitalization ?? this.smartCapitalization,
      punctuation: punctuation ?? this.punctuation,
      disfluencyCleanup: disfluencyCleanup ?? this.disfluencyCleanup,
      customTerms: customTerms ?? this.customTerms,
      meetingAutoDetect: meetingAutoDetect ?? this.meetingAutoDetect,
      meetingNeverDetectBundleIds:
          meetingNeverDetectBundleIds ?? this.meetingNeverDetectBundleIds,
      meetingSummaryModel: meetingSummaryModel ?? this.meetingSummaryModel,
      meetingSaveDirectory: meetingSaveDirectory ?? this.meetingSaveDirectory,
      saveMeetingTranscripts:
          saveMeetingTranscripts ?? this.saveMeetingTranscripts,
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
