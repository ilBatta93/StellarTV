import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../channel_card.dart';
import 'player_format.dart';
import 'seek_time_bubble.dart';

/// Rows of the TV player overlay, from top to bottom.
enum TvPlayerRowKind { top, center, progress, bottom }

/// One on-screen command of the TV player.
class TvPlayerAction {
  final String id;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Big round button (play/pause).
  final bool primary;

  const TvPlayerAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  bool get enabled => onPressed != null;
}

class TvPlayerRow {
  final TvPlayerRowKind kind;
  final List<TvPlayerAction> actions;
  const TvPlayerRow(this.kind, this.actions);
}

/// Remote-only player overlay.
///
/// It owns no focus nodes: the player screen keeps the keyboard focus and
/// moves a highlighted (row, column) selection itself. This avoids every
/// focus trap of the generic widgets (sliders eating the arrows, buttons
/// disappearing while buffering, scrollable rows, overlays stealing focus),
/// which made the player controls unreachable with a remote.
class TvPlayerControls extends StatelessWidget {
  final List<TvPlayerRow> rows;
  final TvPlayerRowKind selectedRow;
  final int selectedColumn;
  final String title;
  final String subtitle;
  final bool isLive;
  final bool locked;
  final Duration position;
  final Duration duration;
  final Duration buffered;

  /// Target of a seek still being composed with left/right.
  final Duration? pendingSeek;

  /// Live timeshift: how far behind the live point (null = at LIVE).
  final Duration? liveDelay;

  const TvPlayerControls({
    super.key,
    required this.rows,
    required this.selectedRow,
    required this.selectedColumn,
    required this.title,
    required this.subtitle,
    required this.isLive,
    required this.locked,
    required this.position,
    required this.duration,
    required this.buffered,
    this.pendingSeek,
    this.liveDelay,
  });

  TvPlayerRow? _row(TvPlayerRowKind kind) {
    for (final r in rows) {
      if (r.kind == kind) return r;
    }
    return null;
  }

  bool _isSelected(TvPlayerRowKind kind, int index) =>
      selectedRow == kind && selectedColumn == index;

  @override
  Widget build(BuildContext context) {
    if (locked) {
      final center = _row(TvPlayerRowKind.center);
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: center == null || center.actions.isEmpty
              ? const SizedBox.shrink()
              : _TvRoundButton(action: center.actions.first, selected: true),
        ),
      );
    }
    final top = _row(TvPlayerRowKind.top);
    final center = _row(TvPlayerRowKind.center);
    final progress = _row(TvPlayerRowKind.progress);
    final bottom = _row(TvPlayerRowKind.bottom);
    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.overlay,
                  AppColors.clear,
                  AppColors.clear,
                  AppColors.overlay,
                ],
                stops: [0, 0.28, 0.55, 1],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
          child: Column(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.onOverlay,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.onOverlaySecondary,
                        fontSize: 14,
                      ),
                    ),
                  if (top != null) ...[
                    const SizedBox(height: 12),
                    _TvActionStrip(
                      row: top,
                      selectedRow: selectedRow,
                      selectedColumn: selectedColumn,
                    ),
                  ],
                ],
              ),
              const Spacer(),
              if (center != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final (i, a) in center.actions.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: _TvRoundButton(
                          action: a,
                          selected: _isSelected(TvPlayerRowKind.center, i),
                        ),
                      ),
                  ],
                ),
              const Spacer(),
              if (isLive)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: liveDelay == null
                        ? const LiveBadge()
                        : TimeshiftBadge(delay: liveDelay!),
                  ),
                )
              else if (progress != null)
                _TvProgress(
                  position: position,
                  duration: duration,
                  buffered: buffered,
                  pendingSeek: pendingSeek,
                  selected: selectedRow == TvPlayerRowKind.progress,
                ),
              if (bottom != null)
                _TvActionStrip(
                  row: bottom,
                  selectedRow: selectedRow,
                  selectedColumn: selectedColumn,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fixed equal-width cells preserve the player's logical row/column mapping.
class _TvActionStrip extends StatelessWidget {
  final TvPlayerRow row;
  final TvPlayerRowKind selectedRow;
  final int selectedColumn;
  const _TvActionStrip({
    required this.row,
    required this.selectedRow,
    required this.selectedColumn,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (index, action) in row.actions.indexed)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _TvPill(
              action: action,
              selected: row.kind == selectedRow && index == selectedColumn,
            ),
          ),
        ),
    ],
  );
}

class _TvPill extends StatelessWidget {
  final TvPlayerAction action;
  final bool selected;
  const _TvPill({required this.action, required this.selected});

