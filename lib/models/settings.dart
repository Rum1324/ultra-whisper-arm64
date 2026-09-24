import 'package:json_annotation/json_annotation.dart';

part 'settings.g.dart';

enum DockVisibilityMode {
  menuBarOnly,
  dockOnly,
  both
}

/// A remembered audio output device and the ducking answer chosen for it.
///
/// The Bluetooth heuristic exists only because a device had no identity to hang
/// a decision on: headphones and a Bluetooth speaker share a transport but want
/// opposite answers. Once a device is remembered it gets an explicit answer, and
/// the transport only supplies the value the row starts life with.
@JsonSerializable()
class AudioDevicePref {
  /// CoreAudio device UID. Stable across reconnects, unlike [name].
  final String uid;

  /// Last-seen human-readable name, refreshed whenever the device is used so a
  /// renamed device does not show a stale label in Settings.
  final String name;

  /// Whether the device was on a Bluetooth transport when last seen. Display
  /// only — the decision is [skipDuck].
  final bool isBluetooth;

  /// Skip volume ducking while this device is the output.
  final bool skipDuck;

  const AudioDevicePref({
    required this.uid,
    required this.name,
    required this.isBluetooth,
    required this.skipDuck,
  });

  String get displayName => name.isEmpty ? 'Unknown device' : name;

  AudioDevicePref copyWith({
    String? uid,
    String? name,
    bool? isBluetooth,
    bool? skipDuck,
  }) {
    return AudioDevicePref(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      isBluetooth: isBluetooth ?? this.isBluetooth,
      skipDuck: skipDuck ?? this.skipDuck,
    );
  }

  factory AudioDevicePref.fromJson(Map<String, dynamic> json) =>
      _$AudioDevicePrefFromJson(json);
  Map<String, dynamic> toJson() => _$AudioDevicePrefToJson(this);
}

List<Map<String, dynamic>> _audioDevicePrefsToJson(List<AudioDevicePref> prefs) =>
    prefs.map((pref) => pref.toJson()).toList();

/// Decodes leniently on purpose. The same settings blob arrives both from
/// jsonDecode (`Map<String, dynamic>`) and across a platform channel
/// (`Map<Object?, Object?>`); a strict cast would throw on the latter, and the
/// settings window answers a load failure by falling back to defaults — which
/// the next save would then write over every real setting.
List<AudioDevicePref> _audioDevicePrefsFromJson(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) => AudioDevicePref.fromJson(Map<String, dynamic>.from(entry)))
      .toList();
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

  /// Per-device ducking overrides, keyed by CoreAudio device UID.
  ///
  /// A device is added the first time it is used, seeded from
  /// [skipDuckWhenBluetooth] and its transport. From then on the row wins, so
  /// Bluetooth headphones and a Bluetooth speaker can disagree.
  ///
  /// Encoded explicitly: the settings window is a separate engine reached over
  /// a platform channel, whose codec can carry maps but not AudioDevicePref.
  @JsonKey(toJson: _audioDevicePrefsToJson, fromJson: _audioDevicePrefsFromJson)
  final List<AudioDevicePref> audioDevicePrefs;

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

  /// Leave the transcript on the clipboard after pasting it.
  ///
  /// The paste itself always goes through the clipboard, so the only question
  /// is what sits there once the paste is done. Restoring the previous
  /// contents keeps a copied link or snippet from being clobbered by dictation,
  /// but it also means the transcript is gone the moment you look for it — the
  /// text you just spoke is not recoverable any other way, whereas whatever you
  /// copied by hand usually is.
  final bool keepTranscriptOnClipboard;

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
  ///
  /// Default is Qwen3.6-35B-A3B at Unsloth's Q3_K_XL (~16.8 GB), pulled from
  /// HuggingFace rather than the Ollama library. A 35B mixture-of-experts with
  /// ~3B active gives extraction quality a 5B model cannot while still running
  /// at usable speed. Measured 2026-08-25: gemma4:e2b summarised a transcript
  /// containing an explicit decision, an owned action item and a date, and
  /// captured none of the three.
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
    this.audioDevicePrefs = const [],

    this.modelStoragePath = '',

    this.toggleRecordHotkey = '⌥⇧R',
    this.toggleRecordEnterHotkey = '⌥⇧E',

    this.smartCapitalization = true,
    this.punctuation = true,
    this.disfluencyCleanup = true,
    this.customTerms = const [],
    this.keepTranscriptOnClipboard = true,

    this.meetingAutoDetect = true,
    this.meetingNeverDetectBundleIds = const [],
    this.meetingSummaryModel = 'hf.co/unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q3_K_XL',
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
    List<AudioDevicePref>? audioDevicePrefs,
    String? modelStoragePath,
    String? toggleRecordHotkey,
    String? toggleRecordEnterHotkey,
    bool? smartCapitalization,
    bool? punctuation,
    bool? disfluencyCleanup,
    List<String>? customTerms,
    bool? keepTranscriptOnClipboard,
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
      audioDevicePrefs: audioDevicePrefs ?? this.audioDevicePrefs,
      modelStoragePath: modelStoragePath ?? this.modelStoragePath,
      toggleRecordHotkey: toggleRecordHotkey ?? this.toggleRecordHotkey,
      toggleRecordEnterHotkey: toggleRecordEnterHotkey ?? this.toggleRecordEnterHotkey,
      smartCapitalization: smartCapitalization ?? this.smartCapitalization,
      punctuation: punctuation ?? this.punctuation,
      disfluencyCleanup: disfluencyCleanup ?? this.disfluencyCleanup,
      customTerms: customTerms ?? this.customTerms,
      keepTranscriptOnClipboard:
          keepTranscriptOnClipboard ?? this.keepTranscriptOnClipboard,
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
