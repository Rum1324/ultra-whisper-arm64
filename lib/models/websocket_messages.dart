import 'package:json_annotation/json_annotation.dart';

part 'websocket_messages.g.dart';

@JsonSerializable()
class MessageEnvelope {
  final String type;
  final String? id;
  final Map<String, dynamic> data;
  
  const MessageEnvelope({
    required this.type,
    this.id,
    required this.data,
  });
  
  factory MessageEnvelope.fromJson(Map<String, dynamic> json) => _$MessageEnvelopeFromJson(json);
  Map<String, dynamic> toJson() => _$MessageEnvelopeToJson(this);
}

@JsonSerializable()
class HelloCommand {
  final String appVersion;
  final String locale;
  
  const HelloCommand({
    required this.appVersion,
    required this.locale,
  });
  
  factory HelloCommand.fromJson(Map<String, dynamic> json) => _$HelloCommandFromJson(json);
  Map<String, dynamic> toJson() => _$HelloCommandToJson(this);
}

@JsonSerializable()
class StartSessionCommand {
  final String sessionId;
  final String? language;
  final String task;
  final bool vad;
  final bool enablePartial;
  final PostProcessingOptions post;

  const StartSessionCommand({
    required this.sessionId,
    this.language,
    this.task = 'transcribe',
    this.vad = false,
    this.enablePartial = true,
    required this.post,
  });
  
  factory StartSessionCommand.fromJson(Map<String, dynamic> json) => _$StartSessionCommandFromJson(json);
  Map<String, dynamic> toJson() => _$StartSessionCommandToJson(this);
}

@JsonSerializable()
class PostProcessingOptions {
  final bool smartCaps;
  final bool punctuation;
  final bool disfluencyCleanup;
  final List<String>? customTerms; // Custom dictionary for domain-specific terms
  /// Clean up the transcript with a local LLM via Ollama after the rule pass.
  final bool aiFormatting;

  const PostProcessingOptions({
    this.smartCaps = true,
    this.punctuation = true,
    this.disfluencyCleanup = true,
    this.customTerms,
    this.aiFormatting = false,
  });

  factory PostProcessingOptions.fromJson(Map<String, dynamic> json) => _$PostProcessingOptionsFromJson(json);
  Map<String, dynamic> toJson() => _$PostProcessingOptionsToJson(this);
}

@JsonSerializable()
class EndSessionCommand {
  final String sessionId;
  
  const EndSessionCommand({
    required this.sessionId,
  });
  
  factory EndSessionCommand.fromJson(Map<String, dynamic> json) => _$EndSessionCommandFromJson(json);
  Map<String, dynamic> toJson() => _$EndSessionCommandToJson(this);
}

@JsonSerializable()
class CancelCommand {
  final String sessionId;
  
  const CancelCommand({
    required this.sessionId,
  });
  
  factory CancelCommand.fromJson(Map<String, dynamic> json) => _$CancelCommandFromJson(json);
  Map<String, dynamic> toJson() => _$CancelCommandToJson(this);
}

@JsonSerializable()
class HelloAckEvent {
  final String serverVersion;
  final List<String> models;
  final String? device;
  final String? backend;
  final String? gpu;

  const HelloAckEvent({
    required this.serverVersion,
    required this.models,
    this.device,
    this.backend,
    this.gpu,
  });

  factory HelloAckEvent.fromJson(Map<String, dynamic> json) => _$HelloAckEventFromJson(json);
  Map<String, dynamic> toJson() => _$HelloAckEventToJson(this);
}

@JsonSerializable()
class PartialEvent {
  @JsonKey(name: 'session_id')
  final String sessionId;
  final String text;
  final double t0;
  final double t1;
  
  const PartialEvent({
    required this.sessionId,
    required this.text,
    required this.t0,
    required this.t1,
  });
  
  factory PartialEvent.fromJson(Map<String, dynamic> json) => _$PartialEventFromJson(json);
  Map<String, dynamic> toJson() => _$PartialEventToJson(this);
}

@JsonSerializable()
class TranscriptionSegment {
  final double t0;
  final double t1;
  final String text;
  
  const TranscriptionSegment({
    required this.t0,
    required this.t1,
    required this.text,
  });
  
  factory TranscriptionSegment.fromJson(Map<String, dynamic> json) => _$TranscriptionSegmentFromJson(json);
  Map<String, dynamic> toJson() => _$TranscriptionSegmentToJson(this);
}

@JsonSerializable()
class FinalEvent {
  @JsonKey(name: 'session_id')
  final String sessionId;
  final String text;
  final List<TranscriptionSegment> segments;
  @JsonKey(name: 'language')
  final String lang;
  @JsonKey(name: 'avg_logprob')
  final double avgLogprob;
  
