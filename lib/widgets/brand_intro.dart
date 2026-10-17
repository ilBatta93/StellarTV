import 'package:flutter/material.dart';
import 'brand_logo.dart';

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

/// Exact, unmodified pixels from the approved flattened logo. Its orbit is
/// baked into the symbol; independent orbit motion awaits original layers.
class BrandIntro extends StatelessWidget {
  const BrandIntro({super.key, required this.progress});
  final double progress;

  Widget _part(double left, double right, double scale) => ClipRect(
    child: SizedBox(
      width: (right - left) * scale,
      height: 375 * scale,
      child: Stack(
        children: [
          Positioned(
            left: -left * scale,
            top: 0,
            width: 1654 * scale,
            height: 375 * scale,
            child: Image.asset(
              kBrandWordmarkAsset,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
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
            final scale = width / 1654;
            final initialLeft = (width - 400 * scale) / 2;
            return SizedBox(
              width: width,
              height: 375 * scale,
              child: Stack(
                children: [
                  Positioned(
                    left: initialLeft * (1 - frame.shift),
                    top: 0,
                    child: Opacity(
                      opacity: frame.symbol,
                      child: _part(0, 400, scale),
                    ),
                  ),
                  Positioned(
                    left: 400 * scale,
                    top: 0,
                    child: Opacity(
                      opacity: frame.stellar,
                      child: _part(400, 1390, scale),
                    ),
                  ),
                  Positioned(
                    left: 1390 * scale,
                    top: 0,
                    child: Opacity(
                      opacity: frame.tv,
                      child: _part(1390, 1654, scale),
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
