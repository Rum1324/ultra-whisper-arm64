import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// What the orb is doing.
enum OrbMode {
  /// Following the microphone: still in silence, swelling with speech.
  listening,

  /// A slow, even swell while the transcript is written.
  writing,
}

/// The "listening" thinking orb: a dotted sphere whose rings carry your voice.
///
/// The dot lattice, projection and shading are ported from `frameWave` in
/// thinking-orbs by Jakub Antalik
/// (https://github.com/Jakubantalik/thinking-orbs, MIT). The motion is not:
/// the original rolls two fixed sine waves on a wall clock, which looks alive
/// whatever the microphone hears. Here the rings are driven by the voice
/// itself. Loudness is sampled into a short history, and each ring takes one
/// moment of it, so a word swells the top ring and then rolls down the sphere
/// as the next word arrives. In silence every ring is at rest and the sphere
/// is still and round.
///
/// The orb owns its ticker, so it costs nothing once unmounted: the overlay
/// only shows it while dictating.
class ThinkingOrb extends StatefulWidget {
  const ThinkingOrb({
    super.key,
    this.level = 0,
    this.mode = OrbMode.listening,
    this.size = 32,
    this.opacity = 1,
  });

  /// Microphone level as the app reports it: −60…−10 dBFS mapped to 0–100.
  final double level;

  final OrbMode mode;
  final double size;

  /// Drawn into the dot colours rather than through an opacity layer, so a
  /// fading orb costs no offscreen pass.
  final double opacity;

  @override
  State<ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<ThinkingOrb>
    with SingleTickerProviderStateMixin {
  final _voice = OrbVoice();
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _ticker?.dispose();
      _ticker = null;
    } else if (_ticker == null) {
      _ticker = createTicker(_tick)..start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    if (widget.mode == OrbMode.writing) {
      _voice.idle(dt);
    } else {
      _voice.hear(dt, widget.level);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _OrbPainter(_voice, widget.opacity.clamp(0.0, 1.0)),
      ),
    );
  }
}

/// Turns the microphone level into motion, frame by frame. Public only so
/// tests can check that silence is still and speech is not.
@visibleForTesting
class OrbVoice extends ChangeNotifier {
  /// How many past moments the sphere shows, one per ring (top = newest).
  static const rings = 9;

  /// How often a new moment enters at the top ring. Long enough that a word
  /// visibly travels, short enough that the top ring answers at once.
  static const _step = 0.07;

  /// Loudness now, 0–1, after attack/release smoothing.
  double now = 0;

  /// One loudness per ring, newest first.
  final List<double> history = List.filled(rings + 1, 0);

  /// Fraction of the way to the next shift, so the roll is continuous.
  double roll = 0;

  /// Slow spin, which also only moves while there is sound.
  double spin = 0;

  /// The room's level when nobody is talking, in the app's 0–100 units.
  /// Starts high and settles onto the real floor within the first second.
  double _floor = 40;

  double _pulse = 0;

  void hear(double dt, double level) {
    // Track the noise floor: drop to any quieter reading at once, creep up
    // slowly so speech is never mistaken for the room.
    if (level < _floor) {
      _floor += (level - _floor) * (1 - math.exp(-dt / 0.15));
    } else {
      _floor += 1.5 * dt;
    }

    // Loudness above the floor. One unit is 0.5 dB: speech sits roughly
    // 10–40 units over a quiet room. The 4-unit margin keeps breath and hum
    // from registering at all.
    final over = ((level - _floor - 4) / 36).clamp(0.0, 1.0);
    final target = math.pow(over, 0.8).toDouble();

    // Rise in 40 ms, fall over 180 ms: a syllable is one gesture.
    final tau = target > now ? 0.04 : 0.18;
    now += (target - now) * (1 - math.exp(-dt / tau));

    _advance(dt);
  }

