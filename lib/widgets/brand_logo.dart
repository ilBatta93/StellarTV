import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// "Orbit Stellar" mark: a titanium four-point star with an orange core and a
/// tilted orbit ring. Pure vector, so it stays crisp from the app bar to TV.
class BrandMark extends StatelessWidget {
  final double size;

  const BrandMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _StellarMarkPainter(color: AppColors.primary),
      ),
    );
  }
}

/// STELLAR ✦ [TV] — spaced satin wordmark, star separator and a glass pill.
class BrandWordmark extends StatelessWidget {
  final double fontSize;

  const BrandWordmark({super.key, this.fontSize = 22});

  @override
  Widget build(BuildContext context) {
    final f = fontSize;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'STELLAR',
          maxLines: 1,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: const Color(0xFFF5F5F7),
            fontFamily: 'Sora',
            fontSize: f,
            fontWeight: FontWeight.w300,
            letterSpacing: f * 0.28,
            height: 1,
          ),
        ),
        SizedBox(
          width: f * 0.7,
          height: f * 0.7,
          child: CustomPaint(
            painter: _SparkPainter(color: AppColors.primary),
          ),
        ),
        SizedBox(width: f * 0.18),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: f * 0.32,
            vertical: f * 0.12,
          ),
          decoration: BoxDecoration(
            color: const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(f),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.85),
              width: math.max(1.0, f * 0.05),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.28),
                blurRadius: f * 0.5,
              ),
            ],
          ),
          child: Text(
            'TV',
            maxLines: 1,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: const Color(0xFFF5F5F7),
              fontFamily: 'Sora',
              fontSize: f * 0.62,
              fontWeight: FontWeight.w600,
              letterSpacing: f * 0.08,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class BrandLogo extends StatelessWidget {
  final double size;

  const BrandLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: size),
        SizedBox(width: size * 0.3),
        BrandWordmark(fontSize: size * 0.5),
      ],
    );
  }
}

Path _starPath(Offset c, double rx, double ry, double waist) {
  return Path()
    ..moveTo(c.dx, c.dy - ry)
    ..quadraticBezierTo(c.dx + waist, c.dy - waist, c.dx + rx, c.dy)
    ..quadraticBezierTo(c.dx + waist, c.dy + waist, c.dx, c.dy + ry)
    ..quadraticBezierTo(c.dx - waist, c.dy + waist, c.dx - rx, c.dy)
    ..quadraticBezierTo(c.dx - waist, c.dy - waist, c.dx, c.dy - ry)
    ..close();
}

class _StellarMarkPainter extends CustomPainter {
  const _StellarMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, size.height / 2);
    final orbitRect = Rect.fromCenter(center: c, width: s * 0.94, height: s * 0.36);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, s * 0.035)
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [const Color(0xFFFF5E00), color, const Color(0xFFFFA000)],
      ).createShader(orbitRect);

    void orbitArc(double start, double sweep) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(-math.pi / 9);
      canvas.translate(-c.dx, -c.dy);
      canvas.drawArc(orbitRect, start, sweep, false, ring);
      canvas.restore();
    }

    // Soft core glow.
    canvas.drawCircle(
      c,
      s * 0.3,
      Paint()
        ..color = color.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.14),
    );
    // Back half of the orbit passes behind the star.
    orbitArc(math.pi, math.pi);

    final star = _starPath(c, s * 0.44, s * 0.47, s * 0.06);
    final bounds = star.getBounds();
    canvas.drawPath(
      star,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFC9CBD1), Color(0xFF7D8088)],
        ).createShader(bounds),
    );
    // Orange core.
    canvas.drawPath(
      _starPath(c, s * 0.2, s * 0.2, s * 0.025),
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFFFFF3E0), color, color.withValues(alpha: 0)],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: c, radius: s * 0.2)),
    );
    // Front half of the orbit crosses in front.
    orbitArc(0, math.pi);
  }

  @override
  bool shouldRepaint(covariant _StellarMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      c,
      size.width * 0.3,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.2),
    );
    canvas.drawPath(
      _starPath(c, size.width * 0.42, size.height * 0.36, size.width * 0.05),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.color != color;
}
