import '../services/playback_progress_writer.dart';
import '../services/episode_metadata_service.dart';
import '../models/episode_metadata.dart';

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
import '../player/playback_engine.dart';
import '../player/tv_playback_shortcuts.dart';
import '../providers/history_provider.dart';
import '../services/imdb_resolver.dart';
import '../services/catalog_rating_service.dart';
import '../services/introdb_service.dart';
import '../services/playback_assistance.dart';
import '../services/segment_library.dart';
import '../services/foreground_policy.dart';
import '../widgets/player/provider_check_button.dart';
import '../services/playback_work_policy.dart';
import '../services/native_player_bridge.dart';
import '../services/player_settings_service.dart';
import '../services/movie_hash.dart';
import '../services/subtitles_service.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import '../widgets/episode_still_overlay.dart';
import '../widgets/player/live_channel_picker.dart';
import '../services/recent_live_channels.dart';
import '../widgets/player/player_controls.dart';
import '../widgets/player/player_format.dart';
import '../widgets/player/player_gestures.dart';
import '../widgets/player/player_sheets.dart';
import '../widgets/player/player_stats.dart';
import '../widgets/player/subtitle_overlay.dart';
import '../widgets/player/tv_player_controls.dart';
import '../widgets/player/video_surface.dart';
import '../widgets/player/tv_playback_info.dart';
import '../widgets/player/tv_quick_playback_sheet.dart';
import '../widgets/poster_card.dart';
import '../widgets/tv_wrap_navigation.dart';
import '../widgets/tv_focusable.dart';

class PlayerScreen extends StatefulWidget {
  final Channel channel;
  final Duration? startAt;
  final bool archivePlayback;

  /// Optional engine seam for deterministic remote-input tests.
  final PlaybackEngine Function(PlayerEngineType)? engineFactory;
  final Future<EpisodeSegments> Function()? segmentsSource;

  /// Ordered episodes of the series being watched (null for films/live).
  final List<Channel>? queue;

