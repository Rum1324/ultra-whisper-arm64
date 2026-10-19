import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:ultrawhisper/services/audio_service.dart';

/// Behaves like record 6.1.2 on macOS: chunks already on the platform channel
/// arrive while `stop()` is in flight, and `stop()` closes the stream before
/// it returns.
class _FakeRecorder implements AudioRecorder {
  _FakeRecorder({this.closesStreamOnStop = true});

  final bool closesStreamOnStop;
  final StreamController<Uint8List> _ctrl = StreamController<Uint8List>.broadcast();
  final Uint8List tail = Uint8List.fromList(List.filled(682, 9));

  void emit(Uint8List chunk) => _ctrl.add(chunk);

  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async => _ctrl.stream;

  @override
  Future<String?> stop() async {
    await Future<void>.delayed(Duration.zero);
    _ctrl.add(tail);
    if (closesStreamOnStop) await _ctrl.close();
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('chunks delivered during stop() reach listeners before stopRecording returns', () async {
    final recorder = _FakeRecorder();
    final service = AudioService(recorder: recorder);
    final received = <Uint8List>[];

    await service.startRecording();
    // Cancelled right after stopRecording, as AppService does before end_session.
    final sub = service.audioStream.listen(received.add);
    recorder.emit(Uint8List.fromList(List.filled(682, 3)));

    await service.stopRecording();
    await sub.cancel();

    expect(received, hasLength(2));
    expect(received.last, recorder.tail);
    expect(service.isRecording, isFalse);
  });

  test('a stream that never closes does not hang stopRecording', () async {
    final service = AudioService(recorder: _FakeRecorder(closesStreamOnStop: false));
    await service.startRecording();

    final watch = Stopwatch()..start();
    await service.stopRecording();

    expect(watch.elapsed, lessThan(AudioService.streamDrainTimeout * 2));
    expect(service.isRecording, isFalse);
  });
}
