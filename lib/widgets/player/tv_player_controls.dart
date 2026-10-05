import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../channel_card.dart';
import 'player_format.dart';

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
                  Color(0xD9000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0xF2000000),
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
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
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
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (top != null)
                    for (final (i, a) in top.actions.indexed)
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: _TvPill(
                          action: a,
                          selected: _isSelected(TvPlayerRowKind.top, i),
                        ),
                      ),
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
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: LiveBadge(),
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
                Row(
                  children: [
                    for (final (i, a) in bottom.actions.indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _TvPill(
                          action: a,
                          selected: _isSelected(TvPlayerRowKind.bottom, i),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TvPill extends StatelessWidget {
  final TvPlayerAction action;
  final bool selected;
  const _TvPill({required this.action, required this.selected});

  @override
  Widget build(BuildContext context) {
    final enabled = action.enabled;
    final fg = selected
        ? Colors.white
        : enabled
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.white38;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected ? Colors.white : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(action.icon, size: 20, color: fg),
          const SizedBox(width: 6),
          Text(
            action.label,
            style: TextStyle(
              color: fg,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
          scale: selected ? 1.12 : 1,
          duration: const Duration(milliseconds: 110),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? AppColors.primary
                  : action.primary
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : Colors.black.withValues(alpha: enabled ? 0.45 : 0.2),
              border: Border.all(
                color: selected ? Colors.white : Colors.white24,
                width: selected ? 3 : 1,
              ),
            ),
            child: Icon(
              action.icon,
              size: size * 0.52,
              color: enabled ? Colors.white : Colors.white30,
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedOpacity(
          opacity: selected ? 1 : 0,
          duration: const Duration(milliseconds: 110),
          child: Text(
            action.label,
            style: const TextStyle(
              color: Colors.white,
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
      color: Colors.white,
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
                    final height = selected ? 8.0 : 4.0;
                    final thumb = selected ? 18.0 : 0.0;
                    return SizedBox(
                      height: 20,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        clipBehavior: Clip.none,
                        children: [
                          _bar(w, height, Colors.white24),
                          _bar(w * frac(buffered), height, Colors.white54),
                          _bar(w * frac(position), height, AppColors.primary),
                          if (pendingSeek != null)
                            _bar(
                              w * frac(pendingSeek!),
                              height,
                              Colors.white.withValues(alpha: 0.85),
                            ),
                          if (selected)
                            Positioned(
                              left: (w * frac(shown) - thumb / 2).clamp(
                                -thumb / 2,
                                w - thumb / 2,
                              ),
                              child: Container(
                                width: thumb,
                                height: thumb,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 3,
                                  ),
                                ),
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
            duration: const Duration(milliseconds: 110),
            child: const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '◀ ▶ per spostarti nel video · OK per pausa',
                style: TextStyle(color: Colors.white70, fontSize: 12),
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