  const FinalEvent({
    required this.sessionId,
    required this.text,
    required this.segments,
    required this.lang,
    required this.avgLogprob,
  });
  
  factory FinalEvent.fromJson(Map<String, dynamic> json) => _$FinalEventFromJson(json);
  Map<String, dynamic> toJson() => _$FinalEventToJson(this);
}

@JsonSerializable()
class ErrorEvent {
  final String? sessionId;
  final String code;
  final String message;
  
  const ErrorEvent({
    this.sessionId,
    required this.code,
    required this.message,
  });
  
  factory ErrorEvent.fromJson(Map<String, dynamic> json) => _$ErrorEventFromJson(json);
  Map<String, dynamic> toJson() => _$ErrorEventToJson(this);
}

@JsonSerializable()
class StatsEvent {
  @JsonKey(name: 'session_id')
  final String sessionId;
  final double rtFactor;
  final double tokensPerS;
  
  const StatsEvent({
    required this.sessionId,
    required this.rtFactor,
    required this.tokensPerS,
  });
  
  factory StatsEvent.fromJson(Map<String, dynamic> json) => _$StatsEventFromJson(json);
  Map<String, dynamic> toJson() => _$StatsEventToJson(this);
}
// ---------------------------------------------------------------------------
// Meeting sessions
//
// See docs/MEETING_PROTOCOL.md. These are camelCase in both directions, unlike
// the legacy `final`/`stats` events above, which carry `session_id` and
// `avg_logprob` and need @JsonKey to paper over it. That inconsistency is not
// propagated here; the legacy fields stay exactly as they are.
// ---------------------------------------------------------------------------

@JsonSerializable()
class StartMeetingCommand {
  final String meetingId;

  /// See backend/summarize/templates.py; 'generic' when unknown.
  final String meetingType;

  /// null means auto-detect.
  final String? language;

  /// Optional, from the calendar match.
  final String? title;

  /// Rolling transcribe window.
  final int windowSeconds;

  const StartMeetingCommand({
    required this.meetingId,
    this.meetingType = 'generic',
    this.language,
    this.title,
    this.windowSeconds = 120,
  });

  factory StartMeetingCommand.fromJson(Map<String, dynamic> json) => _$StartMeetingCommandFromJson(json);
  Map<String, dynamic> toJson() => _$StartMeetingCommandToJson(this);
}

@JsonSerializable()
class EndMeetingCommand {
  final String meetingId;

  const EndMeetingCommand({required this.meetingId});

  factory EndMeetingCommand.fromJson(Map<String, dynamic> json) => _$EndMeetingCommandFromJson(json);
  Map<String, dynamic> toJson() => _$EndMeetingCommandToJson(this);
}

@JsonSerializable()
class SummarizeCommand {
  final String meetingId;

  /// Ollama tag; a user setting.
  final String model;

  /// Optional override of the start_meeting value.
  final String? meetingType;

  const SummarizeCommand({
    required this.meetingId,
    required this.model,
    this.meetingType,
  });

  factory SummarizeCommand.fromJson(Map<String, dynamic> json) => _$SummarizeCommandFromJson(json);
  Map<String, dynamic> toJson() => _$SummarizeCommandToJson(this);
}

@JsonSerializable()
class CancelMeetingCommand {
  final String meetingId;

  const CancelMeetingCommand({required this.meetingId});

  factory CancelMeetingCommand.fromJson(Map<String, dynamic> json) => _$CancelMeetingCommandFromJson(json);
  Map<String, dynamic> toJson() => _$CancelMeetingCommandToJson(this);
}

@JsonSerializable()
class MeetingStartedEvent {
  final String meetingId;
  final String meetingType;
  final int windowSeconds;
  final String status;

  const MeetingStartedEvent({
    required this.meetingId,
    required this.meetingType,
    required this.windowSeconds,
    required this.status,
  });

  factory MeetingStartedEvent.fromJson(Map<String, dynamic> json) => _$MeetingStartedEventFromJson(json);
  Map<String, dynamic> toJson() => _$MeetingStartedEventToJson(this);
}

@JsonSerializable()
class MeetingEndedEvent {
  final String meetingId;

  /// How many segments the transcript holds.
  final int segments;

  const MeetingEndedEvent({required this.meetingId, required this.segments});

  factory MeetingEndedEvent.fromJson(Map<String, dynamic> json) => _$MeetingEndedEventFromJson(json);
  Map<String, dynamic> toJson() => _$MeetingEndedEventToJson(this);
}

