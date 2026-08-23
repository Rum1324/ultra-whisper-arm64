import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultrawhisper/services/meeting_service.dart';

/// Captures what the service would have put on the wire.
class _Wire {
  final List<Map<String, dynamic>> json = [];
  final List<Uint8List> binary = [];

  List<Map<String, dynamic>> ofType(String type) =>
      json.where((m) => m['type'] == type).toList();

  Map<String, dynamic> dataOf(String type) =>
      ofType(type).first['data'] as Map<String, dynamic>;
}

({MeetingService service, _Wire wire}) _build() {
  final wire = _Wire();
  final service = MeetingService(
    sendJson: wire.json.add,
    sendBinary: wire.binary.add,
  );
  return (service: service, wire: wire);
}

Uint8List _pcm(int samples, [int value = 7]) =>
    Uint8List.fromList(List.filled(samples * 2, value));

Map<String, dynamic> _window(
  int index, {
  String meetingId = 'm1',
  List<Map<String, dynamic>>? segments,
}) =>
    {
      'meetingId': meetingId,
      'index': index,
      't0': index * 120.0,
      't1': (index + 1) * 120.0,
      'segments': segments ??
          [
            {'t0': index * 120.0 + 1, 't1': index * 120.0 + 2, 'speaker': 'me', 'text': 'mine $index'},
            {'t0': index * 120.0 + 3, 't1': index * 120.0 + 4, 'speaker': 'them', 'text': 'theirs $index'},
          ],
    };

