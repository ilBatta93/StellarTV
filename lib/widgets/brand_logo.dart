import 'package:flutter/material.dart';

/// Approved "E finale" artwork, kept pixel-identical (colours included).
/// High-resolution transparent rasters: the vector redraw did not match.
const String kBrandWordmarkAsset = 'assets/branding/stellartv_logo.png';
const String kBrandSymbolAsset = 'assets/branding/stellartv_stella.png';
const String kBrandNameAsset = 'assets/branding/stellartv_scritta.png';
const double kBrandWordmarkAspect = 2283 / 526;
const double kBrandNameAspect = 1720 / 526;

Widget _art(String asset, double w, double h, String label) => Image.asset(
  asset,
  width: w,
  height: h,
  fit: BoxFit.contain,
  filterQuality: FilterQuality.high,
  isAntiAlias: true,
  semanticLabel: label,
);

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) =>
      _art(kBrandSymbolAsset, size, size, 'Stella StellarTV');
}

class BrandWordmark extends StatelessWidget {
  final double fontSize;
  const BrandWordmark({super.key, this.fontSize = 22});
  @override
  Widget build(BuildContext context) {
    final h = fontSize * 1.9;
    return _art(kBrandWordmarkAsset, h * kBrandWordmarkAspect, h, 'STELLAR TV');
  }
}

class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) {
    final h = size * 1.35;
    return _art(kBrandWordmarkAsset, h * kBrandWordmarkAspect, h, 'STELLAR TV');
  }
}

class BrandName extends StatelessWidget {
  final double height;
  const BrandName({super.key, this.height = 36});
  @override
  Widget build(BuildContext context) =>
      _art(kBrandNameAsset, height * kBrandNameAspect, height, 'STELLAR TV');
}
