import 'package:flutter/material.dart';
import 'brand_logo.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
}

/// Approved SVG paths; animation remains presentation-only.
class BrandIntro extends StatelessWidget {
  const BrandIntro({super.key, required this.progress});
  final double progress;

  Widget _part(double left, double right, double scale) => ClipRect(
    child: SizedBox(
      width: (right - left) * scale,
      height: 512 * scale,
      child: Stack(
        children: [
          Positioned(
            left: -left * scale,
            top: 0,
            width: 1998 * scale,
            height: 512 * scale,
            child: SvgPicture.asset(
              kBrandWordmarkAsset,
              fit: BoxFit.fill,
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final frame = BrandIntroFrame.at(progress);
    return Semantics(
      label: 'STELLAR TV',
      image: true,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth.clamp(0.0, 640.0);
            final height = width * 375 / 1654;
            final scale = height / 512;
            final vectorWidth = 1998 * scale;
            final inset = (width - vectorWidth) / 2;
            final initialLeft = (width - 516 * scale) / 2;
            return SizedBox(
              width: width,
              height: 512 * scale,
              child: Stack(
                children: [
                  Positioned(
                    left: inset + (initialLeft - inset) * (1 - frame.shift),
                    top: 0,
                    child: Opacity(
                      opacity: frame.symbol,
                      child: _part(0, 516, scale),
                    ),
                  ),
                  Positioned(
                    left: inset + 516 * scale,
                    top: 0,
                    child: Opacity(
                      opacity: frame.stellar,
                      child: _part(516, 1522, scale),
                    ),
                  ),
                  Positioned(
                    left: inset + 1522 * scale,
                    top: 0,
                    child: Opacity(
                      opacity: frame.tv,
                      child: _part(1522, 1998, scale),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
