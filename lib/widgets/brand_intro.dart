import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brand_logo.dart';

const _gold = Color(0xFFF2C55A);
const _ember = Color(0xFFFF5A1F);

/// Timeline contains no startup, session or navigation work.
class BrandIntroFrame {
  const BrandIntroFrame(this.symbol, this.shift, this.stellar, this.tv);
  final double symbol;
  final double shift;
  final double stellar;
  final double tv;
  static double _phase(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);
  static BrandIntroFrame at(double t) => BrandIntroFrame(
    _phase(t, 0, .18),
    Curves.easeInOutCubic.transform(_phase(t, .25, .60)),
    _phase(t, .60, .80),
    _phase(t, .80, 1),
  );

  /// Comet travelling the orbit before the star lights up (0..1).
  static double comet(double t) =>
      Curves.easeInCubic.transform(_phase(t, 0, .2));

  /// Light ring released when the star lights up (0..1, 0 = hidden).
  static double ring(double t) => _phase(t, .16, .5);

  /// Orbit line around the star: fades in, then out while the name arrives.
  static double orbit(double t) {
    if (t < .3) return _phase(t, 0, .12);
    return 1 - _phase(t, .3, .62);
  }

  /// Glint sweeping across the finished logo (0..1, 0 = not started).
  static double glint(double t) => _phase(t, .84, 1);
}

/// Approved logo assembled from its three vectors (star, STELLAR, TV), each
/// placed at its exact position in the shared artwork, plus the orbit, comet
/// and light effects of the intro; presentation-only.
class BrandIntro extends StatelessWidget {
  const BrandIntro({super.key, required this.progress});
  final double progress;

  static const _maxWidth = 720.0;

  @override
  Widget build(BuildContext context) {
    final frame = BrandIntroFrame.at(progress);
    final glint = BrandIntroFrame.glint(progress);
    Widget lockup = BrandLockup(
      symbol: frame.symbol,
      shift: frame.shift,
      stellar: frame.stellar,
      tv: frame.tv,
      maxWidth: _maxWidth,
    );
    if (glint > 0 && glint < 1) {
      // The band paints only over the logo pixels (srcATop).
      lockup = ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) {
          final x = -0.4 + glint * 1.8;
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [
              Color(0x00FFFFFF),
              Color(0x99FFF4D6),
              Color(0x00FFFFFF),
            ],
            stops: [
              (x - .12).clamp(0.0, 1.0),
              x.clamp(0.0, 1.0),
              (x + .12).clamp(0.0, 1.0),
            ],
            transform: const GradientRotation(-0.35),
          ).createShader(rect);
        },
        child: lockup,
      );
    }
    return Semantics(
      label: 'STELLAR TV',
      image: true,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth.clamp(0.0, _maxWidth).toDouble();
            final full = kBrandFullBox;
            final scale = width / full.w;
            final starW = kBrandStarBox.w * scale;
            final starH = kBrandStarBox.h * scale;
            final centred = (width - starW) / 2;
            final docked = (kBrandStarBox.x - full.x) * scale;
            final starLeft = centred * (1 - frame.shift) + docked * frame.shift;
            final center = Offset(
              starLeft + starW / 2,
              (kBrandStarBox.y - full.y) * scale + starH / 2,
            );
            return CustomPaint(
              painter: _IntroFxPainter(
                progress: progress,
                center: center,
                radius: starW / 2,
              ),
              child: lockup,
            );
          },
        ),
      ),
    );
  }
}

/// Orbit, comet and light ring drawn around the star, outside the logo box.
class _IntroFxPainter extends CustomPainter {
  _IntroFxPainter({
    required this.progress,
    required this.center,
    required this.radius,
  });

  final double progress;
  final Offset center;
  final double radius;

  static const _tilt = -0.32;

  Offset _onOrbit(double angle, double rx, double ry) {
    final x = rx * math.cos(angle);
    final y = ry * math.sin(angle);
    return center +
        Offset(
          x * math.cos(_tilt) - y * math.sin(_tilt),
          x * math.sin(_tilt) + y * math.cos(_tilt),
        );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0) return;
    final rx = radius * 2.3;
    final ry = radius * 0.78;

