import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/history_entry.dart';
import '../models/player_settings.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import 'multiview_screen.dart';
import '../providers/epg_provider.dart';
import '../player/playback_session.dart';
import '../providers/history_provider.dart';
import '../services/imdb_resolver.dart';
import '../services/introdb_service.dart';
import '../services/native_player_bridge.dart';
import '../services/player_settings_service.dart';
import '../services/subtitles_service.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import '../widgets/player/player_controls.dart';
import '../widgets/player/player_format.dart';
import '../widgets/player/player_gestures.dart';
import '../widgets/player/player_sheets.dart';
import '../widgets/player/player_stats.dart';
import '../widgets/player/subtitle_overlay.dart';
import '../widgets/player/tv_player_controls.dart';
import '../widgets/player/video_surface.dart';
import '../widgets/poster_card.dart';
import '../widgets/tv_focusable.dart';

class PlayerScreen extends StatefulWidget {
  final Channel channel;
  final Duration? startAt;

  /// Ordered episodes of the series being watched (null for films/live).
  final List<Channel>? queue;

  const PlayerScreen({
    super.key,
    required this.channel,
    this.startAt,
    this.queue,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  final FocusNode _remoteFocus = FocusNode(debugLabel: 'player remote');
  final FocusNode _playFocus = FocusNode(debugLabel: 'player play');
  final FocusNode _failureFocus = FocusNode(debugLabel: 'player failure');
  ModalRoute<dynamic>? _route;

  // TV remote: highlighted command, seek being composed, Back to exit.
  TvPlayerRowKind _tvRow = TvPlayerRowKind.center;
  int _tvCol = 0;
  Duration? _tvSeekTarget;
  Timer? _tvSeekTimer;
  int _tvOutroCol = 0;
  DateTime? _exitArmedAt;
  DateTime _lastBackAt = DateTime(2000);
  bool _exiting = false;
  Timer? _exitTimer;
  bool _exitPrompt = false;
  bool _failureFocused = false;

  // TV: rebuild only when something visible changed (see _needsRebuild).
  int? _lastSignature;
  DateTime _lastPositionBuild = DateTime(2000);
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

  // Sottotitoli online (OpenSubtitles), disegnati sopra il video.
  List<SubtitleCue>? _onlineCues;
  bool _onlineSubsLoading = false;

  // IntroDB skip segments (empty when unavailable: no buttons are shown).
  EpisodeSegments _segments = EpisodeSegments.empty;
  bool _outroDisabled = false;
  bool _outroActive = false;
  int _outroCountdown = 5;
  Timer? _outroTimer;

  bool get _isLive => widget.channel.type == ContentType.live;

  /// Players currently on screen. When a player replaces another (next
  /// channel / next episode) the old one is disposed AFTER the new one is
  /// created: it must not force portrait while a player is still visible.
  static int _activePlayers = 0;
  late final AppProvider _app;

  @override
  void initState() {
    super.initState();
    _activePlayers++;
    _app = context.read<AppProvider>()..setPlaybackActive(true);
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
    _loadSegments();
    if (DeviceTypeService.isTv) {
      // Remote keys are read before the focus system: the player commands
      // work whatever widget holds the focus, and the D-Pad can never get
      // lost behind the video or inside a control.
      FocusManager.instance.addEarlyKeyEventHandler(_onEarlyKey);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _remoteFocus.requestFocus();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  static bool _isBackKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.goBack ||
      key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.browserBack;

  static bool _isOkKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;

  static bool _isArrowKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown;

  static final Set<LogicalKeyboardKey> _mediaKeys = {
    LogicalKeyboardKey.mediaPlayPause,
    LogicalKeyboardKey.mediaPlay,
    LogicalKeyboardKey.mediaPause,
    LogicalKeyboardKey.mediaFastForward,
    LogicalKeyboardKey.mediaRewind,
    LogicalKeyboardKey.mediaTrackNext,
    LogicalKeyboardKey.channelUp,
    LogicalKeyboardKey.channelDown,
    LogicalKeyboardKey.contextMenu,
    LogicalKeyboardKey.info,
  };

  /// TV only. Runs before the focus system for every key while the player
  /// is the visible page (option panels opened above it get their keys).
  KeyEventResult _onEarlyKey(KeyEvent event) {
    if (!mounted || !DeviceTypeService.isTv) return KeyEventResult.ignored;
    final route = _route;
    if (route != null && !route.isCurrent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_isBackKey(key)) {
      if (event is KeyDownEvent) _handleTvBack();
      // Key up is swallowed too, so Android never adds a second "back".
      return KeyEventResult.handled;
    }
    final session = _session;
    if (session == null) return KeyEventResult.ignored;
    // The error page uses normal buttons and focus.
    if (session.status == SessionStatus.failed) return KeyEventResult.ignored;
    final ours = _isOkKey(key) || _isArrowKey(key) || _mediaKeys.contains(key);
    if (!ours) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.handled;
    _onTvKey(session, key, repeat: event is KeyRepeatEvent);
    return KeyEventResult.handled;
  }

  bool _introActive(PlaybackSession session) {
    final intro = _segments.intro;
    return session.status == SessionStatus.playing &&
        intro != null &&
        intro.contains(session.value.position);
  }

  bool _canSeek(PlaybackSession session) =>
      !_isLive && session.value.duration > Duration.zero;

  void _onTvKey(
    PlaybackSession session,
    LogicalKeyboardKey key, {
    required bool repeat,
  }) {
    final step = Duration(seconds: _settings?.seekStepSeconds ?? 10);

    // Dedicated remote buttons work in every state.
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      session.togglePlay();
      _onInteraction();
      return;
    }
    if (key == LogicalKeyboardKey.mediaPlay) {
      if (!session.value.isPlaying) session.togglePlay();
      _onInteraction();
      return;
    }
    if (key == LogicalKeyboardKey.mediaPause) {
      if (session.value.isPlaying) session.togglePlay();
      _onInteraction();
      return;
    }
    if (key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.mediaRewind) {
      if (_canSeek(session)) {
        _showTvControls(TvPlayerRowKind.progress);
        final delta = step * 3;
        _tvSeekBy(
          key == LogicalKeyboardKey.mediaRewind ? -delta : delta,
          repeat,
        );
      }
      return;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      if (_next != null) _playNext();
      return;
    }
    if (key == LogicalKeyboardKey.channelUp ||
        key == LogicalKeyboardKey.channelDown) {
      if (_isLive) {
        _playLiveChannel(
          _adjacentLiveChannel(key == LogicalKeyboardKey.channelUp ? -1 : 1),
        );
      }
      return;
    }
    if (key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.info) {
      _openMenu();
      return;
    }

    final left = key == LogicalKeyboardKey.arrowLeft;
    final right = key == LogicalKeyboardKey.arrowRight;
    final up = key == LogicalKeyboardKey.arrowUp;
    final down = key == LogicalKeyboardKey.arrowDown;
    final ok = _isOkKey(key);

    if (_locked) {
      if (ok && _controlsVisible) {
        setState(() => _locked = false);
        _showTvControls(TvPlayerRowKind.center);
      } else {
        _onInteraction();
      }
      return;
    }

    if (!_controlsVisible) {
      final outro = _outroActive && _next != null;
      if (ok) {
        if (_introActive(session)) {
          _skipIntro();
        } else if (outro) {
          if (_tvOutroCol == 0) {
            _outroTimer?.cancel();
            playNextEpisode();
          } else {
            _watchCredits();
          }
        } else {
          _showTvControls(TvPlayerRowKind.center);
        }
        return;
      }
      if (outro && (left || right)) {
        setState(() => _tvOutroCol = right ? 1 : 0);
        return;
      }
      if (_isLive && (up || down)) {
        _playLiveChannel(_adjacentLiveChannel(up ? -1 : 1));
        return;
      }
      if ((left || right) && _isLive && session.canTimeshift) {
        // Live timeshift straight from the arrows, like a DVR.
        _showTvControls(TvPlayerRowKind.center);
        if (left || session.isBehindLive) {
          session.timeshiftBy(left ? -step : step);
        }
        return;
      }
      if ((left || right) && _canSeek(session)) {
        _showTvControls(TvPlayerRowKind.progress);
        _tvSeekBy(left ? -step : step, repeat);
        return;
      }
      _showTvControls(TvPlayerRowKind.center);
      return;
    }

    // Controls visible: move the highlighted command.
    _onInteraction();
    final rows = _tvRows(session);
    if (rows.isEmpty) return;
    var rowIndex = rows.indexWhere((r) => r.kind == _tvRow);
    if (rowIndex < 0) {
      rowIndex = rows.indexWhere((r) => r.kind == TvPlayerRowKind.center);
      if (rowIndex < 0) rowIndex = 0;
      _tvRow = rows[rowIndex].kind;
      _tvCol = _entryColumn(null, rows[rowIndex]);
    }
    final row = rows[rowIndex];
    final col = _tvCol.clamp(
      0,
      row.actions.isEmpty ? 0 : row.actions.length - 1,
    );

    if (ok) {
      if (row.kind == TvPlayerRowKind.progress) {
        _commitTvSeek();
        session.togglePlay();
        return;
      }
      if (row.actions.isNotEmpty) row.actions[col].onPressed?.call();
      return;
    }
    if (row.kind == TvPlayerRowKind.progress && (left || right)) {
      _tvSeekBy(left ? -step : step, repeat);
      return;
    }
    if (left || right) {
      if (row.actions.isEmpty) return;
      final next = (col + (left ? -1 : 1)).clamp(0, row.actions.length - 1);
      if (next != _tvCol) setState(() => _tvCol = next);
      return;
    }
    final target = (rowIndex + (up ? -1 : 1)).clamp(0, rows.length - 1);
    if (target == rowIndex) return;
    if (row.kind == TvPlayerRowKind.progress) _commitTvSeek();
    setState(() {
      _tvCol = _entryColumn(row, rows[target], fromColumn: col);
      _tvRow = rows[target].kind;
    });
  }

  /// Column highlighted when entering [to]: play in the middle row,
  /// otherwise the command horizontally closest to the previous one.
  int _entryColumn(TvPlayerRow? from, TvPlayerRow to, {int fromColumn = 0}) {
    if (to.actions.isEmpty) return 0;
    if (to.kind == TvPlayerRowKind.center) {
      final play = to.actions.indexWhere((a) => a.id == 'play');
      return play < 0 ? 0 : play;
    }
    if (to.kind == TvPlayerRowKind.progress) return 0;
    if (from == null || from.actions.length <= 1) {
      return to.kind == TvPlayerRowKind.top ? to.actions.length - 1 : 0;
    }
    final fraction = fromColumn / (from.actions.length - 1);
    return (fraction * (to.actions.length - 1)).round();
  }

  void _showTvControls(TvPlayerRowKind row) {
    final session = _session;
    setState(() {
      _controlsVisible = true;
      _tvRow = row;
      final rows = session == null ? const <TvPlayerRow>[] : _tvRows(session);
      final target = rows.where((r) => r.kind == row).firstOrNull;
      if (target == null) {
        _tvRow = TvPlayerRowKind.center;
        final center = rows
            .where((r) => r.kind == TvPlayerRowKind.center)
            .firstOrNull;
        _tvCol = center == null ? 0 : _entryColumn(null, center);
      } else {
        _tvCol = _entryColumn(null, target);
      }
    });
    _scheduleHide();
  }

  void _tvSeekBy(Duration delta, bool repeat) {
    final session = _session;
    if (session == null) return;
    final duration = session.value.duration;
    if (duration <= Duration.zero) return;
    final base = _tvSeekTarget ?? session.value.position;
    var target = base + (repeat ? delta * 3 : delta);
    if (target < Duration.zero) target = Duration.zero;
    final end = duration - const Duration(seconds: 1);
    if (target > end) target = end;
    setState(() => _tvSeekTarget = target);
    _tvSeekTimer?.cancel();
    // One seek after the user stops pressing: repeated seeks on every press
    // made the engines stutter and rebuffer.
    _tvSeekTimer = Timer(const Duration(milliseconds: 700), _commitTvSeek);
    _onInteraction();
  }

  void _commitTvSeek() {
    _tvSeekTimer?.cancel();
    final target = _tvSeekTarget;
    if (target == null) return;
    _session?.seekTo(target);
    if (mounted) setState(() => _tvSeekTarget = null);
  }

  /// First Back: asks for confirmation. Second Back within 3 s: exits.
  void _handleTvBack() {
    final now = DateTime.now();
    // The same press may arrive both as a key and as a system "back".
    if (now.difference(_lastBackAt) < const Duration(milliseconds: 250)) {
      return;
    }
    _lastBackAt = now;
    if (_exiting) return;
    if (_session?.status == SessionStatus.failed) {
      _exitPlayer();
      return;
    }
    final armed = _exitArmedAt;
    if (armed != null && now.difference(armed) <= const Duration(seconds: 3)) {
      _exitPlayer();
      return;
    }
    _exitArmedAt = now;
    _exitTimer?.cancel();
    _hideTimer?.cancel();
    setState(() {
      _exitPrompt = true;
      _controlsVisible = false;
    });
    _exitTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _exitPrompt = false;
        _exitArmedAt = null;
      });
    });
  }

  void _exitPlayer() {
    _exitTimer?.cancel();
    if (!mounted) return;
    if (DeviceTypeService.isTv && !_isLive) {
      // Back is handled on key DOWN, while Android delivers its own "back"
      // on key UP: navigating at once let that trailing back close the title
      // page too (it flashed, then the Film/Serie tab came back). Wait for
      // the key release, keep swallowing Backs here, then open the title.
      if (_exiting) return;
      _exiting = true;
      final started = DateTime.now();
      Timer.periodic(const Duration(milliseconds: 40), (t) {
        final released = HardwareKeyboard.instance.logicalKeysPressed.isEmpty;
        final waited = DateTime.now().difference(started);
        if (!mounted) {
          t.cancel();
          return;
        }
        if ((released && waited >= const Duration(milliseconds: 250)) ||
            waited >= const Duration(milliseconds: 1200)) {
          t.cancel();
          Future.delayed(const Duration(milliseconds: 120), () {
            if (mounted) _openTitle();
          });
        }
      });
      return;
    }
    // Navigator.pop ignores the PopScope that blocks the first Back.
    Navigator.of(context).pop();
  }

  void _openTvSheet(Future<void> Function() open) {
    _hideTimer?.cancel();
    open().whenComplete(() {
      if (!mounted) return;
      _remoteFocus.requestFocus();
      _scheduleHide();
    });
  }

  /// Commands of the TV overlay, row by row.
  List<TvPlayerRow> _tvRows(PlaybackSession session) {
    if (_locked) {
      return [
        TvPlayerRow(TvPlayerRowKind.center, [
          TvPlayerAction(
            id: 'unlock',
            icon: Icons.lock_rounded,
            label: 'Sblocca comandi',
            onPressed: () {
              setState(() => _locked = false);
              _scheduleHide();
            },
          ),
        ]),
      ];
    }
    final v = session.value;
    final step = Duration(seconds: _settings?.seekStepSeconds ?? 10);
    final canSeek = _canSeek(session);
    final engine = session.engine;
    final previousLive = _adjacentLiveChannel(-1);
    final nextLive = _adjacentLiveChannel(1);
    return [
      TvPlayerRow(TvPlayerRowKind.top, [
        TvPlayerAction(
          id: 'exit',
          icon: Icons.arrow_back_rounded,
          label: 'Esci',
          onPressed: _exitPlayer,
        ),
        if (!_isLive)
          TvPlayerAction(
            id: 'title',
            icon: Icons.info_outline_rounded,
            label: 'Scheda titolo',
            onPressed: _openTitle,
          ),
        if (_isEpisode)
          TvPlayerAction(
            id: 'episodes',
            icon: Icons.video_library_rounded,
            label: 'Stagioni ed episodi',
            onPressed: _openEpisodes,
          ),
        if (_isLive)
          TvPlayerAction(
            id: 'multiview',
            icon: Icons.grid_view_rounded,
            label: 'MultiView',
            onPressed: _openMultiView,
          ),
        if (engine != null)
          TvPlayerAction(
            id: 'engine',
            icon: Icons.memory_rounded,
            label: engine.type.label,
            onPressed: () =>
                _openTvSheet(() => showEngineSheet(context, session)),
          ),
        if (_pipSupported)
          TvPlayerAction(
            id: 'pip',
            icon: Icons.picture_in_picture_alt_rounded,
            label: 'PiP',
            onPressed: _enterPip,
          ),
        TvPlayerAction(
          id: 'menu',
          icon: Icons.tune_rounded,
          label: 'Opzioni',
          onPressed: _openMenu,
        ),
      ]),
      TvPlayerRow(TvPlayerRowKind.center, [
        if (_isLive)
          TvPlayerAction(
            id: 'prevChannel',
            icon: Icons.skip_previous_rounded,
            label: previousLive == null
                ? 'Nessun canale precedente'
                : previousLive.name,
            onPressed: previousLive == null
                ? null
                : () => _playLiveChannel(previousLive),
          )
        else if (canSeek)
          TvPlayerAction(
            id: 'rewind',
            icon: Icons.replay_rounded,
            label: '-${step.inSeconds} s',
            onPressed: () => _tvSeekBy(-step, false),
          ),
        if (_isLive && session.canTimeshift)
          TvPlayerAction(
            id: 'liveRewind',
            icon: Icons.replay_10_rounded,
            label: 'Indietro ${step.inSeconds} s',
            onPressed: () => session.timeshiftBy(-step),
          ),
        TvPlayerAction(
          id: 'play',
          icon: v.isEnded
              ? Icons.replay_rounded
              : v.isPlaying
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          label: v.isPlaying ? 'Pausa' : 'Riproduci',
          primary: true,
          onPressed: session.togglePlay,
        ),
        if (_isLive && session.canTimeshift)
          TvPlayerAction(
            id: 'liveForward',
            icon: Icons.forward_10_rounded,
            label: 'Avanti ${step.inSeconds} s',
            onPressed: session.isBehindLive
                ? () => session.timeshiftBy(step)
                : null,
          ),
        if (_isLive && session.isBehindLive)
          TvPlayerAction(
            id: 'goLive',
            icon: Icons.sensors_rounded,
            label: 'Torna in LIVE',
            onPressed: session.goLive,
          ),
        if (_isLive)
          TvPlayerAction(
            id: 'nextChannel',
            icon: Icons.skip_next_rounded,
            label: nextLive == null
                ? 'Nessun canale successivo'
                : nextLive.name,
            onPressed: nextLive == null
                ? null
                : () => _playLiveChannel(nextLive),
          )
        else if (canSeek)
          TvPlayerAction(
            id: 'forward',
            icon: Icons.forward_rounded,
            label: '+${step.inSeconds} s',
            onPressed: () => _tvSeekBy(step, false),
          ),
        if (_introActive(session))
          TvPlayerAction(
            id: 'skipIntro',
            icon: Icons.fast_forward_rounded,
            label: 'Salta sigla',
            onPressed: _skipIntro,
          ),
        if (_next != null)
          TvPlayerAction(
            id: 'nextEpisode',
            icon: Icons.skip_next_rounded,
            label: 'Episodio successivo',
            onPressed: _playNext,
          ),
      ]),
      if (canSeek) const TvPlayerRow(TvPlayerRowKind.progress, []),
      TvPlayerRow(TvPlayerRowKind.bottom, [
        TvPlayerAction(
          id: 'volume',
          icon: session.muted
              ? Icons.volume_off_rounded
              : Icons.volume_up_rounded,
          label: session.muted ? 'Muto' : 'Volume',
          onPressed: session.toggleMute,
        ),
        TvPlayerAction(
          id: 'lock',
          icon: Icons.lock_open_rounded,
          label: 'Blocca',
          onPressed: () {
            setState(() => _locked = true);
            _scheduleHide();
          },
        ),
        TvPlayerAction(
          id: 'audio',
          icon: Icons.audiotrack_rounded,
          label: 'Audio',
          onPressed: () => _openTvSheet(() => showAudioSheet(context, session)),
        ),
        TvPlayerAction(
          id: 'subtitles',
          icon: Icons.subtitles_rounded,
          label: _onlineCues != null ? 'ITA online' : 'Sottotitoli',
          onPressed: () => _openTvSheet(
            () => showSubtitleSheet(
              context,
              session,
              onlineActive: _onlineCues != null,
              onlineLoading: _onlineSubsLoading,
              onLoadOnline: _loadOnlineSubtitles,
              onDisableOnline: _disableOnlineSubtitles,
            ),
          ),
        ),
        if (engine?.supportsQualitySelection ?? false)
          TvPlayerAction(
            id: 'quality',
            icon: Icons.high_quality_rounded,
            label: 'Qualità',
            onPressed: () =>
                _openTvSheet(() => showQualitySheet(context, session)),
          ),
        if (!_isLive)
          TvPlayerAction(
            id: 'speed',
            icon: Icons.speed_rounded,
            label: formatSpeed(session.speed),
            onPressed: () =>
                _openTvSheet(() => showSpeedSheet(context, session)),
          ),
        TvPlayerAction(
          id: 'fit',
          icon: Icons.aspect_ratio_rounded,
          label: session.fitMode.label,
          onPressed: () => _openTvSheet(() => showFitSheet(context, session)),
        ),
      ]),
    ];
  }

  /// "Scheda titolo": leaves the player and shows the movie/series page,
  /// returning to the existing one when the player was opened from it.
  void _openTitle() {
    final navigator = Navigator.of(context);
    final app = context.read<AppProvider>();
    final key = _isEpisode
        ? (widget.channel.seriesKey ?? widget.channel.id)
        : widget.channel.id;
    // The title page is still open below the player: just go back to it,
    // without rebuilding it (and reloading its episodes and pictures).
    final name = titleRouteName(key);
    if (OpenRoutesObserver.instance.containsNamed(name)) {
      navigator.popUntil(
        (route) => route.settings.name == name || route.isFirst,
      );
      return;
    }
    final target = _isEpisode
        ? (app.seriesFolderFor(key) ??
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
              ))
        : widget.channel;
    if (_isEpisode) {
      openSeries(navigator.context, target, replace: true);
    } else {
      openChannel(navigator.context, target, replace: true);
    }
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
      final folder =
          app.seriesFolderFor(key) ??
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

  /// Live only: releases this stream (single-connection providers) and
  /// replaces the player with MultiView, starting from the current channel.
  Future<void> _openMultiView() async {
    if (!_isLive || _advancing) return;
    _advancing = true;
    _hideTimer?.cancel();
    final previous = _session;
    previous?.removeListener(_onSessionChanged);
    setState(() => _session = null);
    previous?.dispose();
    // Wait until decoder, surface and provider connection are really free.
    await (previous?.released ?? Future<void>.value())
        .timeout(const Duration(seconds: 6), onTimeout: () {});
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MultiViewScreen(initialChannel: widget.channel),
        ),
      ),
    );
  }

  Future<void> _openEpisodes() async {
    if (!_isEpisode) return;
    _hideTimer?.cancel();
    // The dialog owns the D-Pad; the early player handler ignores non-current routes.
    final selected = await showDialog<Channel>(
      context: context,
      barrierColor: AppColors.background.withValues(alpha: 0.2),
      builder: (_) => _EpisodePicker(
        current: widget.channel,
        entryFor: _history.entryFor,
        load: () async {
          await _resolveQueue();
          final app = _app;
          return (_queue ?? const <Channel>[])
              .where((c) => !app.kidsMode || app.isKidsContent(c))
              .toList();
        },
      ),
    );
    if (!mounted) return;
    _remoteFocus.requestFocus();
    _scheduleHide();
    if (selected == null || selected.id == widget.channel.id || _advancing)
      return;
    _advancing = true;
    await _saveResume();
    // Retire the old stream before opening another on single-connection providers.
    final previous = _session;
    previous?.removeListener(_onSessionChanged);
    setState(() => _session = null);
    previous?.dispose();
    // Wait until decoder, surface and provider connection are really free.
    await (previous?.released ?? Future<void>.value())
        .timeout(const Duration(seconds: 6), onTimeout: () {});
    if (!mounted) return;
    playChannel(
      context,
      selected,
      queue: _queue,
      startAt: _history.entryFor(selected.id)?.resumePosition,
      replace: true,
    );
  }

  /// IntroDB: resolve the IMDb id of the series, then fetch intro/outro.
  /// Any failure is ignored silently and playback continues normally.
  Future<void> _loadSegments() async {
    final c = widget.channel;
    if (!_isEpisode || c.season == null || c.episode == null) return;
    final title = c.seriesName?.isNotEmpty == true ? c.seriesName! : c.name;
    final imdbId = await ImdbResolver.getImdbId(title: title);
    if (imdbId == null) return;
    final segments = await IntroDbService.fetch(imdbId, c.season!, c.episode!);
    if (mounted) setState(() => _segments = segments);
  }

  /// Cerca e scarica i sottotitoli in italiano da OpenSubtitles (via cloud).
  /// Per le serie risolve l'IMDb della serie e usa stagione/episodio del
  /// canale; per i film cerca per titolo. Gli errori finiscono in uno
  /// snackbar e la riproduzione continua senza sottotitoli.
  Future<void> _loadOnlineSubtitles() async {
    if (_isLive || _onlineSubsLoading || _onlineCues != null) return;
    setState(() => _onlineSubsLoading = true);
    try {
      final c = widget.channel;
      final title = _isEpisode
          ? (c.seriesName?.isNotEmpty == true ? c.seriesName! : c.name)
          : c.name;
      final imdbId = await ImdbResolver.getImdbId(
        title: title,
        isMovie: !_isEpisode,
      );
      if (imdbId == null) throw 'titolo non trovato su TMDB';
      final cues = await SubtitlesService.fetch(
        imdbId: imdbId,
        season: _isEpisode ? c.season : null,
        episode: _isEpisode ? c.episode : null,
      );
      // Evita la doppia scritta spegnendo la traccia incorporata.
      await _session?.engine?.selectSubtitleTrack(null);
      if (mounted) setState(() => _onlineCues = cues);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sottotitoli online: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _onlineSubsLoading = false);
    }
  }

  void _disableOnlineSubtitles() => setState(() => _onlineCues = null);

  void _skipIntro() {
    final intro = _segments.intro;
    if (intro == null) return;
    _session?.seekTo(intro.end);
    _onInteraction();
  }

  void _checkOutro(Duration position) {
    final outro = _segments.outro;
    if (outro == null || _next == null || _outroDisabled || _advancing) return;
    final inOutro = position >= outro.start;
    if (inOutro && !_outroActive) {
      _outroActive = true;
      _outroCountdown = 5;
      _outroTimer?.cancel();
      _outroTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        if (_outroCountdown <= 1) {
          t.cancel();
          playNextEpisode();
        } else {
          setState(() => _outroCountdown--);
        }
      });
    } else if (!inOutro && _outroActive) {
      // The user seeked back before the credits.
      _outroActive = false;
      _outroTimer?.cancel();
    }
  }

  void _watchCredits() {
    _outroTimer?.cancel();
    setState(() {
      _outroActive = false;
      _outroDisabled = true;
      _nextDismissed = true;
    });
  }

  void playNextEpisode() => _playNext();

  Future<void> _playNext() async {
    final next = _next;
    if (next == null || _advancing) return;
    _advancing = true;
    _outroTimer?.cancel();
    await _saveResume();
    if (!mounted) return;
    final previous = _session;
    previous?.removeListener(_onSessionChanged);
    setState(() => _session = null);
    previous?.dispose();
    // Wait until decoder, surface and provider connection are really free.
    await (previous?.released ?? Future<void>.value())
        .timeout(const Duration(seconds: 6), onTimeout: () {});
    if (!mounted) return;
    final entry = _history.entryFor(next.id);
    playChannel(
      context,
      next,
      startAt: entry?.resumePosition,
      queue: _queue,
      replace: true,
    );
  }

  List<Channel> get _liveChannels {
    if (!_isLive) return const [];
    final all = context.read<AppProvider>().channelsOf(ContentType.live);
    final sameGroup = all
        .where((channel) => channel.group == widget.channel.group)
        .toList(growable: false);
    return sameGroup.length > 1 ? sameGroup : all;
  }

  Channel? _adjacentLiveChannel(int offset) {
    final channels = _liveChannels;
    final index = channels.indexWhere(
      (channel) => channel.id == widget.channel.id,
    );
    final target = index + offset;
    if (index < 0 || target < 0 || target >= channels.length) return null;
    return channels[target];
  }

  Future<void> _playLiveChannel(Channel? channel) async {
    if (channel == null || _advancing) return;
    _advancing = true;
    // Close the current provider connection before opening the next channel.
    // Many Xtream plans allow only one active stream and otherwise return 458.
    final previous = _session;
    previous?.removeListener(_onSessionChanged);
    // Unmount the picture before its player is released.
    setState(() => _session = null);
    previous?.dispose();
    // Wait until decoder, surface and provider connection are really free.
    await (previous?.released ?? Future<void>.value())
        .timeout(const Duration(seconds: 6), onTimeout: () {});
    if (!mounted) return;
    playChannel(context, channel, replace: true);
  }

  Future<void> _init() async {
    final settings = await _settingsService.load(
      scope: !DeviceTypeService.isTv
          ? PlayerSettingsScope.shared
          : _isLive
          ? PlayerSettingsScope.liveTv
          : PlayerSettingsScope.filmSeriesTv,
    );
    final pipSupported = await _bridge.isPipSupported();
    Duration? startAt = _isLive ? null : widget.startAt;
    if (startAt == null && !_isLive && settings.resumePlayback) {
      startAt =
          _history.entryFor(widget.channel.id)?.resumePosition ??
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
      _resumeTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _saveResume(),
      );
    }
  }

  Future<void> _setOrientation(String mode) async {
    await SystemChrome.setPreferredOrientations(switch (mode) {
      'landscape' => [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      'portrait' => [DeviceOrientation.portraitUp],
      _ => [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    });
    // Android: force true sensor rotation (also with auto-rotate quirks).
    await _bridge.setOrientation(mode);
  }

  void _applyOrientation(PlayerSettings settings) {
    if (DeviceTypeService.isTv) {
      _setOrientation('landscape');
      return;
    }
    switch (settings.orientation) {
      case PlayerOrientation.landscape:
        _setOrientation('landscape');
      case PlayerOrientation.auto:
      case PlayerOrientation.followVideo:
        _setOrientation('sensor');
    }
  }

  void _onSessionChanged() {
    final session = _session;
    final settings = _settings;
    if (session == null || settings == null || !mounted) return;
    final v = session.value;

    if (v.hasVideoSize) {
      if (!DeviceTypeService.isTv &&
          settings.orientation == PlayerOrientation.followVideo &&
          !_orientationApplied) {
        _orientationApplied = true;
        _setOrientation(v.aspectRatio >= 1 ? 'landscape' : 'portrait');
      }
      if (_pipSupported && v.size != _pipSize) {
        _pipSize = v.size;
        _bridge.setAutoPip(
          settings.autoPip,
          width: v.size.width.round(),
          height: v.size.height.round(),
        );
      }
    }

    if (!_isLive) _checkOutro(v.position);

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
    if (DeviceTypeService.isTv) {
      if (session.status == SessionStatus.failed && !_failureFocused) {
        _failureFocused = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _failureFocus.requestFocus();
        });
      } else if (session.status != SessionStatus.failed && _failureFocused) {
        _failureFocused = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _remoteFocus.requestFocus();
        });
      }
      if (!_needsRebuild(session)) return;
    }
    setState(() {});
  }

  /// TV boxes are slow: the engines report the position many times per
  /// second and rebuilding the whole player each time stole CPU from the
  /// video (stutter). Rebuild on real state changes, and for the position
  /// only when something on screen shows it.
  bool _needsRebuild(PlaybackSession session) {
    final v = session.value;
    final signature = Object.hashAll([
      session.status,
      session.engine,
      session.notice,
      session.muted,
      session.speed,
      session.fitMode,
      v.isPlaying,
      v.isBuffering,
      v.isEnded,
      v.error,
      v.size,
      v.duration.inSeconds,
      v.caption,
      _outroActive,
      _introActive(session),
    ]);
    final now = DateTime.now();
    if (signature != _lastSignature) {
      _lastSignature = signature;
      _lastPositionBuild = now;
      return true;
    }
    final showsPosition =
        _controlsVisible || _onlineCues != null || _statsVisible;
    if (!showsPosition) return false;
    final gap = _onlineCues != null ? 120 : 500;
    if (now.difference(_lastPositionBuild).inMilliseconds < gap) return false;
    _lastPositionBuild = now;
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = _settings;
    if (state == AppLifecycleState.resumed && settings != null) {
      if (!DeviceTypeService.isTv &&
          settings.orientation == PlayerOrientation.followVideo &&
          _orientationApplied) {
        final v = _session?.value;
        if (v != null && v.hasVideoSize) {
          _setOrientation(v.aspectRatio >= 1 ? 'landscape' : 'portrait');
        }
      } else {
        _applyOrientation(settings);
      }
    }
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
    final keep =
        v.position > const Duration(seconds: 5) &&
        remaining > const Duration(minutes: 1);
    await _settingsService.saveResumePosition(
      widget.channel.url,
      keep ? v.position : null,
    );
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    final seconds = _settings?.controlsHideSeconds ?? 4;
    if (seconds <= 0) return;
    _hideTimer = Timer(Duration(seconds: seconds), () {
      final playing = _session?.value.isPlaying ?? false;
      if (mounted && playing) {
        setState(() => _controlsVisible = false);
        if (DeviceTypeService.isTv) _remoteFocus.requestFocus();
      }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Picture-in-Picture non disponibile su questo dispositivo',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
      onlineSubsActive: _onlineCues != null,
      onlineSubsLoading: _onlineSubsLoading,
      onLoadOnlineSubs: _loadOnlineSubtitles,
      onDisableOnlineSubs: _disableOnlineSubtitles,
    ).whenComplete(() {
      if (!mounted) return;
      (DeviceTypeService.isTv ? _remoteFocus : _playFocus).requestFocus();
      _scheduleHide();
    });
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
    _outroTimer?.cancel();
    if (DeviceTypeService.isTv) {
      FocusManager.instance.removeEarlyKeyEventHandler(_onEarlyKey);
    }
    _tvSeekTimer?.cancel();
    _exitTimer?.cancel();
    _failureFocus.dispose();
    _remoteFocus.dispose();
    _playFocus.dispose();
    _activePlayers--;
    if (_activePlayers <= 0) _app.setPlaybackActive(false);
    if (_activePlayers <= 0) {
      _activePlayers = 0;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      if (DeviceTypeService.isTv) {
        // TVs always stay horizontal, also after leaving the player.
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]).then((_) {
          if (_activePlayers == 0) _bridge.setOrientation('landscape');
        });
      } else {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])
            .then((_) {
              // Re-check: a new player may have opened meanwhile.
              if (_activePlayers == 0) _bridge.setOrientation('portrait');
            });
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final settings = _settings;
    final body = session == null || settings == null
        ? Center(child: CircularProgressIndicator(color: AppColors.primary))
        : Stack(
            fit: StackFit.expand,
            children: [
              // Own layer: overlay updates never repaint the video.
              RepaintBoundary(
                child: VideoSurface(session: session, settings: settings),
              ),
              if (!_inPip) ..._buildOverlays(session, settings),
              if (_exitPrompt && DeviceTypeService.isTv)
                const Positioned(
                  top: 32,
                  left: 0,
                  right: 0,
                  child: Center(child: TvExitPrompt()),
                ),
            ],
          );
    return PopScope(
      // TV: the first Back asks for confirmation (see _handleTvBack).
      canPop: !DeviceTypeService.isTv,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && DeviceTypeService.isTv) _handleTvBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: DeviceTypeService.isTv
            ? Focus(focusNode: _remoteFocus, autofocus: true, child: body)
            : body,
      ),
    );
  }

  List<Widget> _buildOverlays(
    PlaybackSession session,
    PlayerSettings settings,
  ) {
    final status = session.status;
    if (status == SessionStatus.failed) {
      return [
        _FailureView(
          session: session,
          onBack: () => Navigator.pop(context),
          retryFocus: DeviceTypeService.isTv ? _failureFocus : null,
        ),
      ];
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
      if (DeviceTypeService.isTv)
        ExcludeFocus(
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: RepaintBoundary(
                child: TvPlayerControls(
                  rows: _tvRows(session),
                  selectedRow: _tvRow,
                  selectedColumn: _tvCol,
                  title: widget.channel.name,
                  subtitle: _isLive
                      ? (context
                                .watch<EpgProvider>()
                                .nowFor(widget.channel)
                                ?.title ??
                            widget.channel.group)
                      : widget.channel.group,
                  isLive: _isLive,
                  locked: _locked,
                  position: session.value.position,
                  duration: session.value.duration,
                  buffered: session.value.bufferedUntil,
                  pendingSeek: _tvSeekTarget,
                  liveDelay: _isLive && session.isBehindLive
                      ? session.liveDelay
                      : null,
                ),
              ),
            ),
          ),
        )
      else
        ExcludeFocus(
          excluding: false,
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: PlayerControls(
                session: session,
                playFocusNode: null,
                title: widget.channel.name,
                subtitle: _isLive
                    ? (context
                              .watch<EpgProvider>()
                              .nowFor(widget.channel)
                              ?.title ??
                          widget.channel.group)
                    : widget.channel.group,
                locked: _locked,
                pipSupported: _pipSupported,
                seekStepSeconds: settings.seekStepSeconds,
                previousChannel: _adjacentLiveChannel(-1),
                nextChannel: _adjacentLiveChannel(1),
                onPreviousChannel: () =>
                    _playLiveChannel(_adjacentLiveChannel(-1)),
                onNextChannel: () => _playLiveChannel(_adjacentLiveChannel(1)),
                onBack: () => Navigator.pop(context),
                onOpenTitle: _isLive ? null : _openTitle,
                onEpisodes: _isEpisode ? _openEpisodes : null,
                onMultiView: _isLive ? _openMultiView : null,
                onPip: _enterPip,
                onMenu: _openMenu,
                onToggleLock: () {
                  setState(() => _locked = !_locked);
                  _scheduleHide();
                },
                onInteraction: _onInteraction,
                onlineSubsActive: _onlineCues != null,
                onlineSubsLoading: _onlineSubsLoading,
                onLoadOnlineSubs: _loadOnlineSubtitles,
                onDisableOnlineSubs: _disableOnlineSubtitles,
              ),
            ),
          ),
        ),
      if (_onlineCues != null)
        SubtitleOverlay(
          cues: _onlineCues!,
          position: session.value.position,
          delay: session.subtitleDelay,
          settings: settings,
        ),
      if (status == SessionStatus.playing &&
          _segments.intro != null &&
          _segments.intro!.contains(session.value.position))
        Positioned(
          right: 24,
          bottom: 96,
          child: SafeArea(
            child: _tvHighlight(
              selected: DeviceTypeService.isTv && !_controlsVisible,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.fast_forward_rounded),
                label: const Text(
                  'Salta Sigla',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: _skipIntro,
              ),
            ),
          ),
        ),
      if (_outroActive && _next != null && !_inPip) _buildOutroOverlay(),
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
          child: SafeArea(
            child: Center(child: _NoticeBanner(text: session.notice!)),
          ),
        ),
    ];
  }

  /// TV: remote-selected look (no focus node; keys are handled above).
  Widget _tvHighlight({required bool selected, required Widget child}) {
    if (!DeviceTypeService.isTv) return child;
    return ExcludeFocus(
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 3,
          ),
        ),
        child: child,
      ),
    );
  }

  /// IntroDB credits: next episode card with a 5 second countdown.
  Widget _buildOutroOverlay() {
    final next = _next!;
    final label = next.season != null && next.episode != null
        ? 'S${next.season} E${next.episode}'
        : 'Prossimo episodio';
    return Positioned(
      right: 24,
      bottom: 96,
      child: SafeArea(
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Prossimo episodio tra $_outroCountdown...',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$label · ${next.name}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: (5 - _outroCountdown) / 5,
                color: AppColors.primary,
                backgroundColor: Colors.white12,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _tvHighlight(
                      selected:
                          DeviceTypeService.isTv &&
                          !_controlsVisible &&
                          _tvOutroCol == 0,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.skip_next_rounded),
                        label: const Text('Prossimo Episodio'),
                        onPressed: () {
                          _outroTimer?.cancel();
                          playNextEpisode();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _tvHighlight(
                    selected:
                        DeviceTypeService.isTv &&
                        !_controlsVisible &&
                        _tvOutroCol == 1,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                      onPressed: _watchCredits,
                      child: const Text('Guarda Crediti'),
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
                color: AppColors.primary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Connessione con $engine...',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
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
          const Icon(
            Icons.swap_horiz_rounded,
            color: AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  final PlaybackSession session;
  final VoidCallback onBack;
  final FocusNode? retryFocus;
  const _FailureView({
    required this.session,
    required this.onBack,
    this.retryFocus,
  });

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
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.error,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Impossibile riprodurre il flusso',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
                  Text(
                    session.error!,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: onBack,
                      child: const Text('Indietro'),
                    ),
                    for (final e in PlayerEngineType.values)
                      OutlinedButton(
                        onPressed: () => session.switchEngine(e),
                        child: Text('Prova con ${e.label}'),
                      ),
                    ElevatedButton.icon(
                      focusNode: retryFocus,
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

class _EpisodePicker extends StatefulWidget {
  final Channel current;
  final Future<List<Channel>> Function() load;
  final HistoryEntry? Function(String id) entryFor;
  const _EpisodePicker({
    required this.current,
    required this.load,
    required this.entryFor,
  });
  @override
  State<_EpisodePicker> createState() => _EpisodePickerState();
}

class _EpisodePickerState extends State<_EpisodePicker> {
  late final Future<List<Channel>> _episodes;
  late int _season;
  final _first = FocusNode(debugLabel: 'episode panel first');
  final _seasonNodes = <int, FocusNode>{};
  int _seasonCount = 0;
  bool _inEpisodes = true;

  @override
  void initState() {
    super.initState();
    _season = widget.current.season ?? 1;
    _episodes = widget.load();
  }

  @override
  void dispose() {
    _first.dispose();
    for (final n in _seasonNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  FocusNode _seasonNode(int season) => _seasonNodes.putIfAbsent(
    season,
    () => FocusNode(debugLabel: 'episode panel season $season'),
  );

  /// Back: from the episode list to the seasons (when there is more than
  /// one), then a second Back closes the panel and resumes playback.
  void _back() {
    if (_inEpisodes && _seasonCount > 1) {
      _seasonNodes[_season]?.requestFocus();
      setState(() => _inEpisodes = false);
      return;
    }
    Navigator.pop(context);
  }

  Widget _episodeRow(Channel episode, int i, int season) {
    final current = episode.id == widget.current.id;
    final entry = widget.entryFor(episode.id);
    final watched = entry?.isWatched ?? false;
    final progress = watched ? null : entry?.progress;
    final number = episode.episode ?? i + 1;
    final image = episode.logo.isNotEmpty ? episode.logo : widget.current.logo;
    return TvFocusable(
      focusNode: i == 0 ? _first : null,
      autofocus: current || (i == 0 && season != (widget.current.season ?? 1)),
      focusedScale: 1.02,
      onFocusChange: (f) {
        if (f && !_inEpisodes) setState(() => _inEpisodes = true);
      },
      onPressed: () => Navigator.pop(context, episode),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.pop(context, episode),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: current
                ? AppColors.primary.withValues(alpha: 0.14)
                : AppColors.card.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: current
                  ? AppColors.primary.withValues(alpha: 0.6)
                  : AppColors.border.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 150,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PosterImage(
                          url: image,
                          fallbackIcon: Icons.movie_outlined,
                        ),
                        if (current)
                          const ColoredBox(
                            color: AppColors.overlay,
                            child: Center(
                              child: Icon(
                                Icons.graphic_eq_rounded,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        if (watched)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: AppColors.success,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: AppColors.background,
                              ),
                            ),
                          ),
                        if (progress != null)
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 6,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 3,
                                color: AppColors.primary,
                                backgroundColor: AppColors.track,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'EPISODIO $number',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      episode.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      current
                          ? 'In riproduzione'
                          : watched
                          ? 'Visto'
                          : progress != null
                          ? 'Visto al ${(progress * 100).round()}%'
                          : 'S$season · E$number',
                      style: TextStyle(
                        color: current
                            ? AppColors.primary
                            : watched
                            ? AppColors.success
                            : AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width < 480
            ? MediaQuery.sizeOf(context).width * .94
            : 480,
        height: MediaQuery.sizeOf(context).height,
        child: Material(
          color: AppColors.glass,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
              child: FocusTraversalGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'EPISODI',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.current.displaySeriesName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        TvFocusable(
                          onPressed: () => Navigator.pop(context),
                          child: IconButton(
                            tooltip: 'Chiudi episodi',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: FutureBuilder<List<Channel>>(
                        future: _episodes,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final all = snapshot.data ?? const <Channel>[];
                          if (all.isEmpty) {
                            return const Center(
                              child: Text('Episodi non disponibili'),
                            );
                          }
                          final seasons =
                              all.map((c) => c.season ?? 1).toSet().toList()
                                ..sort();
                          _seasonCount = seasons.length;
                          final selectedSeason = seasons.contains(_season)
                              ? _season
                              : seasons.first;
                          final episodes = all
                              .where((c) => (c.season ?? 1) == selectedSeason)
                              .toList();
                          return Column(
                            children: [
                              if (seasons.length > 1)
                                SizedBox(
                                  height: 48,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: seasons.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (context, i) {
                                      final s = seasons[i];
                                      final active = selectedSeason == s;
                                      void choose() {
                                        setState(() => _season = s);
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              if (mounted) {
                                                _first.requestFocus();
                                              }
                                            });
                                      }

                                      return TvFocusable(
                                        focusNode: _seasonNode(s),
                                        onFocusChange: (f) {
                                          if (f && _inEpisodes) {
                                            setState(() => _inEpisodes = false);
                                          }
                                        },
                                        onPressed: choose,
                                        child: GestureDetector(
                                          onTap: choose,
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 160,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: active
                                                  ? AppColors.textPrimary
                                                  : AppColors.card,
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                            ),
                                            child: Text(
                                              'Stagione $s',
                                              style: TextStyle(
                                                color: active
                                                    ? AppColors.background
                                                    : AppColors.textPrimary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: ListView.separated(
                                  key: ValueKey(selectedSeason),
                                  padding: const EdgeInsets.only(bottom: 12),
                                  itemCount: episodes.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, i) => _episodeRow(
                                    episodes[i],
                                    i,
                                    selectedSeason,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
