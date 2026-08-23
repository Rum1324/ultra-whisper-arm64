import 'package:flutter/foundation.dart';

import '../models/websocket_messages.dart';
import '../utils/logger.dart';

/// Audio track tags, matching byte 0 of a meeting audio frame.
///
/// Attribution is physical, not inferred: the mic is "me", the system capture
/// is "them". There is no diarization anywhere in UltraWhisper, and this is the
/// entire reason a meeting is captured as two tracks.
class MeetingTrack {
  static const int mic = 0x00;
  static const int system = 0x01;
}

/// Where a meeting is in its lifecycle.
///
/// [summaryUnavailable] is deliberately not an error state. Summarization is an
/// enhancement layered on a transcript that already works, so Ollama being
/// absent must leave the transcript intact and must not read as a failure.
enum MeetingPhase {
  idle,
  recording,
  ended,
  summarizing,
  summarized,
  summaryUnavailable,
}

/// Client half of the meeting protocol.
///
/// See docs/MEETING_PROTOCOL.md. This owns meeting state and message shaping
/// only — the transports are injected, so it neither opens a socket nor knows
/// one exists. That keeps the protocol testable without a backend, which is
/// what test/meeting_service_test.dart relies on.
class MeetingService extends ChangeNotifier {
  MeetingService({required this.sendJson, required this.sendBinary});

  /// Sends one `{type, id, data}` envelope.
  final void Function(Map<String, dynamic> envelope) sendJson;

  /// Sends one raw binary frame.
  final void Function(Uint8List frame) sendBinary;

  String? _meetingId;
  MeetingPhase _phase = MeetingPhase.idle;
  final List<TranscriptSegment> _transcript = [];
  int _lastWindowIndex = -1;
  SummaryProgressEvent? _progress;
  SummaryFinalEvent? _summary;
  SummaryUnavailableEvent? _unavailable;
  String? _error;

  String? get meetingId => _meetingId;
  MeetingPhase get phase => _phase;

  /// Every segment so far, in meeting order.
  List<TranscriptSegment> get transcript => List.unmodifiable(_transcript);

  SummaryProgressEvent? get progress => _progress;
  SummaryFinalEvent? get summary => _summary;
  SummaryUnavailableEvent? get unavailable => _unavailable;
  String? get error => _error;

  bool get isRecording => _phase == MeetingPhase.recording;

  /// Whether a transcript exists to summarize. `end_meeting` deliberately keeps
  /// the session alive for exactly this; only `cancel` frees it.
  bool get canSummarize =>
      _meetingId != null &&
      _transcript.isNotEmpty &&
      _phase != MeetingPhase.recording &&
      _phase != MeetingPhase.summarizing;

  /// The transcript as speaker-labelled lines.
  String get transcriptText => _transcript
      .map((s) => '[${_stamp(s.t0)}] ${s.isMe ? 'Me' : 'Them'}: ${s.text}')
      .join('\n');

