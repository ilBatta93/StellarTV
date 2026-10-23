import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../player/tv_playback_shortcuts.dart';
import 'player_format.dart';
import '../../models/episode_metadata.dart';
import '../title_facets.dart';

/// Local metadata only: no artwork, requests, blur or independent polling.
class TvPlaybackInfo extends StatelessWidget {
  final String title;
  final String? plot;
  final Duration duration;
  final Duration position;
  final double speed;
  final bool playing;
  final EpisodeMetadata? episodeMetadata;

  const TvPlaybackInfo({
    super.key,
    required this.title,
    this.plot,
    required this.duration,
    required this.position,
    required this.speed,
    required this.playing,
    this.episodeMetadata,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = remainingPlaybackTime(duration, position, speed);
    final end = remaining == null || !playing
        ? null
        : DateTime.now().add(remaining);
    final summary = plot?.trim();
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.fromLTRB(24, 64, 24, 0),
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 720),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.onOverlay,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (episodeMetadata case final metadata?) ...[
                  const SizedBox(height: 8),
                  EpisodeRatingBadge(metadata, request: false),
                ],
                if (remaining != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Rimangono ${formatDuration(remaining)}'
                    '${end == null ? '' : ' · Fine prevista ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.onOverlaySecondary,
                      fontSize: 16,
                    ),
                  ),
                ],
                if (summary != null && summary.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.onOverlaySecondary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
