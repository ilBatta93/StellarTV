/// Internal transport for an explicit ExoPlayer load control.
///
/// [VideoPlayerOptions] cannot grow, so Android reads this header from the
/// data source and removes it before any request leaves the device.
const exoLoadControlHeader = 'X-StellarTV-LoadControl';

class ExoLoadControlHeader {
  const ExoLoadControlHeader({
    required this.minBufferMs,
    required this.maxBufferMs,
    required this.bufferForPlaybackMs,
    required this.bufferForPlaybackAfterRebufferMs,
    required this.backBufferMs,
    required this.backBufferRequiresSeekable,
    required this.targetBufferBytes,
  });

  final int minBufferMs;
  final int maxBufferMs;
  final int bufferForPlaybackMs;
  final int bufferForPlaybackAfterRebufferMs;
  final int backBufferMs;
  final bool backBufferRequiresSeekable;
  final int targetBufferBytes;

  static ExoLoadControlHeader? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(',');
    if (parts.length != 7) return null;
    final values = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0) return null;
      values.add(value);
    }
    if (values[5] > 1) return null;
    return ExoLoadControlHeader(
      minBufferMs: values[0],
      maxBufferMs: values[1],
      bufferForPlaybackMs: values[2],
      bufferForPlaybackAfterRebufferMs: values[3],
      backBufferMs: values[4],
      backBufferRequiresSeekable: values[5] == 1,
      targetBufferBytes: values[6],
    );
  }
}

/// Removes [exoLoadControlHeader] without sending it to the stream.
String? takeExoLoadControlHeader(Map<String, String> headers) {
  String? raw;
  final drop = <String>[];
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == exoLoadControlHeader.toLowerCase()) {
      raw = entry.value;
      drop.add(entry.key);
    }
  }
  for (final key in drop) {
    headers.remove(key);
  }
  return raw;
}
