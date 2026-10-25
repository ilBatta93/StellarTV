import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared "already watched" mark for the series page and the player list.
/// A watched episode is dimmed and labelled; a partial one only shows progress.
class EpisodeStillOverlay extends StatelessWidget {
  final bool watched;
  final double? progress;

  /// Center play icon used on the series card. The player list omits it.
  final bool showPlay;

  const EpisodeStillOverlay({
    super.key,
    required this.watched,
    this.progress,
    this.showPlay = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (watched)
          const ColoredBox(color: Color(0xB3000000)),
        if (watched)
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: AppColors.background,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Visto',
                        style: TextStyle(
                          color: AppColors.background,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else if (showPlay)
          const Center(
            child: Icon(
              Icons.play_circle_fill_rounded,
              size: 42,
              color: AppColors.textPrimary,
            ),
          ),
        if (!watched && progress != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  color: AppColors.primary,
                  backgroundColor: AppColors.track,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
