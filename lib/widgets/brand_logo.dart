import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  final double size;

  const BrandMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: Image.asset(
        'assets/stellartv-logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class BrandWordmark extends StatelessWidget {
  final double fontSize;

  const BrandWordmark({super.key, this.fontSize = 22});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/stellartv-name-logo.png',
      width: fontSize * 5.2,
      height: fontSize * 1.55,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
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