  /// The writing swell: a slow, low breath with no microphone.
  void idle(double dt) {
    _pulse += dt;
    final target = 0.18 + 0.1 * math.sin(_pulse * 3.2);
    now += (target - now) * (1 - math.exp(-dt / 0.3));
    _advance(dt);
  }

  void _advance(double dt) {
    roll += dt / _step;
    while (roll >= 1) {
      roll -= 1;
      for (var i = history.length - 1; i > 0; i--) {
        history[i] = history[i - 1];
      }
    }
    history[0] = now;
    spin += dt * (0.05 + 0.6 * now);
    notifyListeners();
  }

  /// The loudness ring [ri] shows. The moment that entered k steps ago sits
  /// at ring k + [roll], drifting down between shifts, so ring [ri] blends
  /// toward the newer moment above it. Ring 0 is always the newest.
  double ringLevel(int ri) {
    final i = ri.clamp(0, history.length - 1);
    if (i == 0) return history[0];
    return history[i] + (history[i - 1] - history[i]) * roll;
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.voice, this.opacity) : super(repaint: voice);

  final OrbVoice voice;
  final double opacity;

  // Lattice tuned between the original's 20px and 64px presets for a ~32px
  // orb: fewer, larger dots than at 64 so it stays legible.
  static const _lonDensity = 19;
  static const _rBase = 0.78;
  static const _rDepth = 2.21;
  static const _rsPow = 0.6;
  static const _rMin = 0.3;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    const rings = OrbVoice.rings;
    final s = size.shortestSide;
    final cx = s / 2;
    final cy = s / 2;
    final radius = (s / 2) * 0.874;
    final rs = math.pow(s / 300, _rsPow).toDouble();

    // The whole sphere breathes a little with the voice right now.
    final body = 0.8 + 0.08 * voice.now;

    final yaw = voice.spin;
    const tilt = 0.38;
    final sy = math.sin(yaw), cyw = math.cos(yaw);
    final st = math.sin(tilt), ct = math.cos(tilt);

    final dots = <_Dot>[];
    for (var ri = 0; ri <= rings; ri++) {
      final lat = -math.pi / 2 + (ri / rings) * math.pi;
      final cosLat = math.cos(lat);
      final sinLat = math.sin(lat);
      // Ring 0 is the bottom of the lattice; the newest moment enters at the
      // top and rolls down.
      final h = voice.ringLevel(rings - ri);
      final rr = radius * (body + 0.2 * h);
      final lonCount = math.max(1, (cosLat.abs() * _lonDensity).round());
      for (var lj = 0; lj < lonCount; lj++) {
        final lon = (lj / lonCount) * 2 * math.pi;
        final x = cosLat * math.cos(lon) * rr;
        final y = sinLat * rr;
        final z = cosLat * math.sin(lon) * rr;
        // spin + tilt + orthographic projection
        final x1 = x * cyw + z * sy;
        final z1 = -x * sy + z * cyw;
        final y1 = y * ct - z1 * st;
        final z2 = y * st + z1 * ct;

        final depth = (z2 / radius + 1) / 2;
        final r = (_rBase + _rDepth * depth) * (1 + 0.5 * h) * rs;
        // a loud ring inks brighter, as the original's crest does
        final white = 0.66 - 0.56 * depth - 0.16 * h;
        dots.add(_Dot(cx + x1, cy - y1, z2, math.max(_rMin, r), white));
      }
    }

    // far → near, so near dots sit on top
    dots.sort((a, b) => a.z.compareTo(b.z));
    final alpha = (opacity * 255).round();
    final paint = Paint()..isAntiAlias = true;
    for (final d in dots) {
      // dark ground: the ink value is mirrored so near dots read bright
      final g = ((1 - d.white.clamp(0.0, 1.0)) * 255).round();
      paint.color = Color.fromARGB(alpha, g, g, g);
      canvas.drawCircle(Offset(d.x, d.y), d.r, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.voice != voice || old.opacity != opacity;
}

class _Dot {
  const _Dot(this.x, this.y, this.z, this.r, this.white);
  final double x, y, z, r, white;
}
