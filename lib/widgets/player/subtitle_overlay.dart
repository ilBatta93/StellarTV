import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/player_settings.dart';
import '../../services/subtitles_service.dart';

/// Sottotitoli scaricati da OpenSubtitles, disegnati sopra il video.
/// Funziona con entrambi i motori perché non dipende dalle tracce
/// incorporate nel flusso.
///
/// The engine reports position only a few times per second (to keep video
/// smooth), so the overlay extrapolates it frame by frame while playing:
/// without this, every cue appeared up to a quarter of a second late.
class SubtitleOverlay extends StatefulWidget {
  final List<SubtitleCue> cues;
  final Duration position;
  final Duration delay;
  final PlayerSettings settings;
  final bool playing;

  const SubtitleOverlay({
    super.key,
    required this.cues,
    required this.position,
    required this.delay,
    required this.settings,
    this.playing = false,
  });

  @override
  State<SubtitleOverlay> createState() => _SubtitleOverlayState();
}

/// Extrapolated playback position: last reported position plus the wall
/// time since that report, capped so a stall never runs subtitles ahead.
Duration extrapolatePosition(
  Duration reported,
  Duration sinceReport, {
  required bool playing,
  Duration cap = const Duration(milliseconds: 600),
}) {
  if (!playing || sinceReport.isNegative) return reported;
  return reported + (sinceReport > cap ? cap : sinceReport);
}

class _SubtitleOverlayState extends State<SubtitleOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Stopwatch _sinceReport = Stopwatch()..start();
  String? _text;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _refresh());
    _sync();
  }

  @override
  void didUpdateWidget(SubtitleOverlay old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) _sinceReport.reset();
    _sync();
  }

  void _sync() {
    if (widget.playing && !_ticker.isActive) _ticker.start();
    if (!widget.playing && _ticker.isActive) _ticker.stop();
    _text = _compute();
  }

  String? _compute() => SubtitlesService.cueAt(
    widget.cues,
    extrapolatePosition(
      widget.position,
      _sinceReport.elapsed,
      playing: widget.playing,
    ),
    widget.delay,
  );

  void _refresh() {
    final next = _compute();
    if (next != _text) setState(() => _text = next);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final text = _text;
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
