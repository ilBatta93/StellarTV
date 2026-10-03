import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  final double size;

  const BrandMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: size * 0.4,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: CustomPaint(painter: _TvPlayPainter()),
    );
  }
}

class _TvPlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.065
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(w * 0.38, w * 0.16), Offset(w * 0.5, w * 0.28), stroke);
    canvas.drawLine(Offset(w * 0.62, w * 0.16), Offset(w * 0.5, w * 0.28), stroke);

    final screen = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.18, w * 0.29, w * 0.64, w * 0.5),
      Radius.circular(w * 0.1),
    );
    canvas.drawRRect(screen, stroke);

    final play = Path()
      ..moveTo(w * 0.44, w * 0.41)
      ..lineTo(w * 0.6, w * 0.54)
      ..lineTo(w * 0.44, w * 0.67)
      ..close();
    canvas.drawPath(play, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BrandWordmark extends StatelessWidget {
  final double fontSize;

  const BrandWordmark({super.key, this.fontSize = 22});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: 'il',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
                letterSpacing: -0.5,
              ),
            ),
            TextSpan(
              text: 'Batta',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
          ]),
        ),
        SizedBox(width: fontSize * 0.2),
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: fontSize * 0.28, vertical: fontSize * 0.04),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(fontSize * 0.22),
          ),
          child: Text(
            'TV',
            style: TextStyle(
              fontSize: fontSize * 0.82,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.2,
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
        BrandWordmark(fontSize: size * 0.62),
      ],
    );
  }
}
