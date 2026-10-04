import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/player_settings.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../providers/epg_provider.dart';
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

  /// Ordered episodes of the series being watched (null for films/live).
  final List<Channel>? queue;

  const PlayerScreen(
      {super.key, required this.channel, this.startAt, this.queue});

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

  /// Resume point not yet reached: progress is not saved until the seek
  /// lands, so a slow start never overwrites the saved position with 0.
  Duration? _pendingResume;
  DateTime _openedAt = DateTime.now();
  List<Channel>? _queue;
  Channel? _next;
  bool _nextDismissed = false;
  bool _advancing = false;

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
    _resolveQueue();
  }

  bool get _isEpisode =>
      widget.channel.type == ContentType.series ||
      widget.channel.type == ContentType.anime;

  /// Finds the next episode: from the list passed by the series page, or by
  /// loading the series (e.g. when resuming from "Continua a guardare").
  Future<void> _resolveQueue() async {
    if (!_isEpisode) return;
    List<Channel> queue = widget.queue ?? const [];
    if (queue.isEmpty) {
      final key = widget.channel.seriesKey;
      if (key == null || key.isEmpty) return;
      final app = context.read<AppProvider>();
      final folder = app.seriesFolderFor(key) ??
          Channel(
            id: key,
            name: widget.channel.seriesName ?? widget.channel.name,
            url: '',
            logo: '',
            group: widget.channel.group,
            type: widget.channel.type,
            seriesKey: key,
            seriesName: widget.channel.seriesName,
            isSeriesFolder: true,
          );
      try {
        final details = await app.loadSeriesDetails(folder);
        queue = [for (final e in details.allEpisodes) e.channel];
      } catch (_) {
        return;
      }
    }
    final index = queue.indexWhere((c) => c.id == widget.channel.id);
    if (!mounted) return;
    setState(() {
      _queue = queue;
      _next = index >= 0 && index + 1 < queue.length ? queue[index + 1] : null;
    });
  }

  void _playNext() {
    final next = _next;
    if (next == null || _advancing) return;
    _advancing = true;
    _saveResume();
    final entry = _history.entryFor(next.id);
    playChannel(context, next,
        startAt: entry?.resumePosition, queue: _queue, replace: true);
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
    if (startAt != null && startAt > Duration.zero) _pendingResume = startAt;
    _openedAt = DateTime.now();

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

    // Netflix-style: at the end of an episode go straight to the next one.
    if (v.isEnded && _next != null && !_nextDismissed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playNext();
      });
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
    final pending = _pendingResume;
    if (pending != null) {
      final landed = v.position >= pending - const Duration(seconds: 10);
      final gaveUp =
          DateTime.now().difference(_openedAt) > const Duration(seconds: 40);
      if (!landed && !gaveUp) return;
      _pendingResume = null;
    }
    _history.updatePosition(widget.channel.id, v.position, v.duration);
    if (_settings?.resumePlayback != true) return;
    final remaining = v.duration - v.position;
    final keep = v.position > const Duration(seconds: 5) &&
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
            subtitle: _isLive
                ? (context.watch<EpgProvider>().nowFor(widget.channel)?.title ??
                    widget.channel.group)
                : widget.channel.group,
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
      if (_next != null && status == SessionStatus.playing && !_inPip)
        _buildNextOverlay(session),
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

  /// "Episodio successivo": a small button while the controls are visible,
  /// and a countdown card in the last 25 seconds (end credits).
  Widget _buildNextOverlay(PlaybackSession session) {
    final v = session.value;
    final remaining = v.duration - v.position;
    final nearEnd = v.duration > const Duration(minutes: 3) &&
        remaining <= const Duration(seconds: 25) &&
        remaining > Duration.zero;
    final showCard = nearEnd && !_nextDismissed;
    if (!showCard && (!_controlsVisible || _locked)) {
      return const SizedBox.shrink();
    }
    final next = _next!;
    final label = next.season != null && next.episode != null
        ? 'S${next.season} E${next.episode}'
        : 'Episodio successivo';
    return Positioned(
      right: 16,
      bottom: showCard ? 96 : 84,
      child: SafeArea(
        child: showCard
            ? Container(
                width: 260,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.card.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('PROSSIMO EPISODIO',
                              style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8)),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _nextDismissed = true),
                          child: const Icon(Icons.close_rounded,
                              color: AppColors.textSecondary, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('$label · ${next.name}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.skip_next_rounded),
                        label: Text('Avvio tra ${remaining.inSeconds}s'),
                        onPressed: _playNext,
                      ),
                    ),
                  ],
                ),
              )
            : ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.55),
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                ),
                icon: const Icon(Icons.skip_next_rounded),
                label: Text('Episodio successivo · $label'),
                onPressed: _playNext,
              ),
      ),
    );
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
