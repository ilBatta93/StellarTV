import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const String kBrandWordmarkAsset = 'assets/branding/stellartv_logo.svg';
const String kBrandSymbolAsset = 'assets/branding/stellartv_stella.svg';
const String kBrandNameAsset = 'assets/branding/stellartv_scritta.svg';
/// Keep the original layout envelope; the SVG is contained, never stretched.
const double kBrandWordmarkAspect = 1654 / 375;

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    kBrandSymbolAsset, width: size, height: size,
    fit: BoxFit.contain, semanticsLabel: 'Stella StellarTV',
  );
}

class BrandWordmark extends StatelessWidget {
  final double fontSize;
  const BrandWordmark({super.key, this.fontSize = 22});
  @override
  Widget build(BuildContext context) {
    final h = fontSize * 1.9;
    return SvgPicture.asset(kBrandWordmarkAsset, height: h,
      width: h * kBrandWordmarkAspect, fit: BoxFit.contain,
      semanticsLabel: 'STELLAR TV');
  }
}

class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) {
    final h = size * 1.35;
    return SvgPicture.asset(kBrandWordmarkAsset, height: h,
      width: h * kBrandWordmarkAspect, fit: BoxFit.contain,
      semanticsLabel: 'STELLAR TV');
  }
}

class BrandName extends StatelessWidget {
  final double height;
  const BrandName({super.key, this.height = 36});
  @override
  Widget build(BuildContext context) => SvgPicture.asset(kBrandNameAsset,
    height: height, width: height * 1482 / 378,
    fit: BoxFit.contain, semanticsLabel: 'STELLAR TV');
}
