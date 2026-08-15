// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Settings _$SettingsFromJson(Map<String, dynamic> json) => Settings(
  sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 16000,
  chunkSizeMs: (json['chunkSizeMs'] as num?)?.toInt() ?? 30,
  duckVolumeDuringRecording: json['duckVolumeDuringRecording'] as bool? ?? true,
  volumeDuckPercentage:
      (json['volumeDuckPercentage'] as num?)?.toDouble() ?? 0.1,
  skipDuckWhenBluetooth: json['skipDuckWhenBluetooth'] as bool? ?? true,
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
  'modelStoragePath': instance.modelStoragePath,
  'toggleRecordHotkey': instance.toggleRecordHotkey,
  'toggleRecordEnterHotkey': instance.toggleRecordEnterHotkey,
  'smartCapitalization': instance.smartCapitalization,
  'punctuation': instance.punctuation,
  'disfluencyCleanup': instance.disfluencyCleanup,
  'customTerms': instance.customTerms,
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
