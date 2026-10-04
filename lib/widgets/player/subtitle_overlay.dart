import 'package:flutter/material.dart';

import '../../models/player_settings.dart';
import '../../services/subtitles_service.dart';

/// Sottotitoli scaricati da OpenSubtitles, disegnati sopra il video.
/// Funziona con entrambi i motori perché non dipende dalle tracce
/// incorporate nel flusso.
class SubtitleOverlay extends StatelessWidget {
  final List<SubtitleCue> cues;
  final Duration position;
  final Duration delay;
  final PlayerSettings settings;

  const SubtitleOverlay({
    super.key,
    required this.cues,
    required this.position,
    required this.delay,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final text = SubtitlesService.cueAt(cues, position, delay);
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
            child: Container(
              padding: settings.subtitleBackground
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                  : EdgeInsets.zero,
              decoration: settings.subtitleBackground
                  ? BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                    )
                  : null,
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: settings.subtitleColor.color,
                  fontSize: settings.subtitleSize.fontSize,
                  fontWeight: settings.subtitleBold
                      ? FontWeight.w700
                      : FontWeight.w500,
                  height: 1.3,
                  shadows: settings.subtitleBackground
                      ? null
                      : const [
                          Shadow(color: Colors.black, blurRadius: 4),
                          Shadow(color: Colors.black, blurRadius: 12),
                        ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