/// One utterance. `speaker` is 'me' (mic) or 'them' (system capture) — physical
/// attribution from the two-track capture, not diarization.
@JsonSerializable()
class TranscriptSegment {
  /// Absolute seconds from the start of the meeting, monotonic across windows.
  final double t0;
  final double t1;
  final String speaker;
  final String text;

  const TranscriptSegment({
    required this.t0,
    required this.t1,
    required this.speaker,
    required this.text,
  });

  bool get isMe => speaker == 'me';

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) => _$TranscriptSegmentFromJson(json);
  Map<String, dynamic> toJson() => _$TranscriptSegmentToJson(this);
}

@JsonSerializable()
class TranscriptWindowEvent {
  final String meetingId;
  final int index;
  final double t0;
  final double t1;
  final List<TranscriptSegment> segments;

  const TranscriptWindowEvent({
    required this.meetingId,
    required this.index,
    required this.t0,
    required this.t1,
    required this.segments,
  });

  factory TranscriptWindowEvent.fromJson(Map<String, dynamic> json) => _$TranscriptWindowEventFromJson(json);
  Map<String, dynamic> toJson() => _$TranscriptWindowEventToJson(this);
}

@JsonSerializable()
class SummaryProgressEvent {
  final String meetingId;

  /// 'classify' | 'map' | 'reduce' | 'render'
  final String stage;
  final int completed;
  final int total;

  const SummaryProgressEvent({
    required this.meetingId,
    required this.stage,
    required this.completed,
    required this.total,
  });

  double get fraction => total <= 0 ? 0 : completed / total;

  factory SummaryProgressEvent.fromJson(Map<String, dynamic> json) => _$SummaryProgressEventFromJson(json);
  Map<String, dynamic> toJson() => _$SummaryProgressEventToJson(this);
}

@JsonSerializable()
class NoteItem {
  final String text;
  final List<NoteItem> children;

  const NoteItem({required this.text, this.children = const []});

  factory NoteItem.fromJson(Map<String, dynamic> json) => _$NoteItemFromJson(json);
  Map<String, dynamic> toJson() => _$NoteItemToJson(this);
}

@JsonSerializable()
class NoteSection {
  final String title;

  /// 'bullet' | 'checkbox'
  final String style;
  final List<NoteItem> items;

  const NoteSection({
    required this.title,
    this.style = 'bullet',
    this.items = const [],
  });

  factory NoteSection.fromJson(Map<String, dynamic> json) => _$NoteSectionFromJson(json);
  Map<String, dynamic> toJson() => _$NoteSectionToJson(this);
}

@JsonSerializable()
class MeetingNote {
  final String title;
  final String meetingType;
  final List<NoteSection> sections;

  const MeetingNote({
    required this.title,
    required this.meetingType,
    this.sections = const [],
  });

  factory MeetingNote.fromJson(Map<String, dynamic> json) => _$MeetingNoteFromJson(json);
  Map<String, dynamic> toJson() => _$MeetingNoteToJson(this);
}

@JsonSerializable()
class SummaryFinalEvent {
  final String meetingId;

  /// The deliverable, and what the UI shows.
  final String markdown;

  /// The structure behind the markdown, carried so per-section actions do not
  /// need a markdown re-parse.
  final MeetingNote note;
  final String model;
  final double elapsedSeconds;

  const SummaryFinalEvent({
    required this.meetingId,
    required this.markdown,
    required this.note,
    required this.model,
    required this.elapsedSeconds,
  });

  factory SummaryFinalEvent.fromJson(Map<String, dynamic> json) => _$SummaryFinalEventFromJson(json);
  Map<String, dynamic> toJson() => _$SummaryFinalEventToJson(this);
}

/// NOT an error. Summarization is layered on a transcript that already works,
/// so the UI shows the transcript, states that notes are unavailable, and
/// offers [remedy] as copyable text. It must not read as a failed operation.
@JsonSerializable()
class SummaryUnavailableEvent {
  final String meetingId;

  /// 'no_server' | 'no_model' | 'timeout' | 'bad_response'
  final String reason;
  final String detail;

  /// Safe to show verbatim; may be null.
  final String? remedy;

  const SummaryUnavailableEvent({
    required this.meetingId,
    required this.reason,
    required this.detail,
    this.remedy,
  });

  factory SummaryUnavailableEvent.fromJson(Map<String, dynamic> json) => _$SummaryUnavailableEventFromJson(json);
  Map<String, dynamic> toJson() => _$SummaryUnavailableEventToJson(this);
}
