import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Touch-only frosted surface in the iOS "glass" style: blurred backdrop,
/// translucent fill, a soft highlight on the upper edge and a hairline rim.
/// TV layouts never use it: blurring the backdrop is costly on TV boxes.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.blur = 24,
    this.tint = AppColors.glassTint,
    this.padding,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final Color tint;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          // A gradient replaces the fill colour, so tint and sheen are two
          // layers.
          child: ColoredBox(
            color: tint,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x1FFFFFFF), Color(0x05FFFFFF)],
                ),
                border: Border.all(color: AppColors.glassStroke, width: 0.8),
              ),
              child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
