import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/multiview_layout.dart';
import '../models/player_settings.dart';
import '../player/playback_session.dart';
import '../player/playback_engine.dart';
import '../player/multiview_audio.dart';
import '../services/native_player_bridge.dart';
import '../providers/app_provider.dart';
import '../providers/ui_settings.dart';
import '../services/device_type_service.dart';
import '../services/player_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/poster_card.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/tv_text_field.dart';
import '../widgets/settings_tiles.dart';
import '../widgets/player/video_surface.dart';

class _Slot {
  _Slot(this.channel, this.session);
  final Channel channel;
  final PlaybackSession session;
  final focus = FocusNode();

  /// Keeps the tile's player alive when the layout changes (rows/columns
  /// rebuild): without it the video view was recreated and went black.
  final viewKey = GlobalKey();

  // Per-tile health, used by the MultiView watchdog.
  Duration? lastPosition;
  int? lastFrames;
  DateTime? stallSince;
  DateTime? playingSince;
  DateTime? retryAt;
  int autoRetries = 0;
  int stallRestarts = 0;

  void dispose() {
    session.dispose();
    focus.dispose();
  }
}

class MultiViewScreen extends StatefulWidget {
  const MultiViewScreen({super.key, this.initialChannel, this.engineFactory});
  final Channel? initialChannel;
  final PlaybackEngine Function(PlayerEngineType)? engineFactory;
  @override
  State<MultiViewScreen> createState() => _MultiViewScreenState();
}

