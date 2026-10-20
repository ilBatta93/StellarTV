import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'player_format.dart';

/// tvOS-style time bubble that floats above the playhead.
///
/// Pure presentation: it never owns focus or gestures, so remote navigation
/// and touch scrubbing keep working exactly as before.
class SeekTimeBubble extends StatelessWidget {
  static const double width = 92;
  static const double height = 34;

  final Duration time;
  final bool visible;

  const SeekTimeBubble({super.key, required this.time, required this.visible});

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: still ? Duration.zero : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: AnimatedScale(
          scale: visible ? 1 : 0.85,
          alignment: Alignment.bottomCenter,
          duration: still ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: SizedBox(
            width: width,
            height: height + 6,
            child: Column(
              children: [
                Container(
                  width: width,
                  height: height,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.card.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(height / 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.overlay,
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    formatDuration(time),
                    style: const TextStyle(
                      color: AppColors.onOverlay,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                CustomPaint(
                  size: const Size(12, 6),
                  painter: _PointerPainter(
                    AppColors.card.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Left offset that centres the bubble on [x], kept inside [0, trackWidth].
  static double leftFor(double x, double trackWidth) {
    final max = trackWidth - width;
    final left = x - width / 2;
    if (max <= 0) return max / 2;
    return left.clamp(0.0, max);
  }
}

class _PointerPainter extends CustomPainter {
  final Color color;
  const _PointerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.color != color;
}
