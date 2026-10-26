import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the live channels whose video the TV's hardware decoder could
/// not draw (audio with a black picture: MPEG-2, interlaced 1080i/576i...).
///
/// The first time a channel shows a black picture mpv switches to FFmpeg
/// software decoding; from then on the channel opens directly in software
/// mode, so the black screen is never seen again on that device.
class DecoderMemory {
  DecoderMemory._();

  static const _prefsKey = 'stellar_software_decode_channels_v2';
  static const _maxEntries = 400;

  static final List<String> _keys = [];
  static Future<void>? _loading;
  static var _ready = false;

  static final _xtreamLive = RegExp(
    r'^https?://([^/]+)/(?:live/)?[^/]+/[^/]+/(\d+)(?:\.(?:m3u8|ts))?$',
  );

  /// Same channel whatever the address form (`.ts`, `.m3u8`, with or
  /// without `/live/`) and without the account credentials.
  static String keyFor(String url) {
    final trimmed = url.trim();
    final m = _xtreamLive.firstMatch(trimmed);
    if (m != null) return '${m[1]}#${m[2]}';
    final q = trimmed.indexOf('?');
    return q < 0 ? trimmed : trimmed.substring(0, q);
  }

  static Future<void> ensureLoaded() {
    if (_ready) return Future<void>.value();
    return _loading ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        _keys
          ..clear()
          ..addAll(prefs.getStringList(_prefsKey) ?? const []);
      } catch (_) {}
      _ready = true;
    }();
  }

  static bool needsSoftware(String url) => _keys.contains(keyFor(url));

  static Future<void> remember(String url) async {
    final key = keyFor(url);
    if (key.isEmpty) return;
    _keys
      ..remove(key)
      ..add(key);
    while (_keys.length > _maxEntries) {
      _keys.removeAt(0);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, List.of(_keys));
    } catch (_) {}
  }

  /// Settings "reset": lets the hardware decoder try every channel again.
  static Future<void> clear() async {
    _keys.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}
