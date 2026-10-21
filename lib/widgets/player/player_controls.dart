import 'package:flutter/material.dart';

import '../../models/channel.dart';
import '../../player/playback_session.dart';
import '../../theme/app_theme.dart';
import '../channel_card.dart';
import '../tv_focusable.dart';
import '../../services/device_type_service.dart';
import 'player_format.dart';
import 'tv_player_controls.dart' show TimeshiftBadge;
import 'player_sheets.dart';
import 'seek_time_bubble.dart';

class PlayerControls extends StatelessWidget {
  final PlaybackSession session;
  final FocusNode? playFocusNode;
  final String title;
  final String subtitle;
  final bool locked;
  final bool pipSupported;
  final int seekStepSeconds;
  final Channel? previousChannel;
  final Channel? nextChannel;
  final VoidCallback onPreviousChannel;
  final VoidCallback onNextChannel;
  final VoidCallback onBack;

  /// Opens the movie/series page; null for live TV (button hidden).
  final VoidCallback? onOpenTitle;
  final VoidCallback? onEpisodes;
  final VoidCallback? onMultiView;
  final VoidCallback onPip;
  final VoidCallback onToggleLock;
  final VoidCallback onInteraction;

  /// Sottotitoli online (OpenSubtitles): stato e azioni del foglio.
  final bool onlineSubsActive;
  final bool onlineSubsLoading;
  final VoidCallback? onLoadOnlineSubs;
  final VoidCallback? onDisableOnlineSubs;

  const PlayerControls({
    super.key,
    required this.session,
    this.playFocusNode,
    required this.title,
    required this.subtitle,
    required this.locked,
    required this.pipSupported,
    required this.seekStepSeconds,
    required this.previousChannel,
    required this.nextChannel,
    required this.onPreviousChannel,
    required this.onNextChannel,
    required this.onBack,
    this.onOpenTitle,
    this.onEpisodes,
    this.onMultiView,
    required this.onPip,
    required this.onToggleLock,
    required this.onInteraction,
    this.onlineSubsActive = false,
    this.onlineSubsLoading = false,
    this.onLoadOnlineSubs,
    this.onDisableOnlineSubs,
  });

  void _act(VoidCallback action) {
    onInteraction();
    action();
  }

