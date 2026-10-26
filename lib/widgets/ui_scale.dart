import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/ui_settings.dart';

/// Layout at a logical viewport, then scale layout and hit testing together.
/// Only presentation shells opt in: native player surfaces are never wrapped.
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) {
    final scale =
        context.select<UiSettings?, int>((ui) => ui?.uiScalePercent ?? 100) /
        100;
    if (scale == 1) return Builder(builder: builder);
    return LayoutBuilder(
      builder: (context, bounds) {
        if (!bounds.hasBoundedWidth || !bounds.hasBoundedHeight)
          return Builder(builder: builder);
        final mq = MediaQuery.of(context);
        final size = Size(bounds.maxWidth / scale, bounds.maxHeight / scale);
        EdgeInsets adjust(EdgeInsets edge) => edge / scale;
        return FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: MediaQuery(
              data: mq.copyWith(
                size: size,
                devicePixelRatio: mq.devicePixelRatio * scale,
                padding: adjust(mq.padding),
                viewPadding: adjust(mq.viewPadding),
                viewInsets: adjust(mq.viewInsets),
              ),
              child: Builder(builder: builder),
            ),
          ),
        );
      },
    );
  }
}
