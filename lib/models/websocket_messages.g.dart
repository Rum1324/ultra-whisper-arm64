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
  aiFormatting: json['aiFormatting'] as bool? ?? false,
);

Map<String, dynamic> _$PostProcessingOptionsToJson(
  PostProcessingOptions instance,
) => <String, dynamic>{
  'smartCaps': instance.smartCaps,
  'punctuation': instance.punctuation,
  'disfluencyCleanup': instance.disfluencyCleanup,
  'customTerms': instance.customTerms,
  'aiFormatting': instance.aiFormatting,
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

StartMeetingCommand _$StartMeetingCommandFromJson(Map<String, dynamic> json) =>
    StartMeetingCommand(
      meetingId: json['meetingId'] as String,
      meetingType: json['meetingType'] as String? ?? 'generic',
      language: json['language'] as String?,
      title: json['title'] as String?,
      windowSeconds: (json['windowSeconds'] as num?)?.toInt() ?? 120,
    );

Map<String, dynamic> _$StartMeetingCommandToJson(
  StartMeetingCommand instance,
) => <String, dynamic>{
  'meetingId': instance.meetingId,
  'meetingType': instance.meetingType,
  'language': instance.language,
  'title': instance.title,
  'windowSeconds': instance.windowSeconds,
};

EndMeetingCommand _$EndMeetingCommandFromJson(Map<String, dynamic> json) =>
    EndMeetingCommand(meetingId: json['meetingId'] as String);

Map<String, dynamic> _$EndMeetingCommandToJson(EndMeetingCommand instance) =>
    <String, dynamic>{'meetingId': instance.meetingId};

SummarizeCommand _$SummarizeCommandFromJson(Map<String, dynamic> json) =>
    SummarizeCommand(
      meetingId: json['meetingId'] as String,
      model: json['model'] as String,
      meetingType: json['meetingType'] as String?,
    );

Map<String, dynamic> _$SummarizeCommandToJson(SummarizeCommand instance) =>
    <String, dynamic>{
      'meetingId': instance.meetingId,
      'model': instance.model,
      'meetingType': instance.meetingType,
    };

CancelMeetingCommand _$CancelMeetingCommandFromJson(
  Map<String, dynamic> json,
) => CancelMeetingCommand(meetingId: json['meetingId'] as String);

Map<String, dynamic> _$CancelMeetingCommandToJson(
  CancelMeetingCommand instance,
) => <String, dynamic>{'meetingId': instance.meetingId};

MeetingStartedEvent _$MeetingStartedEventFromJson(Map<String, dynamic> json) =>
    MeetingStartedEvent(
      meetingId: json['meetingId'] as String,
      meetingType: json['meetingType'] as String,
      windowSeconds: (json['windowSeconds'] as num).toInt(),
      status: json['status'] as String,
    );

Map<String, dynamic> _$MeetingStartedEventToJson(
  MeetingStartedEvent instance,
) => <String, dynamic>{
  'meetingId': instance.meetingId,
  'meetingType': instance.meetingType,
  'windowSeconds': instance.windowSeconds,
  'status': instance.status,
};

MeetingEndedEvent _$MeetingEndedEventFromJson(Map<String, dynamic> json) =>
    MeetingEndedEvent(
      meetingId: json['meetingId'] as String,
      segments: (json['segments'] as num).toInt(),
    );

Map<String, dynamic> _$MeetingEndedEventToJson(MeetingEndedEvent instance) =>
    <String, dynamic>{
      'meetingId': instance.meetingId,
      'segments': instance.segments,
    };

TranscriptSegment _$TranscriptSegmentFromJson(Map<String, dynamic> json) =>
    TranscriptSegment(
      t0: (json['t0'] as num).toDouble(),
      t1: (json['t1'] as num).toDouble(),
      speaker: json['speaker'] as String,
      text: json['text'] as String,
    );

Map<String, dynamic> _$TranscriptSegmentToJson(TranscriptSegment instance) =>
    <String, dynamic>{
      't0': instance.t0,
      't1': instance.t1,
      'speaker': instance.speaker,
      'text': instance.text,
    };

TranscriptWindowEvent _$TranscriptWindowEventFromJson(
  Map<String, dynamic> json,
) => TranscriptWindowEvent(
  meetingId: json['meetingId'] as String,
  index: (json['index'] as num).toInt(),
  t0: (json['t0'] as num).toDouble(),
  t1: (json['t1'] as num).toDouble(),
  segments: (json['segments'] as List<dynamic>)
      .map((e) => TranscriptSegment.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$TranscriptWindowEventToJson(
  TranscriptWindowEvent instance,
) => <String, dynamic>{
  'meetingId': instance.meetingId,
  'index': instance.index,
  't0': instance.t0,
  't1': instance.t1,
  'segments': instance.segments,
};

SummaryProgressEvent _$SummaryProgressEventFromJson(
  Map<String, dynamic> json,
) => SummaryProgressEvent(
  meetingId: json['meetingId'] as String,
  stage: json['stage'] as String,
  completed: (json['completed'] as num).toInt(),
  total: (json['total'] as num).toInt(),
);

Map<String, dynamic> _$SummaryProgressEventToJson(
  SummaryProgressEvent instance,
) => <String, dynamic>{
  'meetingId': instance.meetingId,
  'stage': instance.stage,
  'completed': instance.completed,
  'total': instance.total,
};

NoteItem _$NoteItemFromJson(Map<String, dynamic> json) => NoteItem(
  text: json['text'] as String,
  children:
      (json['children'] as List<dynamic>?)
          ?.map((e) => NoteItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$NoteItemToJson(NoteItem instance) => <String, dynamic>{
  'text': instance.text,
  'children': instance.children,
};

NoteSection _$NoteSectionFromJson(Map<String, dynamic> json) => NoteSection(
  title: json['title'] as String,
  style: json['style'] as String? ?? 'bullet',
  items:
      (json['items'] as List<dynamic>?)
          ?.map((e) => NoteItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$NoteSectionToJson(NoteSection instance) =>
    <String, dynamic>{
      'title': instance.title,
      'style': instance.style,
      'items': instance.items,
    };

MeetingNote _$MeetingNoteFromJson(Map<String, dynamic> json) => MeetingNote(
  title: json['title'] as String,
  meetingType: json['meetingType'] as String,
  sections:
      (json['sections'] as List<dynamic>?)
          ?.map((e) => NoteSection.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$MeetingNoteToJson(MeetingNote instance) =>
    <String, dynamic>{
      'title': instance.title,
      'meetingType': instance.meetingType,
      'sections': instance.sections,
    };

SummaryFinalEvent _$SummaryFinalEventFromJson(Map<String, dynamic> json) =>
    SummaryFinalEvent(
      meetingId: json['meetingId'] as String,
      markdown: json['markdown'] as String,
      note: MeetingNote.fromJson(json['note'] as Map<String, dynamic>),
      model: json['model'] as String,
      elapsedSeconds: (json['elapsedSeconds'] as num).toDouble(),
    );

Map<String, dynamic> _$SummaryFinalEventToJson(SummaryFinalEvent instance) =>
    <String, dynamic>{
      'meetingId': instance.meetingId,
      'markdown': instance.markdown,
      'note': instance.note,
      'model': instance.model,
      'elapsedSeconds': instance.elapsedSeconds,
    };

SummaryUnavailableEvent _$SummaryUnavailableEventFromJson(
  Map<String, dynamic> json,
) => SummaryUnavailableEvent(
  meetingId: json['meetingId'] as String,
  reason: json['reason'] as String,
  detail: json['detail'] as String,
  remedy: json['remedy'] as String?,
);

Map<String, dynamic> _$SummaryUnavailableEventToJson(
  SummaryUnavailableEvent instance,
) => <String, dynamic>{
  'meetingId': instance.meetingId,
  'reason': instance.reason,
  'detail': instance.detail,
  'remedy': instance.remedy,
};
