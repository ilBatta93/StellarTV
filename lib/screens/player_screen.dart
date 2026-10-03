import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/player_settings.dart';
import '../player/playback_session.dart';
import '../providers/history_provider.dart';
import '../services/native_player_bridge.dart';
import '../services/player_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/player/player_controls.dart';
import '../widgets/player/player_gestures.dart';
import '../widgets/player/player_sheets.dart';
import '../widgets/player/player_stats.dart';
import '../widgets/player/video_surface.dart';

class PlayerScreen extends StatefulWidget {
  final Channel channel;
  final Duration? startAt;

  const PlayerScreen({super.key, required this.channel, this.startAt});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  final _settingsService = PlayerSettingsService();
  final _bridge = NativePlayerBridge.instance;
  late final HistoryProvider _history;

  PlayerSettings? _settings;
  PlaybackSession? _session;
  StreamSubscription<bool>? _pipSub;
  Timer? _hideTimer;
  Timer? _resumeTimer;
  Timer? _noticeTimer;
  bool _controlsVisible = true;
  bool _locked = false;
  bool _inPip = false;
  bool _pipSupported = false;
  bool _statsVisible = false;
  bool _orientationApplied = false;
  Size _pipSize = Size.zero;

  bool get _isLive => widget.channel.type == ContentType.live;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _history = context.read<HistoryProvider>();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _pipSub = _bridge.pipChanges.listen((inPip) {
      if (!mounted) return;
      setState(() {
        _inPip = inPip;
        if (inPip) _controlsVisible = false;
      });
    });
    _init();
  }

  Future<void> _init() async {
    final settings = await _settingsService.load();
    final pipSupported = await _bridge.isPipSupported();
    Duration? startAt = _isLive ? null : widget.startAt;
    if (startAt == null && !_isLive && settings.resumePlayback) {
      startAt = _history.entryFor(widget.channel.id)?.resumePosition ??
          await _settingsService.getResumePosition(widget.channel.url);
    }
    if (!mounted) return;

    _applyOrientation(settings);
    if (settings.keepScreenOn) _bridge.setKeepScreenOn(true);
    if (pipSupported) _bridge.setAutoPip(settings.autoPip);

    final session = PlaybackSession(
      url: widget.channel.url,
      isLive: _isLive,
      settings: settings,
      startAt: startAt,
    )..addListener(_onSessionChanged);

    setState(() {
      _settings = settings;
      _session = session;
      _pipSupported = pipSupported;
      _statsVisible = settings.showStats;
    });
    session.start();
    _scheduleHide();
    if (!_isLive) {
      _resumeTimer =
          Timer.periodic(const Duration(seconds: 10), (_) => _saveResume());
    }
  }

  void _applyOrientation(PlayerSettings settings) {
    switch (settings.orientation) {
      case PlayerOrientation.landscape:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      case PlayerOrientation.auto:
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      case PlayerOrientation.followVideo:
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  void _onSessionChanged() {
    final session = _session;
    final settings = _settings;
    if (session == null || settings == null || !mounted) return;
    final v = session.value;

    if (v.hasVideoSize) {
      if (settings.orientation == PlayerOrientation.followVideo &&
          !_orientationApplied) {
        _orientationApplied = true;
        SystemChrome.setPreferredOrientations(v.aspectRatio >= 1
            ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
            : [DeviceOrientation.portraitUp]);
      }
      if (_pipSupported && v.size != _pipSize) {
        _pipSize = v.size;
        _bridge.setAutoPip(settings.autoPip,
            width: v.size.width.round(), height: v.size.height.round());
      }
    }

    if (session.notice != null && _noticeTimer == null) {
      _noticeTimer = Timer(const Duration(seconds: 4), () {
        _noticeTimer = null;
        session.clearNotice();
      });
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = _settings;
    if (state == AppLifecycleState.paused && settings != null) {
      _saveResume();
      if (settings.backgroundAudio) return;
      // PiP also pauses the activity; give the PiP callback time to land.
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted && !_inPip) _session?.engine?.pause();
      });
    }
  }

  Future<void> _saveResume() async {
    final session = _session;
    if (session == null || _isLive) return;
    final v = session.value;
    if (v.duration <= Duration.zero) return;
    _history.updatePosition(widget.channel.id, v.position, v.duration);
    if (_settings?.resumePlayback != true) return;
    final remaining = v.duration - v.position;
    final keep = v.position > const Duration(seconds: 30) &&
        remaining > const Duration(minutes: 1);
    await _settingsService.saveResumePosition(
        widget.channel.url, keep ? v.position : null);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    final seconds = _settings?.controlsHideSeconds ?? 4;
    if (seconds <= 0) return;
    _hideTimer = Timer(Duration(seconds: seconds), () {
      final playing = _session?.value.isPlaying ?? false;
      if (mounted && playing) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _onInteraction() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  Future<void> _enterPip() async {
    final size = _session?.value.size ?? Size.zero;
    final ok = await _bridge.enterPip(
      width: size.width > 0 ? size.width.round() : 16,
      height: size.height > 0 ? size.height.round() : 9,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Picture-in-Picture non disponibile su questo dispositivo'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _openMenu() {
    final session = _session;
    if (session == null) return;
    _hideTimer?.cancel();
    showPlayerMenu(
      context,
      session,
      statsVisible: _statsVisible,
      onStatsChanged: (v) => setState(() => _statsVisible = v),
    ).whenComplete(_scheduleHide);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveResume();
    _hideTimer?.cancel();
    _resumeTimer?.cancel();
    _noticeTimer?.cancel();
    _pipSub?.cancel();
    _session?.removeListener(_onSessionChanged);
    _session?.dispose();
    _bridge.setAutoPip(false);
    _bridge.setKeepScreenOn(false);
    _bridge.resetBrightness();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final settings = _settings;
    return Scaffold(
      backgroundColor: Colors.black,
      body: session == null || settings == null
          ? Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Stack(
              fit: StackFit.expand,
              children: [
                VideoSurface(session: session, settings: settings),
                if (!_inPip) ..._buildOverlays(session, settings),
              ],
            ),
    );
  }

  List<Widget> _buildOverlays(PlaybackSession session, PlayerSettings settings) {
    final status = session.status;
    if (status == SessionStatus.failed) {
      return [_FailureView(session: session, onBack: () => Navigator.pop(context))];
    }
    final connecting =
        status == SessionStatus.connecting || status == SessionStatus.switching;
    return [
      if (status == SessionStatus.playing)
        PlayerGestureLayer(
          session: session,
          settings: settings,
          locked: _locked,
          onTap: _toggleControls,
          onInteraction: _onInteraction,
        ),
      if (connecting) _ConnectingView(session: session),
      IgnorePointer(
        ignoring: !_controlsVisible,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: PlayerControls(
            session: session,
            title: widget.channel.name,
            subtitle: widget.channel.group,
            locked: _locked,
            pipSupported: _pipSupported,
            seekStepSeconds: settings.seekStepSeconds,
            onBack: () => Navigator.pop(context),
            onPip: _enterPip,
            onMenu: _openMenu,
            onToggleLock: () {
              setState(() => _locked = !_locked);
              _scheduleHide();
            },
            onInteraction: _onInteraction,
          ),
        ),
      ),
      if (_statsVisible)
        Positioned(
          top: 72,
          right: 16,
          child: SafeArea(child: PlayerStats(session: session)),
        ),
      if (session.notice != null)
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: SafeArea(child: Center(child: _NoticeBanner(text: session.notice!))),
        ),
    ];
  }
}

class _ConnectingView extends StatelessWidget {
  final PlaybackSession session;
  const _ConnectingView({required this.session});

  @override
  Widget build(BuildContext context) {
    final engine = session.engine?.type.label ?? '';
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text('Connessione con $engine...',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  final String text;
  const _NoticeBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.swap_horiz_rounded, color: AppColors.warning, size: 20),
          const SizedBox(width: 12),
          Flexible(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  final PlaybackSession session;
  final VoidCallback onBack;
  const _FailureView({required this.session, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.error, size: 48),
                const SizedBox(height: 16),
                const Text('Impossibile riprodurre il flusso',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    session.settings.autoFallback
                        ? 'Il canale potrebbe essere offline o in un formato non supportato. '
                            'Sono stati provati entrambi i motori disponibili.'
                        : 'Il canale potrebbe essere offline o in un formato non supportato. '
                            'Prova con l\'altro motore di riproduzione.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (session.error != null) ...[
                  const SizedBox(height: 8),
                  Text(session.error!,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton(onPressed: onBack, child: const Text('Indietro')),
                    for (final e in PlayerEngineType.values)
                      OutlinedButton(
                        onPressed: () => session.switchEngine(e),
                        child: Text('Prova con ${e.label}'),
                      ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Riprova'),
                      onPressed: session.retry,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
