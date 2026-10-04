import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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

class BrandWordmark extends StatelessWidget {
  final double fontSize;

  const BrandWordmark({super.key, this.fontSize = 22});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(
            text: 'STELLAR',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: 'TV',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
      maxLines: 1,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        color: AppColors.textPrimary,
        fontFamily: 'Sora',
        fontSize: fontSize,
        height: 1,
      ),
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
        SizedBox(width: size * 0.34),
        BrandWordmark(fontSize: size * 0.58),
      ],
    );
  }
}

/// A four-point stellar flare cut by a play-shaped void. It stays crisp from
/// the compact app bar to TV-sized splash screens and needs no bitmap asset.
class _StellarMarkPainter extends CustomPainter {
  const _StellarMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final glow = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.16);
    canvas.drawCircle(center, size.width * 0.34, glow);

    final flare = Path()
      ..moveTo(center.dx, size.height * 0.03)
      ..cubicTo(
        size.width * 0.56,
        size.height * 0.36,
        size.width * 0.64,
        size.height * 0.44,
        size.width * 0.97,
        center.dy,
      )
      ..cubicTo(
        size.width * 0.64,
        size.height * 0.56,
        size.width * 0.56,
        size.height * 0.64,
        center.dx,
        size.height * 0.97,
      )
      ..cubicTo(
        size.width * 0.44,
        size.height * 0.64,
        size.width * 0.36,
        size.height * 0.56,
        size.width * 0.03,
        center.dy,
      )
      ..cubicTo(
        size.width * 0.36,
        size.height * 0.44,
        size.width * 0.44,
        size.height * 0.36,
        center.dx,
        size.height * 0.03,
      )
      ..close();

    final play = Path()
      ..moveTo(size.width * 0.43, size.height * 0.34)
      ..lineTo(size.width * 0.70, center.dy)
      ..lineTo(size.width * 0.43, size.height * 0.66)
      ..close();
    final mark = Path.combine(PathOperation.difference, flare, play);
    canvas.drawPath(mark, Paint()..color = color);
    canvas.drawCircle(
      Offset(size.width * 0.74, size.height * 0.25),
      size.width * 0.045,
      Paint()..color = AppColors.textPrimary,
    );
  }

  @override
  bool shouldRepaint(covariant _StellarMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
