import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../models/poster_badges.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';

/// Everything drawn over a catalog poster, each in its fixed place (see
/// [PosterSlot]). Corners stack their badges with the same gap and inset,
/// and with [caption] the bottom badges sit right above the title, so
/// nothing ever covers anything else.
class PosterOverlay extends StatelessWidget {
  const PosterOverlay({
    super.key,
    this.topLeft = const [],
    this.topRight = const [],
    this.bottomLeft = const [],
    this.bottomRight = const [],
    this.caption,
    this.edge,
    this.edgeHeight = 0,
  });

  final List<Widget> topLeft;
  final List<Widget> topRight;
  final List<Widget> bottomLeft;
  final List<Widget> bottomRight;

  /// Title written on the poster, over a dark fade.
  final Widget? caption;

  /// Progress bar along the bottom edge.
  final Widget? edge;
  final double edgeHeight;

  static double get inset => DeviceTypeService.isTv ? 8 : 6;
  static const gap = 4.0;

  Widget? _bottomRow() {
    if (bottomLeft.isEmpty && bottomRight.isEmpty) return null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: bottomLeft,
          ),
        ),
        for (final w in bottomRight)
          Padding(
            padding: const EdgeInsets.only(left: gap),
            child: w,
          ),
      ],
    );
  }

  Widget _column(List<Widget> children, CrossAxisAlignment align) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: align,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: gap),
        children[i],
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final inset = PosterOverlay.inset;
    final bottom = _bottomRow();
    final caption = this.caption;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (caption != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xD9000000)],
                  stops: [0, 0.55],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  inset,
                  inset * 4,
                  inset,
                  inset + edgeHeight,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (bottom != null) ...[bottom, const SizedBox(height: 6)],
                    caption,
                  ],
                ),
              ),
            ),
          )
        else if (bottom != null)
          Positioned(
            left: inset,
            right: inset,
            bottom: inset + edgeHeight,
            child: bottom,
          ),
        if (topLeft.isNotEmpty)
          Positioned(
            top: inset,
            left: inset,
            child: _column(topLeft, CrossAxisAlignment.start),
          ),
        if (topRight.isNotEmpty)
          Positioned(
            top: inset,
            right: inset,
            child: _column(topRight, CrossAxisAlignment.end),
          ),
        if (edge != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: edgeHeight,
            child: edge!,
          ),
      ],
    );
  }
}

/// «Nuovo» on titles the source added in the last days.
class PosterNewBadge extends StatelessWidget {
  const PosterNewBadge(this.channel, {super.key});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    if (!isRecentlyAdded(channel.addedAt, DateTime.now())) {
      return const SizedBox.shrink();
    }
    final tv = DeviceTypeService.isTv;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'NUOVO',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: tv ? 11 : 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
