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

/// Approved logo assembled from its three vectors (star, STELLAR, TV), each
/// placed at its exact position in the shared artwork; presentation-only.
class BrandIntro extends StatelessWidget {
  const BrandIntro({super.key, required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final frame = BrandIntroFrame.at(progress);
    return Semantics(
      label: 'STELLAR TV',
      image: true,
      child: ExcludeSemantics(
        child: BrandLockup(
          symbol: frame.symbol,
          shift: frame.shift,
          stellar: frame.stellar,
          tv: frame.tv,
          maxWidth: 720,
        ),
      ),
    );
  }
}
