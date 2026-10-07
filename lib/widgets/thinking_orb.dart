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

/// The "listening" thinking orb: a dotted sphere with a waveform rolling
/// through its rings.
///
/// Geometry ported from `frameWave` in thinking-orbs by Jakub Antalik
/// (https://github.com/Jakubantalik/thinking-orbs, MIT). The original rolls
/// on a wall clock; here the voice drives it instead. [level] sets how far the
/// rings swell and how fast the wave rolls and the sphere turns, so silence
/// is a still, round sphere and speech is what moves it.
///
/// The orb owns its ticker, so it costs nothing once unmounted: the overlay
/// only shows it while dictating.
class ThinkingOrb extends StatefulWidget {
  const ThinkingOrb({
    super.key,
    this.level = 0,
    this.mode = OrbMode.listening,
    this.size = 32,
  });

  /// Microphone level as the app reports it, 0–100.
  final double level;

  final OrbMode mode;
  final double size;

  @override
  State<ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<ThinkingOrb>
    with SingleTickerProviderStateMixin {
  final _motion = _OrbMotion();
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _ticker?.dispose();
      _ticker = null;
      _motion.phase = 0.6;
    } else if (_ticker == null) {
      _ticker = createTicker(_tick)..start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _motion.advance(dt, _target());
  }

  /// The swell the orb is heading for, 0–1. Speech RMS sits low on a linear
  /// scale, so it is lifted logarithmically, as the old waveform did.
  double _target() {
    if (widget.mode == OrbMode.writing) return 0.12;
    final x = (widget.level / 100).clamp(0.0, 1.0);
    return math.log(1 + 9 * x) / math.ln10;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(painter: _WaveOrbPainter(_motion)),
    );
  }
}

/// The orb's state between frames: how swollen it is and how far the wave
/// has rolled. Notifies the painter, so a frame repaints without a rebuild.
class _OrbMotion extends ChangeNotifier {
  double swell = 0;
  double phase = 0;

  // Tempo of the original's 64px preset.
  static const _presetSpeed = 4.388;

  void advance(double dt, double target) {
    // Rise fast, fall slower: syllables read as one gesture, not a flicker.
    final tau = target > swell ? 0.05 : 0.22;
    swell += (target - swell) * (1 - math.exp(-dt / tau));
    // Near-still in silence; up to the original's full tempo when speaking.
    phase += dt * _presetSpeed * (0.06 + 0.94 * swell);
    notifyListeners();
  }
}

class _WaveOrbPainter extends CustomPainter {
  _WaveOrbPainter(this.motion) : super(repaint: motion);

  final _OrbMotion motion;

  // Tuned between the original's 20px and 64px presets for a ~32px orb:
  // fewer, larger dots than at 64 so it stays legible.
  static const _rings = 7;
  static const _lonDensity = 19;
  static const _rBase = 0.78;
  static const _rDepth = 2.21;
  static const _rsPow = 0.6;
  static const _rMin = 0.3;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final t = motion.phase;
    final swell = motion.swell;

    // Silence: a round sphere. Speech: rings pushed out to about twice the
    // original's undulation.
    final amp = 0.012 + 0.2 * swell;
    final crestGain = 0.4 * math.min(1.0, swell * 2);

    final cx = s / 2;
    final cy = s / 2;
    final radius = (s / 2) * 0.874;
    final rs = math.pow(s / 300, _rsPow).toDouble();

    // spin follows the wave, so a silent orb also stops turning
    final yaw = t * 0.18;
    const tilt = 0.38;
    final sy = math.sin(yaw), cyw = math.cos(yaw);
    final st = math.sin(tilt), ct = math.cos(tilt);

    final dots = <_Dot>[];
    for (var ri = 0; ri <= _rings; ri++) {
      final lat = -math.pi / 2 + (ri / _rings) * math.pi;
      final cosLat = math.cos(lat);
      final sinLat = math.sin(lat);
      // two waves, different tempi — organic, never quite repeating
      final w = 0.62 * math.sin(t * 2.1 - ri * 0.52) +
          0.38 * math.sin(t * 1.27 + ri * 0.83);
      final rr = radius * (0.88 + amp * w);
      final crest = math.max(0.0, w);
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
        final r = (_rBase + _rDepth * depth) * (1 + crestGain * crest) * rs;
        final white = 0.66 - 0.56 * depth - 0.1 * crest * swell;
        dots.add(_Dot(cx + x1, cy - y1, z2, math.max(_rMin, r), white));
      }
    }

    // far → near, so near dots sit on top
    dots.sort((a, b) => a.z.compareTo(b.z));
    final paint = Paint()..isAntiAlias = true;
    for (final d in dots) {
      // dark ground: the ink value is mirrored so near dots read bright
      final g = ((1 - d.white.clamp(0.0, 1.0)) * 255).round();
      paint.color = Color.fromARGB(255, g, g, g);
      canvas.drawCircle(Offset(d.x, d.y), d.r, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveOrbPainter old) => old.motion != motion;
}

class _Dot {
  const _Dot(this.x, this.y, this.z, this.r, this.white);
  final double x, y, z, r, white;
}
