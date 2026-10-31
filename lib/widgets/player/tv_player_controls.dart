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
/// moves a highlighted (row, column) selection itself, so the arrows are
/// not captured by a Flutter focus tree. The center row is the only
/// high-contrast transport. Audio, subtitles, speed and picture fit stay
/// on the bottom row, quieter, because Down already opens that panel.
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
              secondary: row.kind == TvPlayerRowKind.bottom,
            ),
          ),
        ),
    ],
  );
}

class _TvPill extends StatelessWidget {
  final TvPlayerAction action;
  final bool selected;
  final bool secondary;
  const _TvPill({
    required this.action,
    required this.selected,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = action.enabled;
    final fg = !enabled
        ? AppColors.onOverlayDisabled
        : selected
        ? AppColors.onOverlay
        : secondary
        ? AppColors.onOverlaySecondary
        : AppColors.onOverlay.withValues(alpha: 0.9);
    return AnimatedScale(
      scale: selected && !MediaQuery.disableAnimationsOf(context) ? 1.06 : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 110),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 110),
        height: 52,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.overlayControl.withValues(
            alpha: secondary ? 0.34 : 1,
          ),
          borderRadius: BorderRadius.circular(secondary ? 16 : 22),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.clear,
            width: AppTheme.focusRingWidth,
          ),
        ),
        // The selected control also shows its name: an icon alone did not
        // say what it does from the sofa.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, size: secondary ? 20 : 22, color: fg),
            if (selected) const SizedBox(width: 8),
            if (selected)
              Flexible(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: secondary ? 14 : 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
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
              ? 1.06
              : 1,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 110),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: action.primary
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : AppColors.overlayControl,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.track,
                width: AppTheme.focusRingWidth,
              ),
            ),
            child: Icon(
              action.icon,
              size: size * 0.52,
              color: enabled
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
    // tvOS-style glass pill: quiet, rounded, no hard accent frame.
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: DecoratedBox(
        decoration: const BoxDecoration(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.logout_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Uscire dalla riproduzione?',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Premi di nuovo Indietro per confermare',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
