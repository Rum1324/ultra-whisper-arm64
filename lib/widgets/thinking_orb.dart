import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The "listening" thinking orb: a dotted sphere with a waveform rolling
/// through its rings.
///
/// Ported from `frameWave` in thinking-orbs by Jakub Antalik
/// (https://github.com/Jakubantalik/thinking-orbs, MIT), at its 64px preset.
/// The geometry is the original's, line for line; two things are added for
/// dictation:
/// - [level] (0–1, the microphone level) scales the wave's amplitude, so the
///   orb swells when you speak and settles when you pause.
/// - The orb only advances while [repaint] ticks. The overlay stops its
///   ticker when idle, which freezes the orb on its last frame for free.
///
/// Drawn in light ink for a dark ground, as the original's dark theme.
class ThinkingOrb extends StatelessWidget {
  const ThinkingOrb({
    super.key,
    required this.repaint,
    this.level = 0,
    this.speed = 1,
    this.size = 44,
  });

  /// Anything that ticks while the orb should move.
  final Listenable repaint;

  /// Microphone level, 0–1.
  final double level;

  /// Multiplier on the preset's tempo.
  final double speed;

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _WaveOrbPainter(repaint: repaint, level: level, speed: speed),
      ),
    );
  }
}

/// One clock for every orb, as in the original: orbs stay in phase, and
/// pausing and resuming never jumps.
final Stopwatch _clock = Stopwatch()..start();

class _WaveOrbPainter extends CustomPainter {
  _WaveOrbPainter({
    required Listenable repaint,
    required this.level,
    required this.speed,
  }) : super(repaint: repaint);

  final double level;
  final double speed;

  // The 64px preset: base profile rings 15 × lonDensity 40, count 0.341
  // (each side √0.341), speed 4.388; radii at size 1.
  static const _presetSpeed = 4.388;
  static final _countScale = math.sqrt(0.341);
  static final _rings = math.max(2, (15 * _countScale).round());
  static final _lonDensity = math.max(2, (40 * _countScale).round());
  static const _rBase = 0.6;
  static const _rDepth = 1.7;
  static const _rsPow = 0.6;
  static const _rMin = 0.3;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final t = _clock.elapsedMicroseconds / 1e6 * _presetSpeed * speed;

    // Silence keeps a gentle swell; speech pushes it to about twice the
    // original's amplitude.
    final amp = 0.105 * (0.5 + 1.5 * level.clamp(0.0, 1.0));

    final cx = s / 2;
    final cy = s / 2;
    final radius = (s / 2) * 0.874;
    final rs = math.pow(s / 300, _rsPow).toDouble();

    // makeProj(yaw: t * 0.18, tilt: 0.38, scale: 1)
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
        final r = (_rBase + _rDepth * depth) * (1 + 0.4 * crest) * rs;
        final white = 0.66 - 0.56 * depth - 0.1 * crest;
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
  bool shouldRepaint(_WaveOrbPainter old) =>
      old.level != level || old.speed != speed;
}

class _Dot {
  const _Dot(this.x, this.y, this.z, this.r, this.white);
  final double x, y, z, r, white;
}