class _MultiViewScreenState extends State<MultiViewScreen>
    with WidgetsBindingObserver {
  static const maxChannels = 4;
  final _slots = <_Slot>[];
  final _addFocus = FocusNode(debugLabel: 'MultiView add');
  late final AppProvider _app;
  late final MultiViewAudio<PlaybackSession> _audio;
  _Slot? _selected;
  _Slot? _expanded;
  bool _background = false;
  bool _modal = false;
  bool _adding = false;
  bool _closed = false;
  Timer? _watchdog;

  /// Every second: resumes tiles paused by the system, restarts a tile whose
  /// picture is frozen and retries a failed tile on its own, without
  /// touching the others.
  void _tick() {
    if (!mounted || _background || _closed) return;
    final now = DateTime.now();
    for (final slot in List.of(_slots)) {
      final session = slot.session;
      if (session.status == SessionStatus.failed) {
        _autoRetry(slot, now);
        continue;
      }
      if (session.status != SessionStatus.playing) {
        slot.stallSince = null;
        slot.lastPosition = null;
        slot.lastFrames = null;
        continue;
      }
      if (session.viewerPausedLive) {
        slot.stallSince = null;
        slot.lastFrames = null;
        continue;
      }
      slot.retryAt = null;
      slot.playingSince ??= now;
      if (now.difference(slot.playingSince!) > const Duration(seconds: 30)) {
        slot.autoRetries = 0;
      }
      final v = session.value;
      if (!v.isPlaying && !v.isEnded && !v.isBuffering) {
        unawaited(session.ensurePlaying());
      }
      final frames = session.engine?.renderedFrameCount;
      if (frames != null) {
        final previous = slot.lastFrames;
        slot.lastFrames = frames;
        if (previous != null && frames > previous) {
          slot.stallRestarts = 0;
          slot.lastPosition = v.position;
          slot.stallSince = now;
          continue;
        }
        if (previous != null &&
            frames <= previous &&
            v.isPlaying &&
            !v.isBuffering &&
            slot.stallRestarts < 2) {
          slot.stallSince ??= now;
          if (now.difference(slot.stallSince!) > const Duration(seconds: 12)) {
            slot.stallRestarts++;
            _restart(slot);
          }
          continue;
        }
      }
      // Position can sit still on a live tile while the picture is fine.
      // Without a frame counter, a playing tile is left alone.
      if (v.isPlaying && !v.isBuffering) {
        slot.lastPosition = v.position;
        slot.stallSince = now;
        continue;
      }
      if (v.position != slot.lastPosition) {
        slot.lastPosition = v.position;
        slot.stallSince = now;
        continue;
      }
      slot.stallSince ??= now;
      if (now.difference(slot.stallSince!) > const Duration(seconds: 12)) {
        _restart(slot);
      }
    }
  }

  void _restart(_Slot slot) {
    slot
      ..stallSince = null
      ..lastPosition = null
      ..lastFrames = null
      ..playingSince = null;
    unawaited(slot.session.retry().then((_) => _syncAudio()));
  }

  void _autoRetry(_Slot slot, DateTime now) {
    final limit = _connectionLimit(slot) ? 1 : 3;
    if (slot.autoRetries >= limit) return;
    final at = slot.retryAt;
    if (at == null) {
      slot.retryAt = now.add(Duration(seconds: 4 + 4 * slot.autoRetries));
      return;
    }
    if (now.isBefore(at)) return;
    slot
      ..retryAt = null
      ..autoRetries += 1;
    _restart(slot);
  }

  bool _connectionLimit(_Slot slot) =>
      (slot.session.error ?? '').contains('connessioni simultanee');

  @override
  void initState() {
    super.initState();
    _app = context.read<AppProvider>();
    _audio = MultiViewAudio((session, volume) async {
      // Tiles always keep playing: only the volume changes, and a tile
      // paused by Android's audio focus is resumed.
      await session.setVolume(volume);
      await session.ensurePlaying();
    });
    _app.setPlaybackActive(true);
    _app.addListener(_checkAllowed);
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    WidgetsBinding.instance.addObserver(this);
    _screenOffSub =
        NativePlayerBridge.instance.screenOff.listen((_) => _closeAllStreams());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final channel = widget.initialChannel;
      if (channel != null && _allowed(channel)) {
        _addChannel(channel);
      } else {
        _chooseChannel();
      }
    });
  }

  bool _allowed(Channel c) =>
      c.type == ContentType.live &&
      c.isPlayable &&
      _app.channelById(c.id) != null &&
      (!_app.kidsMode || _app.isKidsContent(c));

  void _checkAllowed() {
    final removed = _slots.where((s) => !_allowed(s.channel)).toList();
    for (final slot in removed) {
      _remove(slot);
    }
  }

  Future<void> _syncAudio() => _audio.update(
    _slots.map((s) => s.session),
    _selected?.session,
    suspended: _background || _modal || _closed,
  );

  Future<void> _addChannel(Channel channel) async {
    if (_adding ||
        _slots.length >= maxChannels ||
        !_allowed(channel) ||
        _slots.any((s) => s.channel.id == channel.id)) {
      return;
    }
    setState(() => _adding = true);
    final scope = DeviceTypeService.isTv
        ? PlayerSettingsScope.liveTv
        : PlayerSettingsScope.shared;
    final saved = await PlayerSettingsService().load(scope: scope);
    if (!mounted) return;
    if (!_allowed(channel)) {
      setState(() => _adding = false);
      return;
    }
    // Isolated settings. Shared Exo players use the short forward buffer,
    // and a tile does not keep a back buffer.
    final settings = PlayerSettings.fromJson(saved.toJson())
      ..audioPassthrough = false
      ..backgroundAudio = false
      ..backBufferSeconds = 0;
    final session = PlaybackSession(
      url: channel.url,
      isLive: true,
      settings: settings,
      previewMode: true,
      previewFallback: true,
      engineFactory: widget.engineFactory,
    )..muted = true;
    final slot = _Slot(channel, session);
    setState(() {
      _slots.add(slot);
      _selected = slot;
      _adding = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && slot.focus.context != null) slot.focus.requestFocus();
    });
    unawaited(
      session.start().then((_) {
        if (mounted && _slots.contains(slot)) _syncAudio();
      }),
    );
    await _syncAudio();
  }

  void _select(_Slot slot) {
    if (_selected == slot) return;
    setState(() => _selected = slot);
    _syncAudio().then((_) => slot.session.ensurePlaying());
  }

  void _remove(_Slot slot) {
    if (!_slots.contains(slot)) return;
    // Silence before retiring so no stale owner can keep playing.
    slot.session.muted = true;
    unawaited(slot.session.setVolume(0));
    setState(() {
      _slots.remove(slot);
      if (_expanded == slot) _expanded = null;
      if (_selected == slot) _selected = _slots.firstOrNull;
    });
    _syncAudio();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      slot.dispose();
      final target = _selected?.focus ?? _addFocus;
      if (target.context != null) target.requestFocus();
    });
  }

  Future<void> _chooseChannel() async {
    if (_adding || _slots.length >= maxChannels) return;
    final returnFocus = FocusManager.instance.primaryFocus;
    _modal = true;
    await _syncAudio();
    if (!mounted) return;
    final channel = await showDialog<Channel>(
      context: context,
      barrierColor: AppColors.background.withValues(alpha: 0.35),
      builder: (_) => _MultiViewChannelPicker(
        excluded: _slots.map((s) => s.channel.id).toSet(),
      ),
    );
    if (!mounted) return;
    _modal = false;
    if (channel != null) {
      await _addChannel(channel);
    } else if (returnFocus?.context != null) {
      returnFocus?.requestFocus();
    }
    await _syncAudio();
  }

  Future<void> _layout() async {
    final ui = context.read<UiSettings>();
    _modal = true;
    await _syncAudio();
    if (!mounted) return;
    final layout = await pickOption(
      context,
      title: 'Disposizione MultiView',
      options: MultiViewLayout.values,
      current: ui.multiViewLayout,
      label: (layout) => layout.label,
    );
    if (!mounted) return;
    if (layout != null) await ui.setMultiViewLayout(layout);
    _modal = false;
    await _syncAudio();
  }

  void _exit() {
    if (_expanded != null) {
      setState(() => _expanded = null);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _background = state != AppLifecycleState.resumed;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _closeAllStreams();
      return;
    }
    _syncAudio();
    for (final slot in _slots) {
      if (_background) {
        slot.session.engine?.pause();
      } else {
        slot.session.engine?.play();
      }
    }
  }

  StreamSubscription<void>? _screenOffSub;

  /// Closes every provider connection at once (app in background or TV
  /// switched off) and leaves MultiView: background apps draw no frames, so
  /// the streams are stopped directly instead of waiting for dispose.
  void _closeAllStreams() {
    if (_closed || !mounted) return;
    _closed = true;
    _watchdog?.cancel();
    for (final slot in _slots) {
      slot.session.engine?.pause();
      slot.session.stopStream();
    }
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      final nav = Navigator.of(context);
      if (route.isCurrent) {
        nav.pop();
      } else {
        nav.removeRoute(route);
      }
    }
  }

  Widget _action(
    String label,
    IconData icon,
    VoidCallback? action, {
    FocusNode? focus,
  }) {
    final button = IconButton(
      tooltip: label,
      onPressed: action,
      icon: Icon(icon),
    );
    if (action == null) return button;
    return TvFocusable(
      focusNode: focus,
      focusedScale: 1,
      onPressed: action,
      child: button,
    );
  }

  void _activate(_Slot slot) {
    _select(slot);
    if (slot.session.status == SessionStatus.failed) {
      slot.autoRetries = 0;
      _restart(slot);
      return;
    }
    setState(() => _expanded = _expanded == slot ? null : slot);
  }

  Widget _tile(_Slot slot) =>
      KeyedSubtree(key: slot.viewKey, child: _tileBody(slot));

  Widget _tileBody(_Slot slot) => TvFocusable(
    focusNode: slot.focus,
    focusedScale: 1,
    onFocusChange: (focused) {
      if (focused) _select(slot);
    },
    onPressed: () => _activate(slot),
    child: GestureDetector(
      onTap: () => _activate(slot),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: _selected == slot ? AppColors.primary : AppColors.border,
            width: 2,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: ListenableBuilder(
                listenable: slot.session,
                builder: (_, _) {
                  if (slot.session.status == SessionStatus.failed) {
                    return ColoredBox(
                      color: AppColors.surface,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _connectionLimit(slot)
                                ? 'Il provider IPTV non consente più connessioni simultanee.\nPremi OK per riprovare.'
                                : slot.autoRetries < 3
                                ? 'Canale interrotto, nuovo tentativo tra poco...'
                                : 'Canale non disponibile.\nPremi OK per riprovare.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    );
                  }
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoSurface(
                        session: slot.session,
                        settings: slot.session.settings,
                      ),
                      if (slot.session.status == SessionStatus.connecting ||
                          slot.session.status == SessionStatus.switching)
                        const Center(child: CircularProgressIndicator()),
                    ],
                  );
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: AppColors.overlayControl,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Icon(
                        _selected == slot
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          slot.channel.name,
                          maxLines: 2,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _grid(MultiViewLayout layout) {
    if (_slots.isEmpty) {
      return Center(
        child: _action(
          'Aggiungi canale',
          Icons.add_rounded,
          _chooseChannel,
          focus: _addFocus,
        ),
      );
    }
    if (_expanded != null) return _tile(_expanded ?? _slots.first);
    if (layout == MultiViewLayout.mainAndSide && _slots.length > 1) {
      return Row(
        children: [
          Expanded(flex: 2, child: _tile(_slots.first)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                for (final slot in _slots.skip(1)) ...[
                  Expanded(child: _tile(slot)),
                  if (slot != _slots.last) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      );
    }
    final columns = layout.columns(_slots.length);
    final rows = (_slots.length / columns).ceil();
    return Column(
      children: [
        for (var row = 0; row < rows; row++) ...[
          Expanded(
            child: Row(
              children: [
                for (
                  var col = 0;
                  col < columns && row * columns + col < _slots.length;
                  col++
                ) ...[
                  Expanded(child: _tile(_slots[row * columns + col])),
                  if (col < columns - 1 &&
                      row * columns + col + 1 < _slots.length)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          if (row < rows - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<UiSettings>().multiViewLayout;
    return PopScope(
      canPop: _expanded == null,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && _expanded != null) setState(() => _expanded = null);
      },
      child: Scaffold(
        body: SafeArea(
          child: FocusTraversalGroup(
            child: Column(
              children: [
                SizedBox(
                  height: 60,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _action('Indietro', Icons.arrow_back_rounded, _exit),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'MultiView · ${_slots.length}/$maxChannels',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (_slots.isNotEmpty)
                          _action(
                            'Aggiungi canale',
                            Icons.add_rounded,
                            _slots.length < maxChannels && !_adding
                                ? _chooseChannel
                                : null,
                            focus: _addFocus,
                          ),
                        _action(
                          'Disposizione',
                          Icons.dashboard_customize_outlined,
                          _layout,
                        ),
                        _action(
                          'Riprova canale',
                          Icons.refresh_rounded,
                          _selected == null
                              ? null
                              : () => _selected?.session.retry(),
                        ),
                        _action(
                          'Rimuovi canale',
                          Icons.delete_outline_rounded,
                          _selected == null
                              ? null
                              : () {
                                  final slot = _selected;
                                  if (slot != null) _remove(slot);
                                },
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _grid(layout),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _closed = true;
    _watchdog?.cancel();
    _screenOffSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _app.removeListener(_checkAllowed);
    _audio.dispose();
    for (final slot in _slots) {
      slot.dispose();
    }
    _addFocus.dispose();
    _app.setPlaybackActive(false);
    super.dispose();
  }
}

class _MultiViewChannelPicker extends StatefulWidget {
  const _MultiViewChannelPicker({required this.excluded});
  final Set<String> excluded;
  @override
  State<_MultiViewChannelPicker> createState() =>
      _MultiViewChannelPickerState();
}

/// Apple-style side panel, like the episode panel of the player: category
/// pills on top (instead of seasons) and a compact grid of channel logos.
/// Back from the grid returns to the categories, a second Back closes.
class _MultiViewChannelPickerState extends State<_MultiViewChannelPicker> {
  final _search = TextEditingController();
  final _firstChannel = FocusNode(debugLabel: 'multiview picker first');
  final _categoryNodes = <String, FocusNode>{};
  String _query = '';
  String? _category;
  bool _inGrid = true;

  FocusNode _categoryNode(String label) => _categoryNodes.putIfAbsent(
    label,
    () => FocusNode(debugLabel: 'multiview category $label'),
  );

  /// Standard category: "TV Sat" when present (same as the Diretta tab),
  /// otherwise the first category of the playlist.
  String? _defaultCategory(List<String> labels) {
    String n(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return labels.where((l) => n(l) == 'tvsat').firstOrNull ??
        labels.where((l) => n(l).contains('tvsat')).firstOrNull ??
        labels.firstOrNull;
  }

  void _back() {
    if (_inGrid && _category != null) {
      _categoryNodes[_category]?.requestFocus();
      setState(() => _inGrid = false);
      return;
    }
    Navigator.pop(context);
  }

  void _choose(String label) {
    setState(() => _category = label);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _firstChannel.context != null) {
        _firstChannel.requestFocus();
      }
    });
  }

  bool _allowed(AppProvider app, Channel c) =>
      c.isPlayable &&
      !widget.excluded.contains(c.id) &&
      (!app.kidsMode || app.isKidsContent(c));

  Widget _channelTile(Channel channel, int i) {
    final tv = DeviceTypeService.isTv;
    return TvFocusable(
      focusNode: i == 0 ? _firstChannel : null,
      autofocus: i == 0,
      focusedScale: 1.05,
      borderRadius: BorderRadius.circular(14),
      onFocusChange: (f) {
        if (f && !_inGrid) setState(() => _inGrid = true);
      },
      onPressed: () => Navigator.pop(context, channel),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.pop(context, channel),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.card.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
          ),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: PosterImage(
                    url: channel.logo,
                    fit: BoxFit.contain,
                    fallbackIcon: Icons.live_tv_rounded,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                channel.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: tv ? 12 : 11,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, bool active) {
    void choose() => _choose(label);
    return TvFocusable(
      focusNode: _categoryNode(label),
      onFocusChange: (f) {
        if (f && _inGrid) setState(() => _inGrid = false);
      },
      onPressed: choose,
      child: GestureDetector(
        onTap: choose,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.textPrimary : AppColors.card,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.background : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final groups = app.groupedCatalog(ContentType.live);
    final labels = [for (final g in groups) g.label];
    _category ??= _defaultCategory(labels);
    final q = _query.toLowerCase();
    final List<Channel> channels;
    if (q.isNotEmpty) {
      // Searching looks through every category.
      channels = [
        for (final entry in app.queryEntries(ContentType.live, q))
          if (_allowed(app, entry.primary)) entry.primary,
      ];
    } else {
      final group = groups.where((g) => g.label == _category).firstOrNull;
      channels = [
        for (final e in group?.entries ?? const [])
          if (_allowed(app, e.primary)) e.primary,
      ];
    }
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width < 620 ? width * .96 : 600.0;
    final columns = panelWidth < 420 ? 3 : 4;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: panelWidth,
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
                      const Text(
                        'MULTIVIEW',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Aggiungi canale',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TvTextField(
                        controller: _search,
                        onChanged: (query) => setState(() => _query = query),
                        decoration: const InputDecoration(
                          hintText: 'Cerca canale',
                          prefixIcon: Icon(Icons.search_rounded),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (labels.length > 1 && q.isEmpty)
                        SizedBox(
                          height: 48,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: labels.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) =>
                                _pill(labels[i], labels[i] == _category),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: channels.isEmpty
                            ? const Center(
                                child: Text('Nessun canale disponibile'),
                              )
                            : GridView.builder(
                                key: ValueKey('$_category|$q'),
                                padding: const EdgeInsets.only(bottom: 12),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 10,
                                      childAspectRatio: 0.95,
                                    ),
                                itemCount: channels.length,
                                itemBuilder: (_, i) =>
                                    _channelTile(channels[i], i),
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

  @override
  void dispose() {
    _search.dispose();
    _firstChannel.dispose();
    for (final n in _categoryNodes.values) {
      n.dispose();
    }
    super.dispose();
  }
}
