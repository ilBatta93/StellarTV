import 'package:flutter/material.dart';

import '../../player/playback_session.dart';
import '../../theme/app_theme.dart';
import '../channel_card.dart';
import 'player_format.dart';
import 'player_sheets.dart';

class PlayerControls extends StatelessWidget {
  final PlaybackSession session;
  final String title;
  final String subtitle;
  final bool locked;
  final bool pipSupported;
  final int seekStepSeconds;
  final VoidCallback onBack;
  final VoidCallback onPip;
  final VoidCallback onMenu;
  final VoidCallback onToggleLock;
  final VoidCallback onInteraction;

  const PlayerControls({
    super.key,
    required this.session,
    required this.title,
    required this.subtitle,
    required this.locked,
    required this.pipSupported,
    required this.seekStepSeconds,
    required this.onBack,
    required this.onPip,
    required this.onMenu,
    required this.onToggleLock,
    required this.onInteraction,
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
                colors: [Color(0xCC000000), Color(0x00000000), Color(0x00000000), Color(0xE6000000)],
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
    return Row(
      children: [
        IconButton(
          tooltip: 'Indietro',
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: onBack,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.2)),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        if (engine != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ActionChip(
              onPressed: () => _act(() => showEngineSheet(context, session)),
              avatar: const Icon(Icons.memory_rounded, size: 16, color: Colors.white),
              label: Text(engine.type.label),
              labelStyle: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              side: BorderSide.none,
              shape: const StadiumBorder(),
              visualDensity: VisualDensity.compact,
            ),
          ),
        if (pipSupported)
          IconButton(
            tooltip: 'Picture-in-Picture',
            icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white),
            onPressed: onPip,
          ),
        IconButton(
          tooltip: 'Opzioni',
          icon: const Icon(Icons.tune_rounded, color: Colors.white),
          onPressed: onMenu,
        ),
      ],
    );
  }

  Widget _buildCenter() {
    final v = session.value;
    final step = Duration(seconds: seekStepSeconds);
    final canSeek = !session.isLive && v.duration > Duration.zero;
    final playIcon = v.isEnded
        ? Icons.replay_rounded
        : v.isPlaying
            ? Icons.pause_rounded
            : Icons.play_arrow_rounded;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (canSeek)
          _RoundButton(
            icon: Icons.replay_rounded,
            label: '${step.inSeconds}',
            tooltip: 'Indietro di ${step.inSeconds} secondi',
            onPressed: () => _act(() => session.seekBy(-step)),
          ),
        const SizedBox(width: 32),
        v.isBuffering && !v.isPlaying
            ? SizedBox(
                width: 72,
                height: 72,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
                ),
              )
            : _RoundButton(
                icon: playIcon,
                size: 72,
                filled: true,
                tooltip: v.isPlaying ? 'Pausa' : 'Riproduci',
                onPressed: () => _act(session.togglePlay),
              ),
        const SizedBox(width: 32),
        if (canSeek)
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(alignment: Alignment.centerLeft, child: LiveBadge()),
          )
        else
          _ScrubBar(
            position: v.position,
            duration: v.duration,
            buffered: v.bufferedUntil,
            onSeek: (d) => _act(() => session.seekTo(d)),
            onInteraction: onInteraction,
          ),
        Row(
          children: [
            _BarButton(
              icon: session.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              label: session.muted ? 'Muto' : 'Volume',
              onPressed: () => _act(session.toggleMute),
            ),
            _BarButton(
              icon: Icons.lock_open_rounded,
              label: 'Blocca',
              onPressed: () => _act(onToggleLock),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  children: [
                    _BarButton(
                      icon: Icons.audiotrack_rounded,
                      label: 'Audio',
                      onPressed: () => _act(() => showAudioSheet(context, session)),
                    ),
                    _BarButton(
                      icon: Icons.subtitles_rounded,
                      label: 'Sottotitoli',
                      onPressed: () => _act(() => showSubtitleSheet(context, session)),
                    ),
                    if (!session.isLive)
                      _BarButton(
                        icon: Icons.speed_rounded,
                        label: formatSpeed(session.speed),
                        onPressed: () => _act(() => showSpeedSheet(context, session)),
                      ),
                    _BarButton(
                      icon: Icons.aspect_ratio_rounded,
                      label: session.fitMode.label,
                      onPressed: () => _act(() => showFitSheet(context, session)),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
        color: Colors.white, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(formatDuration(shown), style: timeStyle),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: Colors.white24,
                secondaryActiveTrackColor: Colors.white54,
                thumbColor: AppColors.primary,
                overlayColor: AppColors.primary.withValues(alpha: 0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
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
                  widget.onSeek(Duration(milliseconds: (v * total).round()));
                },
              ),
            ),
          ),
          Text(formatDuration(widget.duration), style: timeStyle),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final String tooltip;
  final double size;
  final bool filled;
  final VoidCallback onPressed;

  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.label,
    this.size = 52,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled
            ? AppColors.primary
            : Colors.black.withValues(alpha: 0.35),
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
                Icon(icon, color: Colors.white, size: size * 0.55),
                if (label != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(label!,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _BarButton(
      {required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}
