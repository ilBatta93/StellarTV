import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Shared mark: star vector, STELLAR wordmark and TV emblem (same files as the
/// website), plus the STELLAR + TV name. Vectors stay sharp at every density.
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

const Color kBrandCanvas = Color(0xFF0B0B0E);

const kBrandFullBox = BrandBox(63.0, -1.0, 1992.1, 514.0);
const kBrandStarBox = BrandBox(63.0, -1.0, 498.0, 514.0);
const kBrandStellarBox = BrandBox(577.0, 171.3, 989.0, 176.4);
const kBrandTvBox = BrandBox(1602.6, 77.8, 452.5, 374.3);
const kBrandNameBox = BrandBox(577.0, 77.8, 1478.1, 374.3);
final double kBrandWordmarkAspect = kBrandFullBox.aspect;
final double kBrandNameAspect = kBrandNameBox.aspect;

Widget brandArt(String asset, double w, double h, String label) =>
    SvgPicture.asset(
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
      brandArt(kBrandSymbolAsset, size, size, 'Stella StellarTV');
}

/// Star, STELLAR and TV in the shared artwork, at one moment of the intro.
class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    required this.symbol,
    required this.shift,
    required this.stellar,
    required this.tv,
    this.maxWidth = double.infinity,
  });

  final double symbol;
  final double shift;
  final double stellar;
  final double tv;
  final double maxWidth;

  static Widget _part(
    String asset,
    BrandBox b,
    double scale,
    double left,
    double opacity,
  ) => Positioned(
    left: left,
    top: (b.y - kBrandFullBox.y) * scale,
    child: Opacity(
      opacity: opacity,
      child: brandArt(asset, b.w * scale, b.h * scale, ''),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth.clamp(0.0, maxWidth).toDouble();
        final full = kBrandFullBox;
        final scale = width / full.w;
        double at(BrandBox b) => (b.x - full.x) * scale;
        final centred = (width - kBrandStarBox.w * scale) / 2;
        final starLeft = centred * (1 - shift) + at(kBrandStarBox) * shift;
        final starTop = (kBrandStarBox.y - full.y) * scale;
        final starW = kBrandStarBox.w * scale;
        final starH = kBrandStarBox.h * scale;
        final glow = starW * 0.28;
        return SizedBox(
          width: width,
          height: full.h * scale,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: starLeft - glow,
                top: starTop - glow,
                width: starW + glow * 2,
                height: starH + glow * 2,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: symbol,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [Color(0x73F2C55A), Color(0x00F2C55A)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: starLeft,
                top: starTop,
                child: Opacity(
                  opacity: symbol,
                  child: Transform.scale(
                    scale: 0.94 + 0.06 * symbol,
                    child: brandArt(kBrandSymbolAsset, starW, starH, ''),
                  ),
                ),
              ),
              _part(
                kBrandStellarAsset,
                kBrandStellarBox,
                scale,
                at(kBrandStellarBox),
                stellar,
              ),
              _part(kBrandTvAsset, kBrandTvBox, scale, at(kBrandTvBox), tv),
            ],
          ),
        );
      },
    );
  }
}

class BrandWordmark extends StatelessWidget {
  final double fontSize;
  const BrandWordmark({super.key, this.fontSize = 22});
  @override
  Widget build(BuildContext context) {
    final h = fontSize * 1.9;
    return Semantics(
      label: 'STELLAR TV',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          width: h * kBrandWordmarkAspect,
          height: h,
          child: const BrandLockup(symbol: 1, shift: 1, stellar: 1, tv: 1),
        ),
      ),
    );
  }
}

/// Full logo: star + STELLAR + TV.
class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) {
    final h = size * 1.35;
    return Semantics(
      label: 'STELLAR TV',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          width: h * kBrandWordmarkAspect,
          height: h,
          child: const BrandLockup(symbol: 1, shift: 1, stellar: 1, tv: 1),
        ),
      ),
    );
  }
}

/// Name only (STELLAR + TV), next to a separate symbol.
class BrandName extends StatelessWidget {
  final double height;
  const BrandName({super.key, this.height = 36});
  @override
  Widget build(BuildContext context) => brandArt(
    kBrandNameAsset,
    height * kBrandNameAspect,
    height,
    'STELLAR TV',
  );
}