  @override
  Widget build(BuildContext context) {
    if (locked) {
      return SafeArea(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _RoundButton(
              icon: Icons.lock_rounded,
              focusNode: playFocusNode,
              tooltip: 'Sblocca comandi',
              onPressed: onToggleLock,
            ),
          ),
        ),
      );
    }

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
                stops: [0, 0.3, 0.6, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildTopBar(context),
                const Spacer(),
                _buildCenter(),
                const Spacer(),
                _buildBottom(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final engine = session.engine;
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Row(
        children: [
          _TopButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Indietro',
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
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
                    color: AppColors.onOverlay,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.onOverlaySecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (onMultiView case final openMultiView?)
            _TopButton(
              icon: Icons.grid_view_rounded,
              tooltip: 'MultiView',
              onPressed: openMultiView,
            ),
          if (onEpisodes case final openEpisodes?)
            _TopButton(
              icon: Icons.video_library_rounded,
              tooltip: 'Stagioni ed episodi',
              onPressed: openEpisodes,
            ),
          if (onOpenTitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _TopChip(
                icon: Icons.info_outline_rounded,
                label: 'Scheda titolo',
                onPressed: onOpenTitle!,
              ),
            ),
          if (engine != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _TopChip(
                icon: Icons.memory_rounded,
                label: engine.type.label,
                onPressed: () => _act(() => showEngineSheet(context, session)),
              ),
            ),
          if (pipSupported)
            _TopButton(
              tooltip: 'Picture-in-Picture',
              icon: Icons.picture_in_picture_alt_rounded,
              onPressed: onPip,
            ),
        ],
      ),
    );
  }

  Widget _buildCenter() {
    final v = session.value;
    final previousLive = previousChannel;
    final nextLive = nextChannel;
    final step = Duration(seconds: seekStepSeconds);
    final canSeek = !session.isLive && v.duration > Duration.zero;
    final ended = !session.isLive && v.isEnded;
    final playing = !session.liveResumePending && v.isPlaying;
    final playIcon = ended
        ? Icons.replay_rounded
        : playing
        ? Icons.pause_rounded
        : Icons.play_arrow_rounded;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (session.isLive)
          _RoundButton(
            icon: Icons.skip_previous_rounded,
            tooltip: previousLive == null
                ? 'Nessun canale precedente'
                : 'Canale precedente: ${previousLive.name}',
            onPressed: previousLive == null ? null : onPreviousChannel,
          )
        else if (canSeek)
          _RoundButton(
            icon: Icons.replay_rounded,
            label: '${step.inSeconds}',
            tooltip: 'Indietro di ${step.inSeconds} secondi',
            onPressed: () => _act(() => session.seekBy(-step)),
          ),
        if (session.isLive && session.canTimeshift) ...[
          const SizedBox(width: 20),
          _RoundButton(
            icon: Icons.replay_10_rounded,
            tooltip: 'Indietro di ${step.inSeconds} secondi',
            onPressed: () => _act(() => session.timeshiftBy(-step)),
          ),
        ],
        const SizedBox(width: 32),
        v.isBuffering && !v.isPlaying
            ? SizedBox(
                width: 72,
                height: 72,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 3,
                  ),
                ),
              )
            : _RoundButton(
                icon: playIcon,
                focusNode: playFocusNode,
                size: 72,
                filled: true,
                tooltip: ended ? 'Riproduci di nuovo' : playing ? 'Pausa' : 'Riproduci',
                onPressed: () => _act(session.togglePlay),
              ),
        const SizedBox(width: 32),
        if (session.isLive && session.canTimeshift) ...[
          _RoundButton(
            icon: Icons.forward_10_rounded,
            tooltip: 'Avanti di ${step.inSeconds} secondi',
            onPressed: session.isBehindLive
                ? () => _act(() => session.timeshiftBy(step))
                : null,
          ),
          const SizedBox(width: 20),
        ],
        if (session.isLive)
          _RoundButton(
            icon: Icons.skip_next_rounded,
            tooltip: nextLive == null
                ? 'Nessun canale successivo'
                : 'Canale successivo: ${nextLive.name}',
            onPressed: nextLive == null ? null : onNextChannel,
          )
        else if (canSeek)
          _RoundButton(
            icon: Icons.forward_rounded,
            label: '${step.inSeconds}',
            tooltip: 'Avanti di ${step.inSeconds} secondi',
            onPressed: () => _act(() => session.seekBy(step)),
          ),
      ],
    );
  }

  Widget _buildBottom(BuildContext context) {
    final v = session.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (session.isLive)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: session.isBehindLive
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TimeshiftBadge(delay: session.liveDelay),
                        const SizedBox(width: 10),
                        TextButton.icon(
                          onPressed: () => _act(session.goLive),
                          icon: const Icon(Icons.sensors_rounded),
                          label: const Text('Torna in LIVE'),
                        ),
                      ],
                    )
                  : const LiveBadge(),
            ),
          )
        else
          _ScrubBar(
            position: v.position,
            duration: v.duration,
            buffered: v.bufferedUntil,
            onSeek: (d) => _act(() => session.seekTo(d)),
            onInteraction: onInteraction,
          ),
        FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Row(
            children: [
              _BarButton(
                icon: session.muted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                label: session.muted ? 'Muto' : 'Volume',
                onPressed: () => _act(session.toggleMute),
              ),
              _BarButton(
                icon: Icons.lock_open_rounded,
                label: 'Blocca',
                onPressed: () => _act(onToggleLock),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _BarButton(
                          icon: Icons.audiotrack_rounded,
                          label: 'Audio',
                          onPressed: () =>
                              _act(() => showAudioSheet(context, session)),
                        ),
                        _BarButton(
                          icon: Icons.subtitles_rounded,
                          label: onlineSubsActive
                              ? 'ITA online'
                              : 'Sottotitoli',
                          onPressed: () => _act(
                            () => showSubtitleSheet(
                              context,
                              session,
                              onlineActive: onlineSubsActive,
                              onlineLoading: onlineSubsLoading,
                              onLoadOnline: onLoadOnlineSubs,
                              onDisableOnline: onDisableOnlineSubs,
                            ),
                          ),
                        ),
                        if (!session.isLive)
                          _BarButton(
                            icon: Icons.speed_rounded,
                            label: formatSpeed(session.speed),
                            onPressed: () =>
                                _act(() => showSpeedSheet(context, session)),
                          ),
                        _BarButton(
                          icon: Icons.aspect_ratio_rounded,
                          label: session.fitMode.label,
                          onPressed: () =>
                              _act(() => showFitSheet(context, session)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScrubBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onInteraction;

  const _ScrubBar({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
    required this.onInteraction,
  });

  @override
  State<_ScrubBar> createState() => _ScrubBarState();
}

class _ScrubBarState extends State<_ScrubBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds;
    double frac(Duration d) =>
        total <= 0 ? 0 : (d.inMilliseconds / total).clamp(0.0, 1.0);
    final value = _dragValue ?? frac(widget.position);
    final shown = _dragValue != null
        ? Duration(milliseconds: (_dragValue! * total).round())
        : widget.position;
    const timeStyle = TextStyle(
      color: AppColors.onOverlay,
      fontSize: 12,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(formatDuration(shown), style: timeStyle),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                clipBehavior: Clip.none,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: AppColors.track,
                      secondaryActiveTrackColor: AppColors.bufferedTrack,
                      thumbColor: AppColors.primary,
                      overlayColor: AppColors.primary.withValues(alpha: 0.2),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                    ),
                    child: Slider(
                      value: value,
                      secondaryTrackValue: frac(widget.buffered),
                      onChangeStart: (v) {
                        widget.onInteraction();
                        setState(() => _dragValue = v);
                      },
                      onChanged: total <= 0
                          ? null
                          : (v) {
                              widget.onInteraction();
                              setState(() => _dragValue = v);
                            },
                      onChangeEnd: (v) {
                        setState(() => _dragValue = null);
                        widget.onSeek(
                          Duration(milliseconds: (v * total).round()),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    // Slider track is inset by the 24 px overlay radius.
                    left: SeekTimeBubble.leftFor(
                      24 + (box.maxWidth - 48) * value,
                      box.maxWidth,
                    ),
                    bottom: 40,
                    child: SeekTimeBubble(
                      time: shown,
                      visible: _dragValue != null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Text(formatDuration(widget.duration), style: timeStyle),
        ],
      ),
    );
  }
}

class _TopButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _TopButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: AppColors.onOverlay),
      onPressed: onPressed,
    );
    if (!DeviceTypeService.isTv) return button;
    return TvFocusable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(24),
      child: button,
    );
  }
}

