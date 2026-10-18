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

/// Approved artwork split into star, name and TV; presentation-only.
class BrandIntro extends StatelessWidget {
  const BrandIntro({super.key, required this.progress});
  final double progress;

  // Source pixel columns of the approved artwork (2070 x 526).
  static const double _w = 2070, _h = 526, _star = 563, _tv = 1580;

  Widget _part(double left, double right, double scale) => ClipRect(
    child: SizedBox(
      width: (right - left) * scale,
      height: _h * scale,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0,
        maxWidth: double.infinity,
        child: Transform.translate(
          offset: Offset(-left * scale, 0),
          child: Image.asset(
            kBrandWordmarkAsset,
            width: _w * scale,
            height: _h * scale,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.high,
          ),
        ),
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
            final width = box.maxWidth.clamp(0.0, 720.0);
            final scale = width / _w;
            final centred = (width - _star * scale) / 2;
            return SizedBox(
              width: width,
              height: _h * scale,
              child: Stack(
                children: [
                  Positioned(
                    left: centred * (1 - frame.shift),
                    top: 0,
                    child: Opacity(
                      opacity: frame.symbol,
                      child: _part(0, _star, scale),
                    ),
                  ),
                  Positioned(
                    left: _star * scale,
                    top: 0,
                    child: Opacity(
                      opacity: frame.stellar,
                      child: _part(_star, _tv, scale),
                    ),
                  ),
                  Positioned(
                    left: _tv * scale,
                    top: 0,
                    child: Opacity(
                      opacity: frame.tv,
                      child: _part(_tv, _w, scale),
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
