import 'package:flutter/material.dart';

import '../../models/player_settings.dart';
import '../../player/playback_session.dart';

class VideoSurface extends StatelessWidget {
  final PlaybackSession session;
  final PlayerSettings settings;

  const VideoSurface({super.key, required this.session, required this.settings});

  static Size _contain(double ratio, double w, double h) =>
      ratio > w / h ? Size(w, w / ratio) : Size(h * ratio, h);

  static Size _cover(double ratio, double w, double h) =>
      ratio > w / h ? Size(h * ratio, h) : Size(w, w / ratio);

  Size _targetSize(double w, double h) {
    final videoRatio = session.value.aspectRatio;
    return switch (session.fitMode) {
      VideoFitMode.fit => _contain(videoRatio, w, h),
      VideoFitMode.fill => Size(w, h),
      VideoFitMode.zoom => _cover(videoRatio, w, h),
      VideoFitMode.ratio16x9 => _contain(16 / 9, w, h),
      VideoFitMode.ratio4x3 => _contain(4 / 3, w, h),
      VideoFitMode.ratio21x9 => _contain(21 / 9, w, h),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final engine = session.presentedEngine;
        return ColoredBox(
          color: Colors.black,
          child: LayoutBuilder(builder: (context, box) {
            if (engine == null || box.maxHeight == 0) {
              return const SizedBox.expand();
            }
            session.updateBoxRatio(box.maxWidth / box.maxHeight);
            final size = _targetSize(box.maxWidth, box.maxHeight);
            // The key is the engine, so a recycled native surface is not
            // remounted. A hot swap keeps the previous picture until the
            // new one has drawn a frame.
            return Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(
                  child: OverflowBox(
                    minWidth: size.width,
                    maxWidth: size.width,
                    minHeight: size.height,
                    maxHeight: size.height,
                    child: KeyedSubtree(
                      key: ObjectKey(engine),
                      child: engine.buildView(size.width / size.height),
                    ),
                  ),
                ),
                if (session.value.caption.isNotEmpty)
                  Positioned(
                    left: 48,
                    right: 48,
                    bottom: 32,
                    child: SubtitleCaption(
                      text: session.value.caption,
                      settings: settings,
                    ),
                  ),
              ],
            );
          }),
        );
      },
    );
  }
}

class SubtitleCaption extends StatelessWidget {
  final String text;
  final PlayerSettings settings;

  const SubtitleCaption({super.key, required this.text, required this.settings});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: settings.subtitleColor.color,
      fontSize: settings.subtitleSize.fontSize,
      fontWeight: settings.subtitleBold ? FontWeight.w700 : FontWeight.w500,
      height: 1.3,
      shadows: settings.subtitleBackground
          ? null
          : const [Shadow(blurRadius: 4, color: Colors.black)],
    );
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: settings.subtitleBackground
              ? Colors.black.withValues(alpha: 0.6)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, textAlign: TextAlign.center, style: style),
      ),
    );
  }
}