class _TopChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _TopChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final chip = ActionChip(
      onPressed: onPressed,
      avatar: Icon(icon, size: 16, color: AppColors.onOverlay),
      label: Text(label),
      labelStyle: const TextStyle(
        color: AppColors.onOverlay,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: AppColors.overlayControl,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      visualDensity: VisualDensity.compact,
    );
    if (!DeviceTypeService.isTv) return chip;
    return TvFocusable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(24),
      child: chip,
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final String tooltip;
  final FocusNode? focusNode;
  final double size;
  final bool filled;
  final VoidCallback? onPressed;

  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.label,
    this.focusNode,
    this.size = 52,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = Tooltip(
      message: tooltip,
      child: Material(
        color: onPressed == null
            ? AppColors.overlayControl
            : filled
            ? AppColors.primary
            : AppColors.overlayControl,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  icon,
                  color: onPressed == null
                      ? AppColors.onOverlayDisabled
                      : AppColors.onOverlay,
                  size: size * 0.55,
                ),
                if (label != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      label!,
                      style: const TextStyle(
                        color: AppColors.onOverlay,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!DeviceTypeService.isTv || onPressed == null) return button;
    return TvFocusable(
      focusNode: focusNode,
      onPressed: onPressed ?? () {},
      borderRadius: BorderRadius.circular(size),
      child: button,
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _BarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final button = TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.onOverlay,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label),
      onPressed: onPressed,
    );
    return TvFocusable(onPressed: onPressed, child: button);
  }
}
