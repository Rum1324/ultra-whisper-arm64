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
  final String model;
  final String device;
  final String computeType;
  final bool vad;
  final bool enablePartial;
  final PostProcessingOptions post;
  
  const StartSessionCommand({
    required this.sessionId,
    this.language,
    this.task = 'transcribe',
    required this.model,
    required this.device,
    required this.computeType,
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

  const PostProcessingOptions({
    this.smartCaps = true,
    this.punctuation = true,
    this.disfluencyCleanup = true,
    this.customTerms,
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