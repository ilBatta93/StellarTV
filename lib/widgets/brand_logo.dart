import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Approved "E orbitale v2" logo as four shared vectors (same files as the
/// website): full logo, star symbol, STELLAR wordmark and TV emblem, plus the
/// STELLAR + TV name. Vectors stay sharp at every TV and phone density.
const String kBrandWordmarkAsset = 'assets/branding/stellartv_logo.svg';
const String kBrandSymbolAsset = 'assets/branding/stellartv_stella.svg';
const String kBrandStellarAsset = 'assets/branding/stellartv_stellar.svg';
const String kBrandTvAsset = 'assets/branding/stellartv_tv.svg';
const String kBrandNameAsset = 'assets/branding/stellartv_scritta.svg';

/// viewBox of every vector, in the shared artwork coordinate space.
class BrandBox {
  const BrandBox(this.x, this.y, this.w, this.h);
  final double x, y, w, h;
  double get aspect => w / h;
}

const kBrandFullBox = BrandBox(63.0, -1.0, 1992.1, 514.0);
const kBrandStarBox = BrandBox(63.0, -1.0, 498.0, 514.0);
const kBrandStellarBox = BrandBox(577.0, 171.3, 989.0, 176.4);
const kBrandTvBox = BrandBox(1602.6, 77.8, 452.5, 374.3);
const kBrandNameBox = BrandBox(577.0, 77.8, 1478.1, 374.3);
final double kBrandWordmarkAspect = kBrandFullBox.aspect;
final double kBrandNameAspect = kBrandNameBox.aspect;

Widget brandArt(String asset, double w, double h, String label) => SvgPicture.asset(
  asset,
  width: w,
  height: h,
  fit: BoxFit.contain,
  semanticsLabel: label,
);

/// Star symbol only (icons, compact headers, loading).
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) =>
      brandArt(kBrandSymbolAsset, size * kBrandStarBox.aspect, size, 'Stella StellarTV');
}

class BrandWordmark extends StatelessWidget {
  final double fontSize;
  const BrandWordmark({super.key, this.fontSize = 22});
  @override
  Widget build(BuildContext context) {
    final h = fontSize * 1.9;
    return brandArt(kBrandWordmarkAsset, h * kBrandWordmarkAspect, h, 'STELLAR TV');
  }
}

/// Full logo: star + STELLAR + TV.
class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) {
    final h = size * 1.35;
    return brandArt(kBrandWordmarkAsset, h * kBrandWordmarkAspect, h, 'STELLAR TV');
  }
}

/// Name only (STELLAR + TV), next to a separate symbol.
class BrandName extends StatelessWidget {
  final double height;
  const BrandName({super.key, this.height = 36});
  @override
  Widget build(BuildContext context) =>
      brandArt(kBrandNameAsset, height * kBrandNameAspect, height, 'STELLAR TV');
}
