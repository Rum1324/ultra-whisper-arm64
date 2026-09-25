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
  modelStoragePath: json['modelStoragePath'] as String? ?? '',
  toggleRecordHotkey: json['toggleRecordHotkey'] as String? ?? '⌥⇧R',
  toggleRecordEnterHotkey: json['toggleRecordEnterHotkey'] as String? ?? '⌥⇧E',
  smartCapitalization: json['smartCapitalization'] as bool? ?? true,
  punctuation: json['punctuation'] as bool? ?? true,
  disfluencyCleanup: json['disfluencyCleanup'] as bool? ?? true,
  customTerms:
      (json['customTerms'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  aiFormatting: json['aiFormatting'] as bool? ?? true,
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
  overlayWidth: (json['overlayWidth'] as num?)?.toDouble() ?? 360.0,
  overlayHeight: (json['overlayHeight'] as num?)?.toDouble() ?? 100.0,
  glassOpacity: (json['glassOpacity'] as num?)?.toDouble() ?? 0.05,
  glassEffect: json['glassEffect'] as String? ?? 'hudWindow',
  alwaysOnTop: json['alwaysOnTop'] as bool? ?? false,
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
  'modelStoragePath': instance.modelStoragePath,
  'toggleRecordHotkey': instance.toggleRecordHotkey,
  'toggleRecordEnterHotkey': instance.toggleRecordEnterHotkey,
  'smartCapitalization': instance.smartCapitalization,
  'punctuation': instance.punctuation,
  'disfluencyCleanup': instance.disfluencyCleanup,
  'customTerms': instance.customTerms,
  'aiFormatting': instance.aiFormatting,
  'keepTranscriptOnClipboard': instance.keepTranscriptOnClipboard,
  'meetingAutoDetect': instance.meetingAutoDetect,
  'meetingNeverDetectBundleIds': instance.meetingNeverDetectBundleIds,
  'meetingSaveDirectory': instance.meetingSaveDirectory,
  'saveMeetingTranscripts': instance.saveMeetingTranscripts,
  'meetingSummaryModel': instance.meetingSummaryModel,
  'overlayWidth': instance.overlayWidth,
  'overlayHeight': instance.overlayHeight,
  'glassOpacity': instance.glassOpacity,
  'glassEffect': instance.glassEffect,
  'alwaysOnTop': instance.alwaysOnTop,
  'bringToFrontDuringRecording': instance.bringToFrontDuringRecording,
  'dockVisibilityMode':
      _$DockVisibilityModeEnumMap[instance.dockVisibilityMode]!,
};

const _$DockVisibilityModeEnumMap = {
  DockVisibilityMode.menuBarOnly: 'menuBarOnly',
  DockVisibilityMode.dockOnly: 'dockOnly',
  DockVisibilityMode.both: 'both',
};
