import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_type_service.dart';
import '../services/download_service.dart';
import '../models/series_details.dart';
import '../models/episode_metadata.dart';
import '../services/episode_metadata_service.dart';
import 'title_facets.dart';
import '../theme/app_theme.dart';
import 'poster_card.dart';
import 'episode_still_overlay.dart';
import 'tv_focusable.dart';
import 'download_button.dart';

/// A fixed-width episode with a single playback stop and explicit actions.
class EpisodeCard extends StatefulWidget {
  final SeriesEpisode episode;
  final VoidCallback onPlay;
  final VoidCallback onToggleWatched;
  final bool watched;
  final double? progress;
  final int? seriesTmdbId;
  final String? seriesImage;
  const EpisodeCard({
    super.key,
    required this.episode,
    required this.onPlay,
    required this.onToggleWatched,
    this.watched = false,
    this.progress,
    this.seriesTmdbId,
    this.seriesImage,
  });
  @override
  State<EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<EpisodeCard> {
  late final FocusNode _play = EpisodePlaybackFocusNode(
    widget.episode.channel.id,
  );
  late final FocusNode _download = FocusNode(
    debugLabel: 'episode-download:${widget.episode.channel.id}',
  );
  late final FocusNode _info = FocusNode(
    debugLabel: 'episode-info:${widget.episode.channel.id}',
  );
  late final FocusNode _watched = FocusNode(
    debugLabel: 'episode-watched:${widget.episode.channel.id}',
  );
  @override
  void dispose() {
    _play.dispose();
    _download.dispose();
    _watched.dispose();
    _info.dispose();
    super.dispose();
  }

  KeyEventResult _arrows(FocusNode node, KeyEvent event) {
    if (!DeviceTypeService.isTv ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent))
      return KeyEventResult.ignored;
    final key = event.logicalKey;
    final available = DownloadService.canDownload(widget.episode.channel);
    if (_play.hasFocus && key == LogicalKeyboardKey.arrowDown) {
      (available ? _download : _watched).requestFocus();
      return KeyEventResult.handled;
    }
    if (_download.hasFocus || _watched.hasFocus || _info.hasFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        _play.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        if (key == LogicalKeyboardKey.arrowRight) {
          if (_download.hasFocus)
            _watched.requestFocus();
          else if (_watched.hasFocus)
            _info.requestFocus();
        }
        if (key == LogicalKeyboardKey.arrowLeft && _info.hasFocus) {
          _watched.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft &&
            _watched.hasFocus &&
            available)
          _download.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _showPlot(String plot, EpisodeMetadata? metadata) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '${widget.episode.code} · ${metadata?.title.isNotEmpty == true ? metadata?.title : widget.episode.title}',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (metadata != null) EpisodeRatingBadge(metadata),
              const SizedBox(height: 12),
              Text(plot.isEmpty ? 'Trama non disponibile' : plot),
            ],
          ),
        ),
        actions: [
          TvFocusable(
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext),
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Chiudi'),
            ),
          ),
        ],
      ),
    );
    if (mounted) _info.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    final onPlay = widget.onPlay;
    final onToggleWatched = widget.onToggleWatched;
    final watched = widget.watched;
    final progress = widget.progress;
    final service = EpisodeMetadataService.instance;
    final id = widget.seriesTmdbId;
    if (id != null)
      service.bind(episode.channel, id, episode.season, episode.number);
    return ListenableBuilder(
      listenable: service.store,
      builder: (context, _) {
        final metadata = service.forChannel(episode.channel);
        final images = episodeArtwork(
          metadata,
          episode.image ?? episode.channel.logo,
          widget.seriesImage,
        );
        final plot = episodeSynopsis(
          metadata?.overview,
          episode.overview,
          null,
        );
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _arrows,
          child: SizedBox(
            width: 284,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TvFocusable(
                  focusNode: _play,
                  onPressed: onPlay,
                  focusedScale: 1.02,
                  child: InkWell(
                    onTap: onPlay,
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                PosterImage(
                                  url: images.firstOrNull,
                                  fallbackUrls: images.skip(1).toList(),
                                ),
                                EpisodeStillOverlay(
                                  watched: watched,
                                  progress: progress,
                                  showPlay: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                          child: Text(
                            '${episode.code} · ${episode.title}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (episode.duration case final duration?)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${duration.inMinutes} min',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (metadata != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: EpisodeRatingBadge(metadata),
                  ),
                if (plot.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: Text(
                      plot,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    DownloadButton(
                      channel: episode.channel,
                      focusNode: _download,
                    ),
                    const Spacer(),
                    TvFocusable(
                      focusNode: _watched,
                      onPressed: onToggleWatched,
                      child: IconButton(
                        tooltip: watched
                            ? 'Segna come non visto'
                            : 'Segna come visto',
                        onPressed: onToggleWatched,
                        icon: Icon(
                          watched
                              ? Icons.check_circle_rounded
                              : Icons.check_circle_outline_rounded,
                          color: watched
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    TvFocusable(
                      focusNode: _info,
                      onPressed: () => _showPlot(plot, metadata),
                      child: IconButton(
                        tooltip: 'Trama episodio',
                        icon: const Icon(Icons.info_outline_rounded),
                        onPressed: () => _showPlot(plot, metadata),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