    final orbit = BrandIntroFrame.orbit(progress);
    if (orbit > 0) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(_tilt);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, radius * 0.025)
          ..color = _gold.withValues(alpha: 0.28 * orbit),
      );
      canvas.restore();
    }

    final comet = BrandIntroFrame.comet(progress);
    if (comet > 0 && comet < 1) {
      // One and a half turns, spiralling into the star.
      final start = math.pi * 0.9;
      final angle = start + comet * math.pi * 3;
      final shrink = 1 - comet * 0.85;
      const trail = 18;
      for (var i = trail; i >= 0; i--) {
        final back = angle - i * 0.07;
        final k = 1 - i / trail;
        final p = _onOrbit(back, rx * shrink, ry * shrink);
        canvas.drawCircle(
          p,
          radius * (0.025 + 0.06 * k),
          Paint()..color = Color.lerp(_ember, _gold, k)!.withValues(alpha: k),
        );
      }
      final head = _onOrbit(angle, rx * shrink, ry * shrink);
      canvas.drawCircle(
        head,
        radius * 0.35,
        Paint()
          ..shader = RadialGradient(
            colors: [_gold.withValues(alpha: 0.7), _gold.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: head, radius: radius * 0.35)),
      );
    }

    final ring = BrandIntroFrame.ring(progress);
    if (ring > 0 && ring < 1) {
      final eased = Curves.easeOutCubic.transform(ring);
      for (final (lag, weight) in [(0.0, 1.0), (0.18, 0.5)]) {
        final e = ((eased - lag) / (1 - lag)).clamp(0.0, 1.0);
        if (e <= 0) continue;
        canvas.drawCircle(
          center,
          radius * (0.9 + 3.2 * e),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = radius * 0.12 * (1 - e) + 0.5
            ..color = _gold.withValues(alpha: 0.55 * (1 - e) * weight),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_IntroFxPainter old) =>
      old.progress != progress || old.center != center || old.radius != radius;
}

/// Full-screen deep sky behind the intro: a warm nebula and twinkling
/// stars drifting slowly towards the viewer.
class BrandIntroBackdrop extends StatelessWidget {
  const BrandIntroBackdrop({super.key, required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _SkyPainter(progress),
      child: const SizedBox.expand(),
    ),
  );
}

class _Star {
  const _Star(this.x, this.y, this.size, this.phase, this.speed);
  final double x, y, size, phase, speed;
}

final List<_Star> _stars = () {
  final random = math.Random(7);
  return [
    for (var i = 0; i < 110; i++)
      _Star(
        random.nextDouble() * 2 - 1,
        random.nextDouble() * 2 - 1,
        0.4 + random.nextDouble() * random.nextDouble() * 1.8,
        random.nextDouble() * math.pi * 2,
        1 + random.nextDouble() * 3,
      ),
  ];
}();

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = kBrandCanvas);
    final fade = Curves.easeOut.transform((t / 0.35).clamp(0.0, 1.0));
    final shortest = size.shortestSide;

    void nebula(Offset at, double r, Color color, double alpha) {
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha * fade),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: at, radius: r)),
      );
    }

    final c = size.center(Offset.zero);
    nebula(c, shortest * 0.75, _gold, 0.10);
    nebula(
      Offset(size.width * (0.18 + 0.04 * t), size.height * 0.82),
      shortest * 0.9,
      _ember,
      0.14,
    );
    nebula(
      Offset(size.width * (0.86 - 0.04 * t), size.height * 0.16),
      shortest * 0.7,
      const Color(0xFF6E5BFF),
      0.10,
    );

    final zoom = 1 + 0.08 * t;
    final paint = Paint();
    for (final s in _stars) {
      final p = c + Offset(s.x * size.width / 2, s.y * size.height / 2) * zoom;
      final twinkle =
          0.55 + 0.45 * math.sin(s.phase + t * math.pi * 2 * s.speed);
      paint.color = Colors.white.withValues(alpha: 0.75 * twinkle * fade);
      canvas.drawCircle(p, s.size, paint);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.t != t;
}