void main() {
  group('commands', () {
    test('start emits start_meeting with the protocol fields', () {
      final t = _build();
      t.service.start(
        meetingId: 'm1',
        meetingType: 'coffee_chat',
        title: 'Coffee chat with Ana',
        windowSeconds: 120,
      );

      final data = t.wire.dataOf('start_meeting');
      expect(data['meetingId'], 'm1');
      expect(data['meetingType'], 'coffee_chat');
      expect(data['title'], 'Coffee chat with Ana');
      expect(data['windowSeconds'], 120);
      expect(data['language'], isNull, reason: 'null means auto-detect');
      expect(t.service.phase, MeetingPhase.recording);
    });

    test('audio frames carry a leading track byte', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.sendMicAudio(_pcm(4));
      t.service.sendSystemAudio(_pcm(4));

      expect(t.wire.binary, hasLength(2));
      expect(t.wire.binary[0][0], MeetingTrack.mic);
      expect(t.wire.binary[1][0], MeetingTrack.system);
      expect(t.wire.binary[0].length, 4 * 2 + 1, reason: 'one tag byte plus PCM');
    });

    test('the track byte does not corrupt the PCM behind it', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      final pcm = Uint8List.fromList([1, 2, 3, 4]);
      t.service.sendMicAudio(pcm);

      expect(t.wire.binary.single.sublist(1), orderedEquals(pcm));
    });

    test('audio outside a recording meeting is dropped', () {
      final t = _build();
      t.service.sendMicAudio(_pcm(4));
      expect(t.wire.binary, isEmpty);

      t.service.start(meetingId: 'm1');
      t.service.end();
      t.service.sendMicAudio(_pcm(4));
      expect(t.wire.binary, isEmpty, reason: 'the meeting is no longer recording');
    });

    test('end emits end_meeting and leaves the transcript intact', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.handleEvent('transcript_window', _window(0));
      t.service.end();

      expect(t.wire.dataOf('end_meeting')['meetingId'], 'm1');
      expect(t.service.phase, MeetingPhase.ended);
      expect(t.service.transcript, isNotEmpty, reason: 'only cancel frees a transcript');
      expect(t.service.canSummarize, isTrue);
    });

    test('cancel drops the meeting and its transcript', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.handleEvent('transcript_window', _window(0));
      t.service.cancel();

      expect(t.wire.dataOf('cancel')['meetingId'], 'm1');
      expect(t.service.transcript, isEmpty);
      expect(t.service.phase, MeetingPhase.idle);
      expect(t.service.meetingId, isNull);
    });

    test('summarize can be re-run with a different model', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.handleEvent('transcript_window', _window(0));
      t.service.end();

      t.service.summarize(model: 'gemma4:e2b');
      t.service.handleEvent('summary_final', {
        'meetingId': 'm1',
        'markdown': '### Notes',
        'note': {'title': 'N', 'meetingType': 'generic', 'sections': []},
        'model': 'gemma4:e2b',
        'elapsedSeconds': 4.0,
      });
      t.service.summarize(model: 'bigger:70b');

      final models = t.wire.ofType('summarize').map((m) => m['data']['model']).toList();
      expect(models, ['gemma4:e2b', 'bigger:70b']);
      expect(t.service.summary, isNull, reason: 'the stale note is cleared while retrying');
      expect(t.service.phase, MeetingPhase.summarizing);
    });

    test('summarize is refused while still recording', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.summarize(model: 'gemma4:e2b');
      expect(t.wire.ofType('summarize'), isEmpty);
    });

    test('every command envelope carries a unique id', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.end();
      t.service.summarize(model: 'm');

      final ids = t.wire.json.map((m) => m['id']).toSet();
      expect(ids, hasLength(t.wire.json.length));
    });
  });

  group('transcript', () {
    test('windows accumulate in meeting order', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.handleEvent('transcript_window', _window(0));
      t.service.handleEvent('transcript_window', _window(1));

      expect(t.service.transcript.map((s) => s.text),
          ['mine 0', 'theirs 0', 'mine 1', 'theirs 1']);
      final stamps = t.service.transcript.map((s) => s.t0).toList();
      expect(stamps, orderedEquals([...stamps]..sort()),
          reason: 'stamps are absolute and monotonic across windows');
    });

    test('speaker attribution survives the round trip', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.handleEvent('transcript_window', _window(0));

      expect(t.service.transcript.first.isMe, isTrue);
      expect(t.service.transcript[1].isMe, isFalse);
    });

    test('a replayed window is ignored', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.handleEvent('transcript_window', _window(0));
      t.service.handleEvent('transcript_window', _window(0));

      expect(t.service.transcript, hasLength(2), reason: 'not duplicated');
    });

    test('a window from a stale meeting is not appended', () {
      final t = _build();
      t.service.start(meetingId: 'm2');
      t.service.handleEvent('transcript_window', _window(0, meetingId: 'old-meeting'));

      expect(t.service.transcript, isEmpty);
    });

    test('transcriptText renders speaker-labelled stamped lines', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.handleEvent('transcript_window', _window(1));

      expect(t.service.transcriptText, contains('[00:02:01] Me: mine 1'));
      expect(t.service.transcriptText, contains('[00:02:03] Them: theirs 1'));
    });

    test('start clears a previous meeting transcript', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.handleEvent('transcript_window', _window(0));
      t.service.start(meetingId: 'm2');

      expect(t.service.transcript, isEmpty);
      expect(t.service.canSummarize, isFalse);
    });
  });

  group('summarization', () {
    test('progress updates are exposed with a fraction', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.handleEvent('summary_progress',
          {'meetingId': 'm1', 'stage': 'map', 'completed': 4, 'total': 8});

      expect(t.service.progress!.stage, 'map');
      expect(t.service.progress!.fraction, 0.5);
    });

    test('a final note is parsed into markdown and structure', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.handleEvent('summary_final', {
        'meetingId': 'm1',
        'markdown': '### Follow-Ups\n- [ ] Send the deck.',
        'note': {
          'title': 'Coffee chat',
          'meetingType': 'coffee_chat',
          'sections': [
            {
              'title': 'Follow-Ups',
              'style': 'checkbox',
              'items': [
                {'text': 'Send the deck.', 'children': []}
              ]
            }
          ]
        },
        'model': 'gemma4:e2b',
        'elapsedSeconds': 84.2,
      });

      expect(t.service.phase, MeetingPhase.summarized);
      expect(t.service.summary!.markdown, contains('Send the deck.'));
      expect(t.service.summary!.note.sections.single.style, 'checkbox');
      expect(t.service.progress, isNull, reason: 'progress clears when the note lands');
    });

    test('summary_unavailable keeps the transcript and is not an error', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.handleEvent('transcript_window', _window(0));
      t.service.end();
      t.service.summarize(model: 'qwen3.6:27b');
      t.service.handleEvent('summary_unavailable', {
        'meetingId': 'm1',
        'reason': 'no_model',
        'detail': 'model "qwen3.6:27b" is not pulled',
        'remedy': 'ollama pull qwen3.6:27b',
      });

      expect(t.service.phase, MeetingPhase.summaryUnavailable);
      expect(t.service.error, isNull, reason: 'this must not read as a failure');
      expect(t.service.transcript, isNotEmpty, reason: 'the transcript is untouched');
      expect(t.service.unavailable!.remedy, 'ollama pull qwen3.6:27b');
      expect(t.service.canSummarize, isTrue, reason: 'retrying stays possible');
    });

    test('a null remedy is tolerated', () {
      final t = _build();
      t.service.start(meetingId: 'm1');
      t.service.handleEvent('summary_unavailable', {
        'meetingId': 'm1',
        'reason': 'no_server',
        'detail': 'connection refused',
        'remedy': null,
      });

      expect(t.service.unavailable!.remedy, isNull);
    });
  });

  group('dispatch', () {
    test('dictation events are left for the dictation handlers', () {
      final t = _build();
      t.service.start(meetingId: 'm1');

      expect(t.service.handleEvent('final', {'text': 'hello'}), isFalse);
      expect(t.service.handleEvent('error', {'code': 'X', 'message': 'dictation blew up'}),
          isFalse);
      expect(t.service.error, isNull);
    });

    test('an error carrying our meetingId is claimed', () {
      final t = _build();
      t.service.start(meetingId: 'm1');

      expect(
          t.service.handleEvent(
              'error', {'meetingId': 'm1', 'code': 'BAD_FRAME', 'message': 'bad frame'}),
          isTrue);
      expect(t.service.error, 'bad frame');
    });

    test('listeners are notified as state changes', () {
      final t = _build();
      var notifications = 0;
      t.service.addListener(() => notifications++);

      t.service.start(meetingId: 'm1');
      t.service.handleEvent('transcript_window', _window(0));
      expect(notifications, greaterThanOrEqualTo(2));
    });
  });

  group('wire shape', () {
    test('commands serialize to the documented envelope', () {
      final t = _build();
      t.service.start(meetingId: 'm1');

      final envelope = t.wire.json.single;
      expect(envelope.keys, containsAll(['type', 'id', 'data']));
      expect(() => jsonEncode(envelope), returnsNormally);
    });
  });
}