  const PlayerScreen({
    super.key,
    required this.channel,
    this.startAt,
    this.archivePlayback = false,
    this.engineFactory,
    this.segmentsSource,
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
  int _tvRepeatCount = 0;
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
  final _progressWriter = PlaybackProgressWriter();
  final _bridge = NativePlayerBridge.instance;
  late final HistoryProvider _history;

  PlayerSettings? _settings;
  PlaybackSession? _session;
  StreamSubscription<bool>? _pipSub;
  Timer? _hideTimer;
  Timer? _resumeTimer;
  Timer? _noticeTimer;
  bool _controlsVisible = false;
  bool _tvInfoVisible = false;
  bool _tvQuickPanelOpen = false;
  bool _tvTogglePending = false;
  Timer? _tvInfoTimer;
  bool _introWasActive = false;
  bool _wasPlaying = false;
  bool _locked = false;
  bool _inPip = false;
  bool _pipSupported = false;
  bool _statsVisible = false;
  bool _orientationApplied = false;
  Size _pipSize = Size.zero;

  /// Resume point not yet reached: progress is not saved until the seek
  /// lands, so a slow start never overwrites the saved position with 0.
  Duration? _pendingResume;
  bool _initialProgressSaved = false;
  DateTime _openedAt = DateTime.now();
  List<Channel>? _queue;
  Channel? _next;
  bool _nextDismissed = false;
  bool _advancing = false;

  // Sottotitoli online (OpenSubtitles), disegnati sopra il video.
  List<SubtitleCue>? _onlineCues;
  bool _onlineSubsLoading = false;
  int _onlineVariant = 0;

  // IntroDB skip segments (empty when unavailable: no buttons are shown).
  EpisodeSegments _segments = EpisodeSegments.empty;
  EpisodeSegments _chapterSegments = EpisodeSegments.empty;
  PlaybackEngine? _chaptersEngine;
  int _chapterAttempts = 0;
  bool _chapterReadInFlight = false;
  DateTime _chaptersNotBefore = DateTime(2000);
  bool _outroVerified = false;
  bool _outroDisabled = false;
  bool _outroActive = false;
  int _outroCountdown = 5;
  Timer? _outroTimer;

  bool get _isLive =>
      widget.channel.type == ContentType.live && !widget.archivePlayback;

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
    _screenOffSub = _bridge.screenOff.listen((_) {
      // Phones may keep on-demand audio with the screen off when allowed.
      final s = _settings;
      final keepAudio =
          s != null && s.backgroundAudio && !DeviceTypeService.isTv && !_isLive;
      if (!keepAudio && !_inPip) _closeProviderStream();
    });
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
    if (_tvQuickPanelOpen) return KeyEventResult.ignored;
    if (_isBackKey(key)) {
      if (event is KeyDownEvent) _handleTvBack();
      // Key up is swallowed too, so Android never adds a second "back".
      return KeyEventResult.handled;
    }
    final session = _session;
    if (session == null) return KeyEventResult.ignored;
    // The error page uses normal buttons and focus.
    if (session.status == SessionStatus.failed) return KeyEventResult.ignored;
    if (_advancing || _exiting) return KeyEventResult.handled;
    final ours = _isOkKey(key) || _isArrowKey(key) || _mediaKeys.contains(key);
    if (!ours) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.handled;
    _onTvKey(session, key, repeat: event is KeyRepeatEvent);
    return KeyEventResult.handled;
  }

  bool _introActive(PlaybackSession session) => _skipChoice(session) != null;

  SkipChoice? _skipChoice(PlaybackSession session) {
    if (session.status != SessionStatus.playing) return null;
    return activeSkip(_effectiveSegments, session.value.position);
  }

  /// Last episode and films have no "next" card, so the credits button is
  /// the way into a scene that follows them.
  SkipChoice? _creditsChoice(PlaybackSession session) {
    if (_next != null || session.status != SessionStatus.playing) return null;
    return postCreditsSkip(_effectiveSegments, session.value.position);
  }

  SkipChoice? _visibleSkip(PlaybackSession session) =>
      _skipChoice(session) ?? _creditsChoice(session);

  bool _canSeek(PlaybackSession session) =>
      !_isLive && session.value.duration > Duration.zero;

  void _onTvKey(
    PlaybackSession session,
    LogicalKeyboardKey key, {
    required bool repeat,
  }) {
    final step = Duration(seconds: _settings?.seekStepSeconds ?? 10);
    // Native pause may finish after the key release; no second transport
    // command may race it, including media buttons or progress-row OK.
    if (_tvTogglePending) return;
    if (repeat && (_isOkKey(key) || _mediaKeys.contains(key))) return;

    // Dedicated remote buttons work in every state.
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      session.togglePlay();
      if (_controlsVisible) _scheduleHide();
      return;
    }
    if (key == LogicalKeyboardKey.mediaPlay) {
      if (!session.value.isPlaying) session.togglePlay();
      if (_controlsVisible) _scheduleHide();
      return;
    }
    if (key == LogicalKeyboardKey.mediaPause) {
      if (session.value.isPlaying) session.togglePlay();
      if (_controlsVisible) _scheduleHide();
      return;
    }
    if (key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.mediaRewind) {
      if (_canSeek(session)) {
        final delta = step * 3;
        _tvSeekBy(
          key == LogicalKeyboardKey.mediaRewind ? -delta : delta,
          repeat,
          revealControls: _controlsVisible,
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
      if (!_isLive) _showTvInfo();
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
      if (ok || up || down) {
        final action = tvHiddenAction(
          ok
              ? TvHiddenKey.ok
              : up
              ? TvHiddenKey.up
              : TvHiddenKey.down,
          live: _isLive,
          repeat: repeat,
          intro: _visibleSkip(session) != null,
          outro: outro,
        );
        switch (action) {
          case TvHiddenAction.skipIntro:
            _skipIntro();
          case TvHiddenAction.outro:
            if (_tvOutroCol == 0) {
              _outroTimer?.cancel();
              playNextEpisode();
            } else {
              _watchCredits();
            }
          case TvHiddenAction.pauseAndControls:
            _pauseAndShowTvControls(session);
          case TvHiddenAction.previousChannel:
            _playLiveChannel(_adjacentLiveChannel(-1));
          case TvHiddenAction.nextChannel:
            _playLiveChannel(_adjacentLiveChannel(1));
          case TvHiddenAction.info:
            _showTvInfo();
          case TvHiddenAction.quickPanel:
            _openTvQuickPanel(session);
          case TvHiddenAction.none:
            break;
        }
        return;
      }
      if (outro && (left || right)) {
        setState(() => _tvOutroCol = right ? 1 : 0);
        return;
      }
      // Left on a live channel opens the channel list over the picture
      // (timeshift stays in the controls and on Right).
      if (_isLive && left) {
        _openChannelList();
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
        _tvSeekBy(left ? -step : step, repeat, revealControls: false);
        return;
      }
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
    // Holding Left/Right anywhere in the controls scrubs like dragging the
    // bar: the selection jumps to the progress row and the seek accelerates.
    if ((left || right) &&
        repeat &&
        !_isLive &&
        _canSeek(session) &&
        rows.any((r) => r.kind == TvPlayerRowKind.progress)) {
      if (_tvRow != TvPlayerRowKind.progress) {
        setState(() => _tvRow = TvPlayerRowKind.progress);
      }
      _tvSeekBy(left ? -step : step, true);
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
    _dismissTvInfo();
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

  void _tvSeekBy(Duration delta, bool repeat, {bool revealControls = true}) {
    final session = _session;
    if (session == null) return;
    final duration = session.value.duration;
    if (duration <= Duration.zero) return;
    final base = _tvSeekTarget ?? session.value.position;
    _tvRepeatCount = repeat ? _tvRepeatCount + 1 : 0;
    var target = base + delta * tvScrubMultiplier(repeat, _tvRepeatCount);
    if (target < Duration.zero) target = Duration.zero;
    final end = duration - const Duration(seconds: 1);
    if (target > end) target = end;
    setState(() => _tvSeekTarget = target);
    _tvSeekTimer?.cancel();
    // One seek after the user stops pressing: repeated seeks on every press
    // made the engines stutter and rebuffer.
    _tvSeekTimer = Timer(const Duration(milliseconds: 700), _commitTvSeek);
    if (revealControls) _onInteraction();
  }

  void _restartFromBeginning() {
    _tvSeekTimer?.cancel();
    setState(() => _tvSeekTarget = null);
    final session = _session;
    if (session == null) return;
    session.seekTo(Duration.zero).then((_) {
      if (!session.value.isPlaying) session.togglePlay();
    });
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
    if (_tvInfoVisible) {
      _dismissTvInfo();
      return;
    }
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

  Future<void> _pauseAndShowTvControls(PlaybackSession session) async {
    if (_tvTogglePending) return;
    _tvTogglePending = true;
    _showTvControls(TvPlayerRowKind.center);
    try {
      // Do not accidentally resume a video that was already paused.
      if (session.value.isPlaying) await session.togglePlay();
    } catch (_) {
      // Native playback errors continue through the existing session UI.
    } finally {
      _tvTogglePending = false;
    }
  }

  void _dismissTvInfo() {
    _tvInfoTimer?.cancel();
    if (_tvInfoVisible && mounted) setState(() => _tvInfoVisible = false);
  }

  void _showTvInfo() {
    _tvInfoTimer?.cancel();
    setState(() => _tvInfoVisible = true);
    _tvInfoTimer = Timer(const Duration(seconds: 6), _dismissTvInfo);
  }

  Future<void> _openTvQuickPanel(PlaybackSession session) async {
    if (_tvQuickPanelOpen || _advancing) return;
    _dismissTvInfo();
    _hideTimer?.cancel();
    _tvQuickPanelOpen = true;
    try {
      final choice = await showTvQuickPlaybackSheet(
        context,
        episodes: _isEpisode,
      );
      if (!mounted || _session != session || _advancing) return;
      switch (choice) {
        case TvQuickPlaybackChoice.audio:
          await showAudioSheet(context, session);
        case TvQuickPlaybackChoice.subtitles:
          await showSubtitleSheet(
            context,
            session,
            onlineActive: _onlineCues != null,
            onlineLoading: _onlineSubsLoading,
            onLoadOnline: _loadOnlineSubtitles,
            onDisableOnline: _disableOnlineSubtitles,
          );
        case TvQuickPlaybackChoice.episodes:
          await _openEpisodes();
        case null:
          break;
      }
    } finally {
      _tvQuickPanelOpen = false;
      if (mounted && !_advancing) {
        _remoteFocus.requestFocus();
        if (_controlsVisible) _scheduleHide();
      }
    }
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
        if (!_isLive && canSeek)
          TvPlayerAction(
            id: 'restart',
            icon: Icons.replay_rounded,
            label: 'Ricomincia',
            onPressed: _restartFromBeginning,
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
          icon: !session.isLive && v.isEnded
              ? Icons.replay_rounded
              : !session.liveResumePending && v.isPlaying
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          label: !session.isLive && v.isEnded
              ? 'Riproduci di nuovo'
              : !session.liveResumePending && v.isPlaying
              ? 'Pausa'
              : 'Riproduci',
          primary: true,
          onPressed: () {
            if (!_tvTogglePending) session.togglePlay();
          },
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
        if (_isLive &&
            (session.isBehindLive || !v.isPlaying || session.liveResumePending))
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
        if (_visibleSkip(session) case final skip?)
          TvPlayerAction(
            id: 'skipIntro',
            icon: Icons.fast_forward_rounded,
            label: skip.label,
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
    await (previous?.released ?? Future<void>.value());
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
          if (_queue == null) await _resolveQueue();
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
    await (previous?.released ?? Future<void>.value());
    if (!mounted) return;
    playChannel(
      context,
      selected,
      queue: _queue,
      startAt: _history.entryFor(selected.id)?.resumePosition,
      replace: true,
    );
  }

  /// Local copy first, then the shared cache. A miss does not block playback.
  Future<void> _loadSegments() async {
    final source = widget.segmentsSource;
    if (source != null) {
      final segments = await source();
      if (!mounted) return;
      setState(() => _segments = segments);
      _onSessionChanged();
      return;
    }
    await SegmentLibrary.instance.deliver(widget.channel, (segments) {
      if (!mounted) return;
      setState(() => _segments = segments);
      _onSessionChanged();
    });
  }

  /// Cerca e scarica i sottotitoli in italiano da OpenSubtitles (via cloud).
  /// Per le serie risolve l'IMDb della serie e usa stagione/episodio del
  /// canale; per i film cerca per titolo. Gli errori finiscono in uno
  /// snackbar e la riproduzione continua senza sottotitoli.
  Future<void> _loadOnlineSubtitles() async {
    if (_isLive || _onlineSubsLoading) return;
    setState(() => _onlineSubsLoading = true);
    try {
      final c = widget.channel;
      // Livello 1: una traccia italiana incorporata è già perfettamente
      // sincronizzata, quindi ha la precedenza sui file scaricati.
      if (_onlineCues == null && await _selectEmbeddedItalian()) return;
      if (_isEpisode && (c.season == null || c.episode == null)) {
        throw 'stagione o episodio non identificati: usa la traccia incorporata';
      }
      final title = _isEpisode
          ? (c.seriesName?.isNotEmpty == true ? c.seriesName! : c.name)
          : c.name;
      final saved = CatalogRatingService.instance.imdbIdOf(c);
      final imdbId = saved ??
          await ImdbResolver.getImdbId(
            title: title,
            isMovie: !_isEpisode,
          );
      if (saved == null && imdbId != null) {
        CatalogRatingService.instance.noteImdbId(c, imdbId);
      }
      if (imdbId == null) throw 'titolo non trovato su TMDB';
      final variant = _onlineCues == null ? 0 : (_onlineVariant + 1) % 5;
      // Livello 2: impronta esatta del file (solo alla prima richiesta).
      final hash = variant == 0 ? await MovieHash.fromUrl(c.url) : null;
      final cues = await SubtitlesService.fetch(
        imdbId: imdbId,
        season: _isEpisode ? c.season : null,
        episode: _isEpisode ? c.episode : null,
        variant: variant,
        movieHash: hash?.hash,
        byteSize: hash?.size,
      );
      if (!mounted) return;
      // Evita la doppia scritta spegnendo la traccia incorporata.
      await _session?.setExternalSubtitles(true);
      if (mounted)
        setState(() {
          _onlineCues = cues;
          _onlineVariant = variant;
        });
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

  Future<bool> _selectEmbeddedItalian() async {
    final session = _session;
    if (session == null) return false;
    try {
      final track = (await session.subtitleTracks())
          .where((t) => trackMatchesLanguage(t, 'it'))
          .firstOrNull;
      if (track == null) return false;
      await session.selectSubtitleTrack(track);
      if (mounted) {
        setState(() => _onlineCues = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sottotitoli italiani interni attivati'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _disableOnlineSubtitles() {
    _session?.setExternalSubtitles(false);
    setState(() => _onlineCues = null);
  }

  EpisodeSegments get _effectiveSegments {
    final duration = _session?.value.duration ?? Duration.zero;
    return mergeSkipSegments(
      validSegments(_segments, duration),
      validSegments(_chapterSegments, duration),
    );
  }

  Future<void> _readLocalChapters(PlaybackSession session) async {
    final engine = session.engine;
    final movie = widget.channel.type == ContentType.movie;
    if ((!_isEpisode && !movie) || engine == null || _chapterReadInFlight)
      return;
    if (!identical(engine, _chaptersEngine)) {
      _chaptersEngine = engine;
      _chapterAttempts = 0;
      _chapterSegments = EpisodeSegments.empty;
      _chaptersNotBefore = DateTime(2000);
    }
    if (!session.value.isReady ||
        session.value.duration <= Duration.zero ||
        DateTime.now().isBefore(_chaptersNotBefore) ||
        _chapterAttempts >= 3 ||
        _chapterSegments.all.isNotEmpty)
      return;
    _chapterReadInFlight = true;
    _chapterAttempts++;
    try {
      final chapters = await engine.chapters();
      if (!mounted ||
          !identical(_session, session) ||
          !identical(session.engine, engine))
        return;
      final parsed = chapterSegments(chapters, session.value.duration);
      if (parsed.all.isEmpty) {
        if (_chapterAttempts < 3) {
          _chaptersNotBefore = DateTime.now().add(const Duration(seconds: 2));
        }
        return;
      }
      _chapterAttempts = 3;
      setState(() => _chapterSegments = parsed);
      _onSessionChanged();
    } catch (_) {
      /* Local chapter support is optional. */
    } finally {
      _chapterReadInFlight = false;
    }
  }

  void _skipIntro() {
    final session = _session;
    if (session == null) return;
    final choice = _visibleSkip(session);
    if (choice == null) return;
    _hideTimer?.cancel();
    setState(() => _controlsVisible = false);
    session.seekTo(choice.target);
    if (DeviceTypeService.isTv) _remoteFocus.requestFocus();
  }

  void _checkOutro(Duration position) {
    final session = _session;
    final outro = _effectiveSegments.outro;
    if (session == null || _next == null || _outroDisabled || _advancing)
      return;
    final inOutro = outro != null
        ? position >= outro.start
        : suggestNext(position: position, duration: session.value.duration);
    _outroVerified = outro != null;
    if (inOutro && !_outroActive) {
      _outroActive = true;
      _outroCountdown = 5;
      _outroTimer?.cancel();
      if (_settings?.autoNextEpisode == true && _outroVerified)
        _outroTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted || _settings?.autoNextEpisode != true) return t.cancel();
          final current = _session;
          if (current == null ||
              !current.value.isPlaying ||
              !ForegroundPolicy.instance.active ||
              _route?.isCurrent != true)
            return;
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

  void playNextEpisode() => _playNext(completeCurrent: _outroVerified);

  Future<void> _playNext({bool completeCurrent = false}) async {
    final next = _next;
    if (next == null || _advancing) return;
    _advancing = true;
    _outroTimer?.cancel();
    _resumeTimer?.cancel();
    if (completeCurrent) {
      final runtime = _session?.value.duration;
      await _progressWriter.complete(() async {
        await _history.markWatched(widget.channel, duration: runtime);
        await _settingsService.saveResumePosition(widget.channel.url, null);
      });
    } else {
      await _saveResume();
    }
    if (!mounted) return;
    final previous = _session;
    previous?.removeListener(_onSessionChanged);
    setState(() => _session = null);
    previous?.dispose();
    // Wait until decoder, surface and provider connection are really free.
    await (previous?.released ?? Future<void>.value());
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

  /// Transparent channel list over the playing live picture: playback
  /// continues underneath, OK switches channel, one Back closes it.
  Future<void> _openChannelList() async {
    if (!_isLive || _advancing) return;
    _hideTimer?.cancel();
    final app = _app;
    final epg = context.read<EpgProvider>();
    final all = [
      for (final g in app.groupedCatalog(ContentType.live))
        for (final e in g.entries) e.primary,
    ];
    final recent = [
      for (final id in RecentLiveChannels.instance.ids)
        if (app.channelById(id) case final c?)
          if (c.type == ContentType.live) c,
    ];
    final favorites = [
      for (final c in app.favorites)
        if (c.type == ContentType.live) c,
    ];
    final groups = [
      LiveChannelGroup('Tutti', all),
      if (favorites.isNotEmpty) LiveChannelGroup('Preferiti', favorites),
      if (recent.isNotEmpty) LiveChannelGroup('Visti di recente', recent),
      for (final g in app.groupedCatalog(ContentType.live))
        LiveChannelGroup(g.label, [for (final e in g.entries) e.primary]),
    ];
    final selected = await showGeneralDialog<Channel>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Chiudi elenco canali',
      barrierColor: AppColors.clear,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => LiveChannelPicker(
        current: widget.channel,
        groups: groups,
        nowOnAir: (c) => epg.nowFor(c)?.title,
      ),
      transitionBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(-0.08, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted) return;
    _remoteFocus.requestFocus();
    if (selected == null || selected.id == widget.channel.id) return;
    await _playLiveChannel(selected);
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
    await (previous?.released ?? Future<void>.value());
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
    if (startAt == null &&
        !_isLive &&
        !widget.archivePlayback &&
        settings.resumePlayback) {
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
      engineFactory: widget.engineFactory,
      onPositionCommitted: (position) {
        _pendingResume = position;
        _openedAt = DateTime.now();
        return _saveResume(position: position);
      },
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
        (_) => _saveResume(periodic: true),
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
    unawaited(_readLocalChapters(session));
    final introActive = _visibleSkip(session) != null;
    if (introActive && !_introWasActive) {
      _hideTimer?.cancel();
      _controlsVisible = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && DeviceTypeService.isTv && _route?.isCurrent == true) {
          _remoteFocus.requestFocus();
        }
      });
    }
    _introWasActive = introActive;
    if (!_initialProgressSaved &&
        v.isReady &&
        v.duration > Duration.zero &&
        (_pendingResume == null ||
            (v.position - (_pendingResume ?? Duration.zero)).abs() <=
                const Duration(seconds: 10))) {
      _initialProgressSaved = true;
      unawaited(_saveResume(periodic: true));
    }
    if (_wasPlaying &&
        (!v.isPlaying || v.isEnded) &&
        !PlaybackWorkPolicy.instance.blocksCloud) {
      _saveResume();
    }
    _wasPlaying = v.isPlaying;

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
    if (!_isLive &&
        settings.autoNextEpisode &&
        v.isEnded &&
        _next != null &&
        !_nextDismissed &&
        !_advancing &&
        ForegroundPolicy.instance.active &&
        _route?.isCurrent == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_nextDismissed &&
            _settings?.autoNextEpisode == true &&
            _session?.value.isEnded == true &&
            ForegroundPolicy.instance.active &&
            _route?.isCurrent == true)
          _playNext();
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
      _visibleSkip(session)?.label,
      _visibleSkip(session)?.target.inSeconds,
    ]);
    final now = DateTime.now();
    if (signature != _lastSignature) {
      _lastSignature = signature;
      _lastPositionBuild = now;
      return true;
    }
    final showsPosition = _controlsVisible || _statsVisible || _tvInfoVisible;
    if (!showsPosition) return false;
    const gap = 500;
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
    if (state == AppLifecycleState.resumed) {
      _backgroundStop?.cancel();
      return;
    }
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) &&
        settings != null) {
      _saveResume();
      if (state == AppLifecycleState.detached) {
        _closeProviderStream();
        return;
      }
      // Background audio keeps on-demand titles going on phones only; on TV
      // and for live channels the provider connection is always closed.
      final keepAudio =
          settings.backgroundAudio && !DeviceTypeService.isTv && !_isLive;
      if (keepAudio) return;
      // PiP also pauses the activity; give the PiP callback time to land.
      _backgroundStop?.cancel();
      _backgroundStop = Timer(const Duration(milliseconds: 800), () {
        if (mounted && !_inPip) _closeProviderStream();
      });
    }
  }

  Timer? _backgroundStop;
  StreamSubscription<void>? _screenOffSub;
  bool _providerClosed = false;

  /// Releases the player and the provider connection immediately, then
  /// removes the player page. Used when the app leaves the screen or the TV
  /// is switched off, so no stream stays open while nobody is watching.
  void _closeProviderStream() {
    if (_providerClosed || !mounted) return;
    _providerClosed = true;
    _backgroundStop?.cancel();
    _saveResume();
    _session?.engine?.pause();
    _session?.stopStream();
    _bridge.setKeepScreenOn(false);
    final route = ModalRoute.of(context);
    final nav = Navigator.of(context);
    if (route != null && route.isActive) {
      if (route.isCurrent) {
        nav.pop();
      } else {
        nav.removeRoute(route);
      }
    }
  }

  Future<void> _saveResume({bool periodic = false, Duration? position}) async {
    final session = _session;
    if (session == null || _isLive || widget.archivePlayback) return;
    final v = session.value;
    if (!v.isReady || v.duration <= Duration.zero) return;
    final actualPosition = position ?? v.position;
    final pending = _pendingResume;
    if (pending != null && position == null) {
      final landed =
          (v.position - pending).abs() <= const Duration(seconds: 10);
      final gaveUp =
          DateTime.now().difference(_openedAt) > const Duration(seconds: 40);
      if (!landed && !gaveUp) return;
      _pendingResume = null;
    }
    await _progressWriter.save(() async {
      await _history.updatePosition(
        widget.channel.id,
        actualPosition,
        v.duration,
        // A paused video syncs at once so another device resumes exactly.
        periodic: periodic && v.isPlaying,
      );
      if (_settings?.resumePlayback != true) return;
      final remaining = v.duration - actualPosition;
      final keep =
          actualPosition > Duration.zero &&
          remaining > const Duration(minutes: 1);
      await _settingsService.saveResumePosition(
        widget.channel.url,
        keep ? actualPosition : null,
      );
    });
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveResume();
    _hideTimer?.cancel();
    _resumeTimer?.cancel();
    _tvInfoTimer?.cancel();
    _noticeTimer?.cancel();
    _pipSub?.cancel();
    _screenOffSub?.cancel();
    _backgroundStop?.cancel();
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

  String _episodeInfoTitle() {
    final metadata = EpisodeMetadataService.instance.forChannel(widget.channel);
    if (metadata == null) return widget.channel.name;
    final code =
        'S${metadata.season.toString().padLeft(2, '0')} E${metadata.episode.toString().padLeft(2, '0')}';
    return '${widget.channel.displaySeriesName} · $code${metadata.title.isEmpty ? '' : ' · ${metadata.title}'}';
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
          playbackUrl: widget.channel.url,
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
      if (DeviceTypeService.isTv && _tvInfoVisible && !_controlsVisible)
        TvPlaybackInfo(
          title: _episodeInfoTitle(),
          episodeMetadata: EpisodeMetadataService.instance.forChannel(
            widget.channel,
          ),
          plot: episodeSynopsis(
            EpisodeMetadataService.instance
                .forChannel(widget.channel)
                ?.overview,
            widget.channel.plot,
            _app.seriesFolderFor(widget.channel.seriesKey ?? '')?.plot,
          ),
          duration: session.value.duration,
          position: session.value.position,
          speed: session.speed,
          playing: session.value.isPlaying,
        ),
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
      // Arrow seek with the controls hidden: a small time bubble only.
      if (!_controlsVisible && _tvSeekTarget != null)
        Positioned(
          top: 40,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(
                  '${_tvSeekTarget! >= session.value.position ? '»' : '«'}  '
                  '${formatDuration(_tvSeekTarget!)} / ${formatDuration(session.value.duration)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      if (_onlineCues case final cues?)
        ListenableBuilder(
          listenable: session,
          builder: (context, _) => SubtitleOverlay(
            cues: cues,
            position: session.value.position,
            delay: session.subtitleDelay,
            settings: settings,
            playing: session.value.isPlaying,
          ),
        ),
      if (_visibleSkip(session) case final skip?
          when status == SessionStatus.playing)
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
                label: Text(
                  skip.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          // Light glass without blur: the scene stays visible if the card
          // appears early, and no blur pass runs over the video surface.
          child: DecoratedBox(
            decoration: const BoxDecoration(),
            child: Container(
              width: 340,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 32,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _settings?.autoNextEpisode == true && _outroVerified
                        ? 'Prossimo episodio tra $_outroCountdown...'
                        : 'Prossimo episodio disponibile',
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
                  if (_settings?.autoNextEpisode == true && _outroVerified)
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
        color: AppColors.card.withValues(alpha: 0.55),
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
  final String playbackUrl;
  final VoidCallback onBack;
  final FocusNode? retryFocus;
  const _FailureView({
    required this.session,
    required this.playbackUrl,
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
                ProviderCheckButton(
                  playbackUrl: playbackUrl,
                  playbackFailed: true,
                  automatic: true,
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
                TvWrapNavigation(
                  child: Wrap(
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
    final images = episodeArtwork(
      EpisodeMetadataService.instance.forChannel(episode),
      episode.logo,
      widget.current.logo,
    );
    final image = images.firstOrNull;
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
                          fallbackUrls: images.skip(1).toList(),
                          fallbackIcon: Icons.movie_outlined,
                        ),
                        EpisodeStillOverlay(
                          watched: watched,
                          progress: progress,
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

/// Seek multiplier while a remote arrow is held: 3x at first, growing every
/// ~10 repeats up to 30x, so long titles can be crossed quickly.
int tvScrubMultiplier(bool repeat, int repeats) {
  if (!repeat) return 1;
  return (3 + (repeats ~/ 10) * 3).clamp(3, 30);
}
