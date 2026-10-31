import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/epg_program.dart';
import '../../theme/app_theme.dart';

/// Digit of a remote number key (top row or keypad), null otherwise.
int? remoteDigit(LogicalKeyboardKey key) {
  const top = [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  const pad = [
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];
  final i = top.indexOf(key);
  if (i >= 0) return i;
  final j = pad.indexOf(key);
  return j >= 0 ? j : null;
}

/// Resolution the stream really delivers ("4K", "1080p"...), from the
/// decoded picture; null while it is unknown.
String? liveQualityLabel(Size size) {
  final h = size.height;
  if (h <= 0) return null;
  if (h >= 2000) return '4K';
  if (h >= 1000) return '1080p';
  if (h >= 700) return '720p';
  return 'SD';
}

/// Channel banner shown for a few seconds when a live channel is tuned:
/// what is on now (times, progress) and what comes next. Guide data only:
/// no requests, artwork or polling.
class TvLiveBanner extends StatelessWidget {
  final String channelName;
  final int? number;
  final EpgProgram? now;
  final EpgProgram? next;
  final String? qualityLabel;

  const TvLiveBanner({
    super.key,
    required this.channelName,
    this.number,
    this.now,
    this.next,
    this.qualityLabel,
  });

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Share of [program] already aired at [at], 0..1.
  static double progressOf(EpgProgram program, DateTime at) {
    final total = program.endTime.difference(program.startTime).inSeconds;
    if (total <= 0) return 0;
    final done = at.difference(program.startTime).inSeconds;
    return (done / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final current = now;
    final upcoming = next;
    final clock = DateTime.now();
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.fromLTRB(48, 0, 48, 40),
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            constraints: const BoxConstraints(maxWidth: 1100),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (number != null) ...[
                      Text(
                        '$number',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Flexible(
                      child: Text(
                        channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.onOverlay,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (qualityLabel != null) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.onOverlay),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          qualityLabel!,
                          style: const TextStyle(
                            color: AppColors.onOverlay,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      _clock(clock),
                      style: const TextStyle(
                        color: AppColors.onOverlaySecondary,
                        fontSize: 18,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (current == null)
                  const Text(
                    'Programmazione non disponibile',
                    style: TextStyle(
                      color: AppColors.onOverlaySecondary,
                      fontSize: 17,
                    ),
                  )
                else ...[
                  Text(
                    '${current.timeRange}  ${current.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.onOverlay,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progressOf(current, clock),
                      minHeight: 4,
                      color: AppColors.primary,
                      backgroundColor: AppColors.track,
                    ),
                  ),
                  if (current.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      current.description.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.onOverlaySecondary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ],
                if (upcoming != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Dopo · ${_clock(upcoming.startTime)}  ${upcoming.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.onOverlaySecondary,
                      fontSize: 15,
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
