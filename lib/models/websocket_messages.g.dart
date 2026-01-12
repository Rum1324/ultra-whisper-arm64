// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'websocket_messages.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MessageEnvelope _$MessageEnvelopeFromJson(Map<String, dynamic> json) =>
    MessageEnvelope(
      type: json['type'] as String,
      id: json['id'] as String?,
      data: json['data'] as Map<String, dynamic>,
    );

Map<String, dynamic> _$MessageEnvelopeToJson(MessageEnvelope instance) =>
    <String, dynamic>{
      'type': instance.type,
      'id': instance.id,
      'data': instance.data,
    };

HelloCommand _$HelloCommandFromJson(Map<String, dynamic> json) => HelloCommand(
  appVersion: json['appVersion'] as String,
  locale: json['locale'] as String,
);

Map<String, dynamic> _$HelloCommandToJson(HelloCommand instance) =>
    <String, dynamic>{
      'appVersion': instance.appVersion,
      'locale': instance.locale,
    };

StartSessionCommand _$StartSessionCommandFromJson(Map<String, dynamic> json) =>
    StartSessionCommand(
      sessionId: json['sessionId'] as String,
      language: json['language'] as String?,
      task: json['task'] as String? ?? 'transcribe',
      model: json['model'] as String,
      device: json['device'] as String,
      computeType: json['computeType'] as String,
      vad: json['vad'] as bool? ?? false,
      enablePartial: json['enablePartial'] as bool? ?? true,
      post: PostProcessingOptions.fromJson(
        json['post'] as Map<String, dynamic>,
      ),
    );

Map<String, dynamic> _$StartSessionCommandToJson(
  StartSessionCommand instance,
) => <String, dynamic>{
  'sessionId': instance.sessionId,
  'language': instance.language,
  'task': instance.task,
  'model': instance.model,
  'device': instance.device,
  'computeType': instance.computeType,
  'vad': instance.vad,
  'enablePartial': instance.enablePartial,
  'post': instance.post,
};

PostProcessingOptions _$PostProcessingOptionsFromJson(
  Map<String, dynamic> json,
) => PostProcessingOptions(
  smartCaps: json['smartCaps'] as bool? ?? true,
  punctuation: json['punctuation'] as bool? ?? true,
  disfluencyCleanup: json['disfluencyCleanup'] as bool? ?? true,
  customTerms: (json['customTerms'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$PostProcessingOptionsToJson(
  PostProcessingOptions instance,
) => <String, dynamic>{
  'smartCaps': instance.smartCaps,
  'punctuation': instance.punctuation,
  'disfluencyCleanup': instance.disfluencyCleanup,
  'customTerms': instance.customTerms,
};

EndSessionCommand _$EndSessionCommandFromJson(Map<String, dynamic> json) =>
    EndSessionCommand(sessionId: json['sessionId'] as String);

Map<String, dynamic> _$EndSessionCommandToJson(EndSessionCommand instance) =>
    <String, dynamic>{'sessionId': instance.sessionId};

CancelCommand _$CancelCommandFromJson(Map<String, dynamic> json) =>
    CancelCommand(sessionId: json['sessionId'] as String);

Map<String, dynamic> _$CancelCommandToJson(CancelCommand instance) =>
    <String, dynamic>{'sessionId': instance.sessionId};

HelloAckEvent _$HelloAckEventFromJson(Map<String, dynamic> json) =>
    HelloAckEvent(
      serverVersion: json['serverVersion'] as String,
      models: (json['models'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      device: json['device'] as String?,
      backend: json['backend'] as String?,
      gpu: json['gpu'] as String?,
    );

Map<String, dynamic> _$HelloAckEventToJson(HelloAckEvent instance) =>
    <String, dynamic>{
      'serverVersion': instance.serverVersion,
      'models': instance.models,
      'device': instance.device,
      'backend': instance.backend,
      'gpu': instance.gpu,
    };

PartialEvent _$PartialEventFromJson(Map<String, dynamic> json) => PartialEvent(
  sessionId: json['session_id'] as String,
  text: json['text'] as String,
  t0: (json['t0'] as num).toDouble(),
  t1: (json['t1'] as num).toDouble(),
);

Map<String, dynamic> _$PartialEventToJson(PartialEvent instance) =>
    <String, dynamic>{
      'session_id': instance.sessionId,
      'text': instance.text,
      't0': instance.t0,
      't1': instance.t1,
    };

TranscriptionSegment _$TranscriptionSegmentFromJson(
  Map<String, dynamic> json,
) => TranscriptionSegment(
  t0: (json['t0'] as num).toDouble(),
  t1: (json['t1'] as num).toDouble(),
  text: json['text'] as String,
);

Map<String, dynamic> _$TranscriptionSegmentToJson(
  TranscriptionSegment instance,
) => <String, dynamic>{
  't0': instance.t0,
  't1': instance.t1,
  'text': instance.text,
};

FinalEvent _$FinalEventFromJson(Map<String, dynamic> json) => FinalEvent(
  sessionId: json['session_id'] as String,
  text: json['text'] as String,
  segments: (json['segments'] as List<dynamic>)
      .map((e) => TranscriptionSegment.fromJson(e as Map<String, dynamic>))
      .toList(),
  lang: json['language'] as String,
  avgLogprob: (json['avg_logprob'] as num).toDouble(),
);

Map<String, dynamic> _$FinalEventToJson(FinalEvent instance) =>
    <String, dynamic>{
      'session_id': instance.sessionId,
      'text': instance.text,
      'segments': instance.segments,
      'language': instance.lang,
      'avg_logprob': instance.avgLogprob,
    };

ErrorEvent _$ErrorEventFromJson(Map<String, dynamic> json) => ErrorEvent(
  sessionId: json['sessionId'] as String?,
  code: json['code'] as String,
  message: json['message'] as String,
);

Map<String, dynamic> _$ErrorEventToJson(ErrorEvent instance) =>
    <String, dynamic>{
      'sessionId': instance.sessionId,
      'code': instance.code,
      'message': instance.message,
    };

StatsEvent _$StatsEventFromJson(Map<String, dynamic> json) => StatsEvent(
  sessionId: json['session_id'] as String,
  rtFactor: (json['rtFactor'] as num).toDouble(),
  tokensPerS: (json['tokensPerS'] as num).toDouble(),
);

Map<String, dynamic> _$StatsEventToJson(StatsEvent instance) =>
    <String, dynamic>{
      'session_id': instance.sessionId,
      'rtFactor': instance.rtFactor,
      'tokensPerS': instance.tokensPerS,
    };
