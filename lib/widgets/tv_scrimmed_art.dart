import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// TV artwork under the black scrim shared by Home and detail pages: solid
/// on the text side, clear past the middle, optionally fading to black at
/// the bottom.
///
/// The layer is redrawn on every frame of a scroll. The picture is skipped
/// where the scrim is solid and each gradient covers only its fade, so a
/// weak TV GPU fills about half the pixels (Fire TV Stick, Home row scroll:
/// slowest raster frames from 35 to 20 ms).
class TvScrimmedArt extends StatelessWidget {
  /// Scrim stops across the width: solid black up to [solid], fading to
  /// clear at [clear].
  static const solid = 0.28;
  static const clear = 0.58;

  final Widget picture;

  /// Height fraction where the bottom fade to black starts; null for none.
  final double? bottomFadeFrom;

  const TvScrimmedArt({super.key, required this.picture, this.bottomFadeFrom});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final left = c.maxWidth * solid;
        final fadeFrom = bottomFadeFrom;
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(clipper: _LeftCut(left), child: picture),
            Positioned(
              left: left,
              width: c.maxWidth * (clear - solid),
              top: 0,
              bottom: 0,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.background, AppColors.clear],
                  ),
                ),
              ),
            ),
            if (fadeFrom != null)
              Positioned(
                left: left,
                right: 0,
                top: c.maxHeight * fadeFrom,
                bottom: 0,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.clear, AppColors.background],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Drops the part of the picture hidden by the solid scrim.
class _LeftCut extends CustomClipper<Rect> {
  final double left;
  const _LeftCut(this.left);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(left.clamp(0, size.width), 0, size.width, size.height);

  @override
  bool shouldReclip(_LeftCut old) => old.left != left;
}
