import 'package:flutter_test/flutter_test.dart';
import 'package:ultrawhisper/widgets/thinking_orb.dart';

/// Feeds [level] (the app's 0–100 dB scale) for [seconds] at 60 fps.
void feed(OrbVoice voice, double level, double seconds) {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    voice.hear(1 / 60, level);
  }
}

void main() {
  // The orb used to roll on a clock, so it looked busy whatever the mic
  // heard. These pin the behaviour that replaced it.

  test('a quiet room settles to a still orb', () {
    final voice = OrbVoice();
    // A typical room: about -48 dBFS with a little hum on top.
    for (var i = 0; i < 120; i++) {
      voice.hear(1 / 60, 24 + (i.isEven ? 1.5 : -1.5));
    }
    expect(voice.now, lessThan(0.02));
    expect(voice.history.every((h) => h < 0.02), isTrue);
  });

  test('speech swells the newest ring at once and rolls down', () {
    final voice = OrbVoice();
    feed(voice, 24, 2); // learn the room
    feed(voice, 70, 0.1); // a word, about 23 dB over it

    expect(voice.now, greaterThan(0.5));
    expect(voice.ringLevel(0), greaterThan(0.5));
    // the far end of the sphere has not heard it yet
    expect(voice.ringLevel(OrbVoice.rings), lessThan(0.05));

    feed(voice, 24, 0.4); // silence again: the word travels on
    expect(voice.now, lessThan(0.15));
    expect(voice.history.skip(3).any((h) => h > 0.3), isTrue);
  });

  test('louder speech swells more than quiet speech', () {
    final quiet = OrbVoice();
    final loud = OrbVoice();
    feed(quiet, 24, 2);
    feed(loud, 24, 2);
    feed(quiet, 45, 0.3);
    feed(loud, 75, 0.3);
    expect(loud.now, greaterThan(quiet.now + 0.3));
  });
}
