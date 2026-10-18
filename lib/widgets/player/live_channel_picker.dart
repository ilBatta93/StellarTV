import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/channel.dart';
import '../../theme/app_theme.dart';
import '../poster_card.dart';
import '../tv_focusable.dart';

/// One category of the in-player channel list.
class LiveChannelGroup {
  const LiveChannelGroup(this.label, this.channels);
  final String label;
  final List<Channel> channels;
}

/// Category to open first: the one of the playing channel when it is
/// listed there, otherwise the first category that contains it.
@visibleForTesting
int initialLiveGroup(List<LiveChannelGroup> groups, Channel current) {
  final own = groups.indexWhere(
    (g) =>
        g.label == current.group && g.channels.any((c) => c.id == current.id),
  );
  if (own >= 0) return own;
  final any = groups.indexWhere(
    (g) => g.channels.any((c) => c.id == current.id),
  );
  return any >= 0 ? any : 0;
}

/// Transparent channel list opened with Left during live TV: categories on
/// the left, channels with the programme now on air on the right. The video
/// keeps playing behind it; OK picks a channel and one Back closes it.
class LiveChannelPicker extends StatefulWidget {
  const LiveChannelPicker({
    super.key,
    required this.current,
    required this.groups,
    required this.nowOnAir,
  });

  final Channel current;
  final List<LiveChannelGroup> groups;
  final String? Function(Channel channel) nowOnAir;

  @override
  State<LiveChannelPicker> createState() => _LiveChannelPickerState();
}

class _LiveChannelPickerState extends State<LiveChannelPicker> {
  static const _channelExtent = 66.0;
  static const _groupExtent = 52.0;

  late int _group = initialLiveGroup(widget.groups, widget.current);
  // One node per category: swapping a node onto the focused row dropped focus.
  late final List<FocusNode> _groupNodes = [
    for (var i = 0; i < widget.groups.length; i++)
      FocusNode(debugLabel: 'live picker category $i'),
  ];
  final _channelNode = FocusNode(debugLabel: 'live picker channel');
  late final ScrollController _groupScroll = ScrollController(
    initialScrollOffset: (_group - 3).clamp(0, 1 << 20) * _groupExtent,
  );
  late ScrollController _channelScroll = _channelScrollFor(_group);
  bool _initialChannels = true;

  List<Channel> get _channels =>
      widget.groups.isEmpty ? const [] : widget.groups[_group].channels;

  int _anchorIndex(int group) {
    if (!_initialChannels || widget.groups.isEmpty) return 0;
    final i = widget.groups[group].channels.indexWhere(
      (c) => c.id == widget.current.id,
    );
    return i < 0 ? 0 : i;
  }

  ScrollController _channelScrollFor(int group) => ScrollController(
    initialScrollOffset:
        (_anchorIndex(group) - 3).clamp(0, 1 << 30) * _channelExtent,
  );

  @override
  void dispose() {
    for (final n in _groupNodes) {
      n.dispose();
    }
    _channelNode.dispose();
    _groupScroll.dispose();
    _channelScroll.dispose();
    super.dispose();
  }

  void _showGroup(int index) {
    if (index == _group) return;
    final old = _channelScroll;
    setState(() {
      _initialChannels = false;
      _group = index;
      _channelScroll = _channelScrollFor(index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  KeyEventResult _columnKey(KeyEvent event, {required bool inChannels}) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (inChannels && key == LogicalKeyboardKey.arrowLeft) {
      if (_groupNodes.isNotEmpty) _groupNodes[_group].requestFocus();
      return KeyEventResult.handled;
    }
    if (!inChannels && key == LogicalKeyboardKey.arrowRight) {
      if (_channels.isNotEmpty) _channelNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _groupRow(int index) {
    final group = widget.groups[index];
    final selected = index == _group;
    return TvFocusable(
      focusNode: _groupNodes[index],
      focusedScale: 1.0,
      onFocusChange: (f) {
        if (f) _showGroup(index);
      },
      onPressed: () {
        _showGroup(index);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _channels.isNotEmpty) _channelNode.requestFocus();
        });
      },
      child: Container(
        height: _groupExtent - 4,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.18)
              : AppColors.clear,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                group.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.onOverlaySecondary,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${group.channels.length}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelRow(Channel channel, int index, int anchor) {
    final playing = channel.id == widget.current.id;
    final now = widget.nowOnAir(channel);
    return TvFocusable(
      focusNode: index == anchor ? _channelNode : null,
      autofocus: index == anchor && _initialChannels,
      focusedScale: 1.0,
      onPressed: () => Navigator.pop(context, channel),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.pop(context, channel),
        child: Container(
          height: _channelExtent - 4,
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: playing
                ? AppColors.primary.withValues(alpha: 0.16)
                : AppColors.clear,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                height: 40,
                child: PosterImage(
                  url: channel.logo,
                  fit: BoxFit.contain,
                  fallbackIcon: Icons.live_tv_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (now != null && now.isNotEmpty)
                      Text(
                        now,
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
              if (playing)
                Icon(
                  Icons.graphic_eq_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.62).clamp(320.0, 980.0);
    final channels = _channels;
    final anchor = _anchorIndex(_group);
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: width,
        height: size.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.background.withValues(alpha: 0.88),
                AppColors.background.withValues(alpha: 0.72),
                AppColors.background.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.8, 1.0],
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(28, 22, width * 0.06, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Elenco canali',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.current.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.primary, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Focus(
                              canRequestFocus: false,
                              skipTraversal: true,
                              onKeyEvent: (_, e) =>
                                  _columnKey(e, inChannels: false),
                              child: FocusTraversalGroup(
                                child: ListView.builder(
                                  controller: _groupScroll,
                                  itemExtent: _groupExtent,
                                  itemCount: widget.groups.length,
                                  itemBuilder: (_, i) => _groupRow(i),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 7,
                            child: Focus(
                              canRequestFocus: false,
                              skipTraversal: true,
                              onKeyEvent: (_, e) =>
                                  _columnKey(e, inChannels: true),
                              child: FocusTraversalGroup(
                                child: channels.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'Nessun canale',
                                          style: TextStyle(
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        key: ValueKey(_group),
                                        controller: _channelScroll,
                                        itemExtent: _channelExtent,
                                        itemCount: channels.length,
                                        itemBuilder: (_, i) =>
                                            _channelRow(channels[i], i, anchor),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
