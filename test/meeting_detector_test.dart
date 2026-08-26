import 'package:flutter_test/flutter_test.dart';
import 'package:ultrawhisper/services/meeting_detector.dart';

/// One entry as `listAudioProcesses` returns it.
Map<String, dynamic> proc(
  int pid, {
  String? bundleId,
  String name = 'App',
  bool input = false,
  bool output = false,
}) => {
      'pid': pid,
      'bundleId': bundleId,
      'name': name,
      'runningInput': input,
      'runningOutput': output,
    };

void main() {
  late List<Map<String, dynamic>> processes;
  late DateTime now;
  late List<MeetingCandidate> fired;
  late MeetingDetector detector;

  setUp(() {
    processes = [];
    now = DateTime(2026, 8, 23, 12);
    fired = [];
    detector = MeetingDetector(
      listProcesses: () async => processes,
      clock: () => now,
      sustain: const Duration(seconds: 4),
      ownPid: 999,
    )..onMeetingLikely = fired.add;
  });

  void advance(Duration d) => now = now.add(d);

  group('the input+output rule', () {
    test('fires for one process doing both, once it has held', () async {
      processes = [proc(11, bundleId: 'com.example.meet', name: 'Meet',
          input: true, output: true)];

      await detector.poll();
      expect(fired, isEmpty, reason: 'must not fire before the sustain window');

      advance(const Duration(seconds: 5));
      await detector.poll();

      expect(fired, hasLength(1));
      expect(fired.single.pid, 11);
      expect(fired.single.name, 'Meet');
    });

    test('ignores playback-only processes', () async {
      processes = [proc(11, bundleId: 'com.spotify.client', output: true)];
      await detector.poll();
      advance(const Duration(seconds: 30));
      await detector.poll();
      expect(fired, isEmpty);
    });

    test('ignores capture-only processes', () async {
      processes = [proc(11, bundleId: 'com.apple.VoiceMemos', input: true)];
      await detector.poll();
      advance(const Duration(seconds: 30));
      await detector.poll();
      expect(fired, isEmpty);
    });

    test('ignores music in one process and a mic in another', () async {
      processes = [
        proc(11, bundleId: 'com.spotify.client', output: true),
        proc(12, bundleId: 'com.apple.VoiceMemos', input: true),
      ];
      await detector.poll();
      advance(const Duration(seconds: 30));
      await detector.poll();
      expect(fired, isEmpty);
    });

    test('never fires for our own process', () async {
      processes = [proc(999, bundleId: 'com.ultrawhisper.ultrawhisper',
          input: true, output: true)];
      await detector.poll();
      advance(const Duration(seconds: 30));
      await detector.poll();
      expect(fired, isEmpty);
    });
  });

  group('sustain', () {
    test('a blip that stops being bidirectional restarts the clock', () async {
      final live = proc(11, bundleId: 'com.example.meet', input: true, output: true);
      processes = [live];
      await detector.poll();

      advance(const Duration(seconds: 3));
      processes = [proc(11, bundleId: 'com.example.meet', input: true)];
      await detector.poll();

      advance(const Duration(seconds: 3));
      processes = [live];
      await detector.poll();
      expect(fired, isEmpty, reason: 'the earlier 3s must not count');

      advance(const Duration(seconds: 5));
      await detector.poll();
      expect(fired, hasLength(1));
    });

    test('a known meeting bundle ID skips the wait', () async {
      processes = [proc(11, bundleId: 'us.zoom.xos', name: 'zoom.us',
          input: true, output: true)];
      await detector.poll();
      expect(fired, hasLength(1));
    });
  });

  group('not asking twice', () {
    setUp(() {
      processes = [proc(11, bundleId: 'com.example.meet', name: 'Meet',
          input: true, output: true)];
    });

    Future<void> firstPrompt() async {
      advance(const Duration(seconds: 10));
      await detector.poll();
      advance(const Duration(seconds: 10));
      await detector.poll();
    }

    test('one prompt per app per session', () async {
      await firstPrompt();
      expect(fired, hasLength(1));
    });

    test('"Never" adds the bundle ID and keeps a restart quiet', () async {
      await firstPrompt();
      final bundleId = detector.never(fired.single);
      expect(bundleId, 'com.example.meet');
      expect(detector.neverList, contains('com.example.meet'));

      // Same app, new pid — the never-list is keyed on the bundle ID exactly
      // so a relaunch stays quiet.
      fired.clear();
      processes = [proc(77, bundleId: 'com.example.meet', name: 'Meet',
          input: true, output: true)];
      advance(const Duration(seconds: 10));
      await detector.poll();
      advance(const Duration(seconds: 10));
      await detector.poll();
      expect(fired, isEmpty);
    });

    test('nothing is emitted while suppressed', () async {
      detector.suppressed = true;
      await firstPrompt();
      expect(fired, isEmpty);

      detector.suppressed = false;
      advance(const Duration(seconds: 10));
      await detector.poll();
      expect(fired, hasLength(1));
    });

    test('disabled means no scanning at all', () async {
      detector.enabled = false;
      await firstPrompt();
      expect(fired, isEmpty);
    });
  });

  test('a process without a bundle ID still gets a pid-scoped key', () async {
    processes = [proc(11, name: 'pid 11', input: true, output: true)];
    advance(const Duration(seconds: 10));
    await detector.poll();
    advance(const Duration(seconds: 10));
    await detector.poll();

    expect(fired, hasLength(1));
    expect(fired.single.key, 'pid:11');
    expect(detector.never(fired.single), isNull);
  });

  test('a failing scan is swallowed rather than thrown', () async {
    final failing = MeetingDetector(
      listProcesses: () async => throw StateError('channel is gone'),
      clock: () => now,
      ownPid: 999,
    );
    await expectLater(failing.poll(), completes);
  });

  test('the timer only runs while the mic is hot', () {
    expect(detector.isRunning, isFalse);
    detector.micActivityChanged(true);
    expect(detector.isRunning, isTrue);
    detector.micActivityChanged(false);
    expect(detector.isRunning, isFalse);
    detector.dispose();
  });
}