  @override
  Widget build(BuildContext context) {
    final enabled = action.enabled;
    final fg = selected
        ? AppColors.background
        : enabled
        ? AppColors.onOverlay.withValues(alpha: 0.9)
        : AppColors.onOverlayDisabled;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 110),
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.textPrimary : AppColors.overlayControl,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected ? AppColors.onOverlay : AppColors.clear,
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(action.icon, size: 22, color: fg),
          const SizedBox(height: 4),
          Text(
            action.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TvRoundButton extends StatelessWidget {
  final TvPlayerAction action;
  final bool selected;
  const _TvRoundButton({required this.action, required this.selected});

  @override
  Widget build(BuildContext context) {
    final size = action.primary ? 76.0 : 56.0;
    final enabled = action.enabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: selected && !MediaQuery.disableAnimationsOf(context)
              ? 1.12
              : 1,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 110),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? AppColors.textPrimary
                  : action.primary
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : AppColors.overlayControl,
              border: Border.all(
                color: selected ? AppColors.onOverlay : AppColors.track,
                width: selected ? 3 : 1,
              ),
            ),
            child: Icon(
              action.icon,
              size: size * 0.52,
              color: selected
                  ? AppColors.background
                  : enabled
                  ? AppColors.onOverlay
                  : AppColors.onOverlayDisabled,
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedOpacity(
          opacity: selected ? 1 : 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 110),
          child: Text(
            action.label,
            style: const TextStyle(
              color: AppColors.onOverlay,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _TvProgress extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final Duration? pendingSeek;
  final bool selected;

  const _TvProgress({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.pendingSeek,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    double frac(Duration d) =>
        total <= 0 ? 0 : (d.inMilliseconds / total).clamp(0.0, 1.0);
    final shown = pendingSeek ?? position;
    const timeStyle = TextStyle(
      color: AppColors.onOverlay,
      fontSize: 14,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(formatDuration(shown), style: timeStyle),
              const SizedBox(width: 14),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final w = box.maxWidth;
                    final still = MediaQuery.disableAnimationsOf(context);
                    final height = selected ? 8.0 : 4.0;
                    final thumb = selected ? 18.0 : 0.0;
                    return SizedBox(
                      height: 20,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        clipBehavior: Clip.none,
                        children: [
                          _bar(w, height, AppColors.track),
                          _bar(
                            w * frac(buffered),
                            height,
                            AppColors.bufferedTrack,
                          ),
                          _bar(w * frac(position), height, AppColors.primary),
                          if (pendingSeek != null)
                            _bar(
                              w * frac(pendingSeek!),
                              height,
                              AppColors.onOverlay.withValues(alpha: 0.85),
                            ),
                          if (selected)
                            AnimatedPositioned(
                              duration: still
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              left: (w * frac(shown) - thumb / 2).clamp(
                                -thumb / 2,
                                w - thumb / 2,
                              ),
                              child: Container(
                                width: thumb,
                                height: thumb,
                                decoration: BoxDecoration(
                                  color: AppColors.onOverlay,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          AnimatedPositioned(
                            duration: still
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            left: SeekTimeBubble.leftFor(w * frac(shown), w),
                            bottom: 22,
                            child: SeekTimeBubble(
                              time: shown,
                              visible: selected || pendingSeek != null,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 14),
              Text(formatDuration(duration), style: timeStyle),
            ],
          ),
          AnimatedOpacity(
            opacity: selected ? 1 : 0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 110),
            child: const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Riproduzione',
                style: TextStyle(
                  color: AppColors.onOverlaySecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(double width, double height, Color color) => AnimatedContainer(
    duration: const Duration(milliseconds: 90),
    width: width < 0 ? 0 : width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(height),
    ),
  );
}

/// "Press Back again" prompt shown before leaving the TV player.
class TvExitPrompt extends StatelessWidget {
  const TvExitPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.logout_rounded, color: AppColors.primary, size: 26),
          const SizedBox(width: 14),
          const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vuoi uscire dalla riproduzione?',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Premi di nuovo Indietro entro 3 secondi per uscire',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown instead of LIVE while the picture is behind the live point.
class TimeshiftBadge extends StatelessWidget {
  final Duration delay;
  const TimeshiftBadge({super.key, required this.delay});

  @override
  Widget build(BuildContext context) {
    final m = delay.inMinutes;
    final sec = (delay.inSeconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.overlayControl,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.onOverlayDisabled),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.history_rounded,
            color: AppColors.onOverlay,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'In differita  -$m:$sec',
            style: const TextStyle(
              color: AppColors.onOverlay,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
