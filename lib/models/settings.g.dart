// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Settings _$SettingsFromJson(Map<String, dynamic> json) => Settings(
  defaultAction:
      $enumDecodeNullable(_$PasteActionEnumMap, json['defaultAction']) ??
      PasteAction.paste,
  inputDevice: json['inputDevice'] as String? ?? 'default',
  sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 16000,
  chunkSizeMs: (json['chunkSizeMs'] as num?)?.toInt() ?? 30,
  model:
      $enumDecodeNullable(_$WhisperModelEnumMap, json['model']) ??
      WhisperModel.largeV3Turbo,
  device:
      $enumDecodeNullable(_$ComputeDeviceEnumMap, json['device']) ??
      ComputeDevice.auto,
  computeType:
      $enumDecodeNullable(_$ComputeTypeEnumMap, json['computeType']) ??
      ComputeType.int8Float32,
  modelStoragePath: json['modelStoragePath'] as String? ?? '',
  autoDetectLanguage: json['autoDetectLanguage'] as bool? ?? true,
  manualLanguage:
      $enumDecodeNullable(_$LanguageEnumMap, json['manualLanguage']) ??
      Language.english,
  holdToTalkHotkey: json['holdToTalkHotkey'] as String? ?? 'Right ⌥',
  toggleRecordHotkey: json['toggleRecordHotkey'] as String? ?? '⌥⇧R',
  loggingLevel: json['loggingLevel'] as String? ?? 'INFO',
  smartCapitalization: json['smartCapitalization'] as bool? ?? true,
  punctuation: json['punctuation'] as bool? ?? true,
  disfluencyCleanup: json['disfluencyCleanup'] as bool? ?? true,
  overlayWidth: (json['overlayWidth'] as num?)?.toDouble() ?? 360.0,
  overlayHeight: (json['overlayHeight'] as num?)?.toDouble() ?? 100.0,
  glassBlurRadius: (json['glassBlurRadius'] as num?)?.toDouble() ?? 20.0,
  glassOpacity: (json['glassOpacity'] as num?)?.toDouble() ?? 0.05,
  glassEffect: json['glassEffect'] as String? ?? 'hudWindow',
  borderOpacity: (json['borderOpacity'] as num?)?.toDouble() ?? 0.2,
  alwaysOnTop: json['alwaysOnTop'] as bool? ?? false,
  bringToFrontDuringRecording:
      json['bringToFrontDuringRecording'] as bool? ?? false,
);

Map<String, dynamic> _$SettingsToJson(Settings instance) => <String, dynamic>{
  'defaultAction': _$PasteActionEnumMap[instance.defaultAction]!,
  'inputDevice': instance.inputDevice,
  'sampleRate': instance.sampleRate,
  'chunkSizeMs': instance.chunkSizeMs,
  'model': _$WhisperModelEnumMap[instance.model]!,
  'device': _$ComputeDeviceEnumMap[instance.device]!,
  'computeType': _$ComputeTypeEnumMap[instance.computeType]!,
  'modelStoragePath': instance.modelStoragePath,
  'autoDetectLanguage': instance.autoDetectLanguage,
  'manualLanguage': _$LanguageEnumMap[instance.manualLanguage]!,
  'holdToTalkHotkey': instance.holdToTalkHotkey,
  'toggleRecordHotkey': instance.toggleRecordHotkey,
  'loggingLevel': instance.loggingLevel,
  'smartCapitalization': instance.smartCapitalization,
  'punctuation': instance.punctuation,
  'disfluencyCleanup': instance.disfluencyCleanup,
  'overlayWidth': instance.overlayWidth,
  'overlayHeight': instance.overlayHeight,
  'glassBlurRadius': instance.glassBlurRadius,
  'glassOpacity': instance.glassOpacity,
  'glassEffect': instance.glassEffect,
  'borderOpacity': instance.borderOpacity,
  'alwaysOnTop': instance.alwaysOnTop,
  'bringToFrontDuringRecording': instance.bringToFrontDuringRecording,
};

const _$PasteActionEnumMap = {
  PasteAction.paste: 'paste',
  PasteAction.pasteWithEnter: 'pasteWithEnter',
  PasteAction.clipboardOnly: 'clipboardOnly',
};

const _$WhisperModelEnumMap = {
  WhisperModel.small: 'small',
  WhisperModel.medium: 'medium',
  WhisperModel.large: 'large',
  WhisperModel.largeV3: 'largeV3',
  WhisperModel.largeV3Turbo: 'largeV3Turbo',
};

const _$ComputeDeviceEnumMap = {
  ComputeDevice.auto: 'auto',
  ComputeDevice.metal: 'metal',
  ComputeDevice.cpu: 'cpu',
};

const _$ComputeTypeEnumMap = {
  ComputeType.int8Float16: 'int8Float16',
  ComputeType.int8Float32: 'int8Float32',
  ComputeType.float16: 'float16',
  ComputeType.int8: 'int8',
  ComputeType.float32: 'float32',
};

const _$LanguageEnumMap = {
  Language.auto: 'auto',
  Language.english: 'english',
  Language.japanese: 'japanese',
};
