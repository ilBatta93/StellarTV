/// Highest picture the player asks the stream for. Only adaptive streams
/// (HLS, DASH) offer more than one size: a single-picture stream plays as is.
enum MaxVideoResolution {
  unlimited('Nessun limite', null),
  native('Nativa dello schermo', null),
  p2160('2160p (4K)', 2160),
  p1080('1080p (Full HD)', 1080),
  p720('720p (HD)', 720),
  p480('480p (SD)', 480);

  final String label;

  /// Short side of the cap; null for the two modes without a fixed size.
  final int? lines;
  const MaxVideoResolution(this.label, this.lines);
}

/// The screen in physical pixels. [width] and [height] are the panel's own
/// size; the current output can be smaller (Android TV often draws at 1080p
/// on a 4K panel).
class DisplayResolution {
  final int width;
  final int height;
  final int? currentWidth;
  final int? currentHeight;

  const DisplayResolution({
    required this.width,
    required this.height,
    this.currentWidth,
    this.currentHeight,
  });

  int get long => width > height ? width : height;
  int get short => width > height ? height : width;

  /// True when the system draws at a size other than the panel's own.
  bool get outputDiffers =>
      currentWidth != null &&
      currentHeight != null &&
      (currentWidth! * currentHeight!) != width * height;

  String get label => describeResolution(width, height);
}

/// Largest picture allowed, as long side × short side, so a portrait screen
/// or a vertical video compares the same way as a landscape one.
class VideoSizeCap {
  final int long;
  final int short;
  const VideoSizeCap(this.long, this.short);

  /// Coded sizes overshoot a little (1920×1088): a 1.5% slack keeps them in.
  bool fits(int width, int height) {
    final l = width > height ? width : height;
    final s = width > height ? height : width;
    return l <= long + long ~/ 64 && s <= short + short ~/ 64;
  }

  @override
  bool operator ==(Object other) =>
      other is VideoSizeCap && other.long == long && other.short == short;

  @override
  int get hashCode => Object.hash(long, short);

  @override
  String toString() => '${long}x$short';
}

/// Null means no cap: no limit chosen, or the screen is still unknown.
VideoSizeCap? videoSizeCap(
  MaxVideoResolution choice,
  DisplayResolution? display,
) {
  if (choice == MaxVideoResolution.unlimited) return null;
  if (choice == MaxVideoResolution.native) {
    if (display == null || display.short <= 0) return null;
    return VideoSizeCap(display.long, display.short);
  }
  final lines = choice.lines!;
  return VideoSizeCap((lines * 16 / 9).round(), lines);
}

/// Index of the largest variant inside [cap]; the smallest one when none
/// fits, so a stream that only offers big pictures still plays.
int? pickCappedVariant(List<(int, int)> sizes, VideoSizeCap cap) {
  int? best;
  int? smallest;
  for (var i = 0; i < sizes.length; i++) {
    final (w, h) = sizes[i];
    if (w <= 0 || h <= 0) continue;
    final area = w * h;
    if (smallest == null || area < sizes[smallest].$1 * sizes[smallest].$2) {
      smallest = i;
    }
    if (cap.fits(w, h) &&
        (best == null || area > sizes[best].$1 * sizes[best].$2)) {
      best = i;
    }
  }
  return best ?? smallest;
}

/// First variant mpv opens, by bitrate, before the track list shows the
/// real sizes. Typical rates for each size; above 1080p mpv keeps "max".
int? hlsBitrateFor(VideoSizeCap? cap) {
  if (cap == null) return null;
  if (cap.short <= 480) return 1500000;
  if (cap.short <= 720) return 3000000;
  if (cap.short <= 1080) return 6000000;
  return null;
}

String describeResolution(int width, int height) {
  final short = width > height ? height : width;
  final name = switch (short) {
    >= 4320 => '8K',
    >= 2160 => '4K',
    >= 1440 => 'QHD',
    >= 1080 => 'Full HD',
    >= 720 => 'HD',
    _ => 'SD',
  };
  return '$width × $height ($name)';
}
