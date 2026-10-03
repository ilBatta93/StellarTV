import 'package:flutter/material.dart';

import '../../player/playback_session.dart';
import 'player_format.dart';

class PlayerStats extends StatelessWidget {
  final PlaybackSession session;

  const PlayerStats({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final v = session.value;
    final buffer = v.bufferedUntil > v.position
        ? v.bufferedUntil - v.position
        : Duration.zero;
    final rows = <(String, String)>[
      ('Motore', session.engine?.type.label ?? '-'),
      ('Risoluzione',
          v.hasVideoSize ? '${v.size.width.round()}x${v.size.height.round()}' : '-'),
      ('Proporzioni', v.hasVideoSize ? v.aspectRatio.toStringAsFixed(2) : '-'),
      ('Stato', v.isBuffering ? 'Buffering' : v.isPlaying ? 'In riproduzione' : 'In pausa'),
      ('Posizione', session.isLive ? 'Diretta' : formatDuration(v.position)),
      if (buffer > Duration.zero) ('Buffer', '${buffer.inSeconds} s'),
      ('Velocità', formatSpeed(v.speed)),
      ('Formato', session.fitMode.label),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          height: 1.5,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, value) in rows)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(label,
                        style: const TextStyle(color: Colors.white60)),
                  ),
                  Text(value),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
