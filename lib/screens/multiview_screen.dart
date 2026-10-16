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
import '../providers/app_provider.dart';
import '../providers/ui_settings.dart';
import '../services/device_type_service.dart';
import '../services/player_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/tv_text_field.dart';
import '../widgets/settings_tiles.dart';
import '../widgets/player/video_surface.dart';

class _Slot {
  _Slot(this.channel, this.session);
  final Channel channel;
  final PlaybackSession session;
  final focus = FocusNode();
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
    WidgetsBinding.instance.addObserver(this);
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
        _slots.any((s) => s.channel.id == channel.id))
      return;
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
    // Isolated settings, no timeshift allocation for parallel tiles.
    final settings = PlayerSettings.fromJson(saved.toJson())
      ..audioPassthrough = false
      ..backgroundAudio = false;
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
    final channel = await showModalBottomSheet<Channel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
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
    _syncAudio();
    for (final slot in _slots) {
      if (_background) {
        slot.session.engine?.pause();
      } else {
        slot.session.engine?.play();
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

  Widget _tile(_Slot slot) => TvFocusable(
    focusNode: slot.focus,
    focusedScale: 1,
    onFocusChange: (focused) {
      if (focused) _select(slot);
    },
    onPressed: () {
      _select(slot);
      setState(() => _expanded = _expanded == slot ? null : slot);
    },
    child: GestureDetector(
      onTap: () {
        _select(slot);
        setState(() => _expanded = _expanded == slot ? null : slot);
      },
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
                            'Canale non disponibile\nIl provider o il dispositivo potrebbe limitare le riproduzioni simultanee.',
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
    if (_slots.isEmpty)
      return Center(
        child: _action(
          'Aggiungi canale',
          Icons.add_rounded,
          _chooseChannel,
          focus: _addFocus,
        ),
      );
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

class _MultiViewChannelPickerState extends State<_MultiViewChannelPicker> {
  final _search = TextEditingController();
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final channels = app.allChannels
        .where(
          (c) =>
              c.type == ContentType.live &&
              c.isPlayable &&
              !widget.excluded.contains(c.id) &&
              (!app.kidsMode || app.isKidsContent(c)) &&
              c.name.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: FocusTraversalGroup(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TvTextField(
                  controller: _search,
                  onChanged: (query) => setState(() => _query = query),
                  decoration: const InputDecoration(
                    hintText: 'Cerca canale',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              Expanded(
                child: channels.isEmpty
                    ? const Center(child: Text('Nessun canale disponibile'))
                    : ListView.builder(
                        itemCount: channels.length,
                        itemBuilder: (ctx, i) {
                          final channel = channels[i];
                          return TvFocusable(
                            autofocus: i == 0,
                            focusedScale: 1,
                            onPressed: () => Navigator.pop(context, channel),
                            child: ListTile(
                              title: Text(channel.name),
                              onTap: () => Navigator.pop(context, channel),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}