  static String _stamp(double seconds) {
    final total = seconds < 0 ? 0 : seconds.floor();
    final h = (total ~/ 3600).toString().padLeft(2, '0');
    final m = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // -- commands -------------------------------------------------------------

  /// Begin a meeting. Safe to leave open for hours: the backend retains stamped
  /// text and discards the audio as it goes.
  void start({
    required String meetingId,
    String meetingType = 'generic',
    String? language,
    String? title,
    int windowSeconds = 120,
  }) {
    _meetingId = meetingId;
    _phase = MeetingPhase.recording;
    _transcript.clear();
    _lastWindowIndex = -1;
    _progress = null;
    _summary = null;
    _unavailable = null;
    _error = null;

    _send('start_meeting', StartMeetingCommand(
      meetingId: meetingId,
      meetingType: meetingType,
      language: language,
      title: title,
      windowSeconds: windowSeconds,
    ).toJson());

    notifyListeners();
  }

  /// Send one chunk of microphone audio: PCM int16 LE, mono, 16 kHz.
  void sendMicAudio(Uint8List pcm) => _sendAudio(MeetingTrack.mic, pcm);

  /// Send one chunk of system audio, same format.
  void sendSystemAudio(Uint8List pcm) => _sendAudio(MeetingTrack.system, pcm);

  void _sendAudio(int track, Uint8List pcm) {
    if (_phase != MeetingPhase.recording || _meetingId == null) return;
    if (pcm.isEmpty) return;

    // One leading track byte, then the PCM. A byte rather than a JSON sidecar
    // because these arrive every 20-40ms for the length of a meeting; the
    // framing cost matters and the tag never carries anything else.
    final frame = Uint8List(pcm.length + 1);
    frame[0] = track;
    frame.setRange(1, frame.length, pcm);
    sendBinary(frame);
  }

  /// Stop recording. The transcript stays available for [summarize].
  void end() {
    final id = _meetingId;
    if (id == null || _phase != MeetingPhase.recording) return;

    _phase = MeetingPhase.ended;
    _send('end_meeting', EndMeetingCommand(meetingId: id).toJson());
    notifyListeners();
  }

  /// Generate notes. Safe to call more than once, including with a different
  /// model — that is the intended way to retry after a weak note.
  void summarize({required String model, String? meetingType}) {
    final id = _meetingId;
    if (id == null || _phase == MeetingPhase.recording) return;

    _phase = MeetingPhase.summarizing;
    _progress = null;
    _summary = null;
    _unavailable = null;

    _send('summarize', SummarizeCommand(
      meetingId: id,
      model: model,
      meetingType: meetingType,
    ).toJson());

    notifyListeners();
  }

  /// Drop the meeting and its retained transcript.
  void cancel() {
    final id = _meetingId;
    if (id == null) return;

    _send('cancel', CancelMeetingCommand(meetingId: id).toJson());
    _reset();
    notifyListeners();
  }

  void _reset() {
    _meetingId = null;
    _phase = MeetingPhase.idle;
    _transcript.clear();
    _lastWindowIndex = -1;
    _progress = null;
    _summary = null;
    _unavailable = null;
    _error = null;
  }

  void _send(String type, Map<String, dynamic> data) {
    sendJson({'type': type, 'id': _messageId(), 'data': data});
  }

  int _counter = 0;
  String _messageId() => '${_meetingId ?? 'meeting'}-${_counter++}';

  // -- events ---------------------------------------------------------------

  /// Handle one backend event.
  ///
  /// Returns whether it belonged to this meeting, so the caller's dispatch can
  /// fall through to the dictation handlers for everything else.
  bool handleEvent(String type, Map<String, dynamic> data) {
    // A stale event from a cancelled or superseded meeting is not ours. Without
    // this a late window from a previous meeting would append to the new one's
    // transcript.
    final id = data['meetingId'];
    if (id is String && _meetingId != null && id != _meetingId) {
      AppLogger.debug('Ignoring $type for stale meeting $id');
      return true;
    }

    switch (type) {
      case 'meeting_started':
        return true;

      case 'transcript_window':
        _onWindow(TranscriptWindowEvent.fromJson(data));
        return true;

      case 'meeting_ended':
        if (_phase == MeetingPhase.recording) _phase = MeetingPhase.ended;
        notifyListeners();
        return true;

      case 'summary_progress':
        _progress = SummaryProgressEvent.fromJson(data);
        notifyListeners();
        return true;

      case 'summary_final':
        _summary = SummaryFinalEvent.fromJson(data);
        _progress = null;
        _phase = MeetingPhase.summarized;
        notifyListeners();
        return true;

      case 'summary_unavailable':
        // Not a failure. The transcript is untouched and stays on screen; the
        // UI states that notes are unavailable and offers `remedy` verbatim.
        _unavailable = SummaryUnavailableEvent.fromJson(data);
        _progress = null;
        _phase = MeetingPhase.summaryUnavailable;
        AppLogger.warning('Meeting notes unavailable: ${_unavailable!.detail}');
        notifyListeners();
        return true;

      case 'error':
        // Only claim errors carrying our meetingId; dictation errors are not
        // ours to swallow.
        if (id is String && id == _meetingId) {
          _error = (data['message'] ?? 'Unknown meeting error').toString();
          notifyListeners();
          return true;
        }
        return false;
    }
    return false;
  }

  void _onWindow(TranscriptWindowEvent window) {
    // Windows arrive in order and each is emitted once. Guarding on the index
    // keeps the transcript monotonic if one is ever replayed.
    if (window.index <= _lastWindowIndex) {
      AppLogger.debug('Ignoring replayed window ${window.index}');
      return;
    }
    _lastWindowIndex = window.index;
    _transcript.addAll(window.segments);
    notifyListeners();
  }
}
