import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/player_settings.dart';
import '../../player/playback_session.dart';
import '../../services/native_player_bridge.dart';
import '../../theme/app_theme.dart';
import 'player_format.dart';

enum _DragKind { none, brightness, volume, seek }

class PlayerGestureLayer extends StatefulWidget {
  final PlaybackSession session;
  final PlayerSettings settings;
  final bool locked;
  final VoidCallback onTap;
  final VoidCallback onInteraction;

  const PlayerGestureLayer({
    super.key,
    required this.session,
    required this.settings,
    required this.locked,
    required this.onTap,
    required this.onInteraction,
  });

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  _DragKind _drag = _DragKind.none;
  double _level = 0;
  Duration _seekTarget = Duration.zero;
  Duration _seekOrigin = Duration.zero;
  Offset? _doubleTapAt;
  String? _flash;
  bool _flashLeft = false;
  Timer? _flashTimer;
  Timer? _hudTimer;

  PlaybackSession get _session => widget.session;
  bool get _canSeek =>
      !_session.isLive && _session.value.duration > Duration.zero;

  @override
  void dispose() {
    _flashTimer?.cancel();
    _hudTimer?.cancel();
    super.dispose();
  }

  void _showFlash(String text, bool left) {
    _flashTimer?.cancel();
    setState(() {
      _flash = text;
      _flashLeft = left;
    });
    _flashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _onDoubleTap() {
    final at = _doubleTapAt;
    if (at == null) return;
    final width = context.size?.width ?? 1;
    final step = Duration(seconds: widget.settings.seekStepSeconds);
    if (_canSeek && at.dx < width / 3) {
      _session.seekBy(-step);
      _showFlash('-${step.inSeconds}s', true);
    } else if (_canSeek && at.dx > width * 2 / 3) {
      _session.seekBy(step);
      _showFlash('+${step.inSeconds}s', false);
    } else {
      _session.togglePlay();
    }
    widget.onInteraction();
  }

  Future<void> _onVerticalStart(DragStartDetails d) async {
    final width = context.size?.width ?? 1;
    final left = d.localPosition.dx < width / 2;
    _hudTimer?.cancel();
    if (left) {
      final current = await NativePlayerBridge.instance.getBrightness();
      if (!mounted) return;
      setState(() {
        _drag = _DragKind.brightness;
        _level = current ?? 0.5;
      });
    } else {
      setState(() {
        _drag = _DragKind.volume;
        _level = _session.muted ? 0 : _session.volume;
      });
    }
  }

  void _onVerticalUpdate(DragUpdateDetails d) {
    if (_drag != _DragKind.brightness && _drag != _DragKind.volume) return;
    final height = context.size?.height ?? 1;
    final next = (_level - d.delta.dy / (height * 0.8)).clamp(0.0, 1.0);
    setState(() => _level = next);
    if (_drag == _DragKind.brightness) {
      NativePlayerBridge.instance.setBrightness(next);
    } else {
      _session.setVolume(next);
    }
  }

  void _onHorizontalStart(DragStartDetails d) {
    if (!_canSeek) return;
    _hudTimer?.cancel();
    setState(() {
      _drag = _DragKind.seek;
      _seekOrigin = _session.value.position;
      _seekTarget = _seekOrigin;
    });
  }

  void _onHorizontalUpdate(DragUpdateDetails d) {
    if (_drag != _DragKind.seek) return;
    final width = context.size?.width ?? 1;
    final total = _session.value.duration;
    // A full-width swipe scrubs through 90 seconds or a fifth of the title.
    final span = total.inSeconds < 450 ? 90 : total.inSeconds ~/ 5;
    final deltaMs = (d.delta.dx / width * span * 1000).round();
    var next = _seekTarget + Duration(milliseconds: deltaMs);
    if (next < Duration.zero) next = Duration.zero;
    if (next > total) next = total;
    setState(() => _seekTarget = next);
  }

  void _endDrag() {
    if (_drag == _DragKind.seek) _session.seekTo(_seekTarget);
    widget.onInteraction();
    _hudTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _drag = _DragKind.none);
    });
  }

  @override
  Widget build(BuildContext context) {
    final gestures = widget.settings.gesturesEnabled && !widget.locked;
    final doubleTap = widget.settings.doubleTapSeek && !widget.locked;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: doubleTap ? (d) => _doubleTapAt = d.localPosition : null,
      onDoubleTap: doubleTap ? _onDoubleTap : null,
      onVerticalDragStart: gestures ? _onVerticalStart : null,
      onVerticalDragUpdate: gestures ? _onVerticalUpdate : null,
      onVerticalDragEnd: gestures ? (_) => _endDrag() : null,
      onHorizontalDragStart: gestures ? _onHorizontalStart : null,
      onHorizontalDragUpdate: gestures ? _onHorizontalUpdate : null,
      onHorizontalDragEnd: gestures ? (_) => _endDrag() : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_flash != null)
            Align(
              alignment: _flashLeft
                  ? const Alignment(-0.6, 0)
                  : const Alignment(0.6, 0),
              child: _Hud(
                icon: _flashLeft
                    ? Icons.fast_rewind_rounded
                    : Icons.fast_forward_rounded,
                label: _flash!,
              ),
            ),
          AnimatedOpacity(
            opacity: _drag == _DragKind.none ? 0 : 1,
            duration: const Duration(milliseconds: 180),
            child: Center(child: _buildDragHud()),
          ),
        ],
      ),
    );
  }

  Widget _buildDragHud() {
    switch (_drag) {
      case _DragKind.brightness:
      case _DragKind.volume:
        final isBrightness = _drag == _DragKind.brightness;
        return _Hud(
          icon: isBrightness
              ? Icons.brightness_6_rounded
              : _level == 0
              ? Icons.volume_off_rounded
              : Icons.volume_up_rounded,
          label: '${(_level * 100).round()}%',
          progress: _level,
        );
      case _DragKind.seek:
        final diff = _seekTarget - _seekOrigin;
        final sign = diff.isNegative ? '-' : '+';
        return _Hud(
          icon: diff.isNegative
              ? Icons.fast_rewind_rounded
              : Icons.fast_forward_rounded,
          label:
              '$sign${formatDuration(diff.abs())}  ·  ${formatDuration(_seekTarget)}',
        );
      case _DragKind.none:
        return const SizedBox.shrink();
    }
  }
}

class _Hud extends StatelessWidget {
  final IconData icon;
  final String label;
  final double? progress;

  const _Hud({required this.icon, required this.label, this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Colors.white24,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
