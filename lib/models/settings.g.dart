// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AudioDevicePref _$AudioDevicePrefFromJson(Map<String, dynamic> json) =>
    AudioDevicePref(
      uid: json['uid'] as String,
      name: json['name'] as String,
      isBluetooth: json['isBluetooth'] as bool,
      skipDuck: json['skipDuck'] as bool,
    );

Map<String, dynamic> _$AudioDevicePrefToJson(AudioDevicePref instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'name': instance.name,
      'isBluetooth': instance.isBluetooth,
      'skipDuck': instance.skipDuck,
    };

Settings _$SettingsFromJson(Map<String, dynamic> json) => Settings(
  sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 16000,
  chunkSizeMs: (json['chunkSizeMs'] as num?)?.toInt() ?? 30,
  duckVolumeDuringRecording: json['duckVolumeDuringRecording'] as bool? ?? true,
  volumeDuckPercentage:
      (json['volumeDuckPercentage'] as num?)?.toDouble() ?? 0.1,
  skipDuckWhenBluetooth: json['skipDuckWhenBluetooth'] as bool? ?? true,
  audioDevicePrefs: json['audioDevicePrefs'] == null
      ? const []
      : _audioDevicePrefsFromJson(json['audioDevicePrefs']),
  speechModelId: json['speechModelId'] as String? ?? kDefaultSpeechModelId,
  setupCompleted: json['setupCompleted'] as bool? ?? false,
  toggleRecordHotkey: json['toggleRecordHotkey'] as String? ?? '⌥⇧R',
  toggleRecordEnterHotkey: json['toggleRecordEnterHotkey'] as String? ?? '⌥⇧E',
  customTerms:
      (json['customTerms'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  aiFormatting: json['aiFormatting'] as bool? ?? true,
  aiFormattingEngine:
      $enumDecodeNullable(
        _$AiFormattingEngineEnumMap,
        json['aiFormattingEngine'],
        unknownValue: AiFormattingEngine.local,
      ) ??
      AiFormattingEngine.local,
  keepTranscriptOnClipboard: json['keepTranscriptOnClipboard'] as bool? ?? true,
  meetingAutoDetect: json['meetingAutoDetect'] as bool? ?? true,
  meetingNeverDetectBundleIds:
      (json['meetingNeverDetectBundleIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  meetingSummaryModel:
      json['meetingSummaryModel'] as String? ??
      'hf.co/unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q3_K_XL',
  meetingSaveDirectory: json['meetingSaveDirectory'] as String? ?? '',
  saveMeetingTranscripts: json['saveMeetingTranscripts'] as bool? ?? true,
  meetingNotes: json['meetingNotes'] as bool? ?? true,
  overlayWidth: (json['overlayWidth'] as num?)?.toDouble() ?? 360.0,
  overlayHeight: (json['overlayHeight'] as num?)?.toDouble() ?? 100.0,
  glassOpacity: (json['glassOpacity'] as num?)?.toDouble() ?? 0.05,
  glassEffect: json['glassEffect'] as String? ?? 'hudWindow',
  alwaysOnTop: json['alwaysOnTop'] as bool? ?? false,
  showDictationOverlay: json['showDictationOverlay'] as bool? ?? true,
  orbExpressiveness:
      $enumDecodeNullable(
        _$OrbExpressivenessEnumMap,
        json['orbExpressiveness'],
      ) ??
      OrbExpressiveness.high,
  bringToFrontDuringRecording:
      json['bringToFrontDuringRecording'] as bool? ?? false,
  dockVisibilityMode:
      $enumDecodeNullable(
        _$DockVisibilityModeEnumMap,
        json['dockVisibilityMode'],
      ) ??
      DockVisibilityMode.menuBarOnly,
);

Map<String, dynamic> _$SettingsToJson(Settings instance) => <String, dynamic>{
  'sampleRate': instance.sampleRate,
  'chunkSizeMs': instance.chunkSizeMs,
  'duckVolumeDuringRecording': instance.duckVolumeDuringRecording,
  'volumeDuckPercentage': instance.volumeDuckPercentage,
  'skipDuckWhenBluetooth': instance.skipDuckWhenBluetooth,
  'audioDevicePrefs': _audioDevicePrefsToJson(instance.audioDevicePrefs),
  'speechModelId': instance.speechModelId,
  'setupCompleted': instance.setupCompleted,
  'toggleRecordHotkey': instance.toggleRecordHotkey,
  'toggleRecordEnterHotkey': instance.toggleRecordEnterHotkey,
  'customTerms': instance.customTerms,
  'aiFormatting': instance.aiFormatting,
  'aiFormattingEngine':
      _$AiFormattingEngineEnumMap[instance.aiFormattingEngine]!,
  'keepTranscriptOnClipboard': instance.keepTranscriptOnClipboard,
  'meetingAutoDetect': instance.meetingAutoDetect,
  'meetingNeverDetectBundleIds': instance.meetingNeverDetectBundleIds,
  'meetingSaveDirectory': instance.meetingSaveDirectory,
  'saveMeetingTranscripts': instance.saveMeetingTranscripts,
  'meetingNotes': instance.meetingNotes,
  'meetingSummaryModel': instance.meetingSummaryModel,
  'overlayWidth': instance.overlayWidth,
  'overlayHeight': instance.overlayHeight,
  'glassOpacity': instance.glassOpacity,
  'glassEffect': instance.glassEffect,
  'alwaysOnTop': instance.alwaysOnTop,
  'showDictationOverlay': instance.showDictationOverlay,
  'orbExpressiveness': _$OrbExpressivenessEnumMap[instance.orbExpressiveness]!,
  'bringToFrontDuringRecording': instance.bringToFrontDuringRecording,
  'dockVisibilityMode':
      _$DockVisibilityModeEnumMap[instance.dockVisibilityMode]!,
};

const _$AiFormattingEngineEnumMap = {
  AiFormattingEngine.local: 'local',
  AiFormattingEngine.claude: 'claude',
};

const _$OrbExpressivenessEnumMap = {
  OrbExpressiveness.low: 'low',
  OrbExpressiveness.high: 'high',
};

const _$DockVisibilityModeEnumMap = {
  DockVisibilityMode.menuBarOnly: 'menuBarOnly',
  DockVisibilityMode.dockOnly: 'dockOnly',
  DockVisibilityMode.both: 'both',
};
