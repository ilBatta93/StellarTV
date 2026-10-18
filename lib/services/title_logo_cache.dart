import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TitleLogoEntry {
  const TitleLogoEntry(this.url);
  final String? url;
}

/// Versioned because older metadata allowed untagged foreign-language logos.
class TitleLogoCache {
  static const storageKey = 'title_logo_cache_it_en_v1';
  static const limit = 240;
  static Future<void> _writes = Future<void>.value();
  static Map<String, dynamic> _decode(String? raw) {
    try {
      return raw == null
          ? {}
          : (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  static bool validUrl(Object? url) =>
      url == null ||
      (url is String &&
          RegExp(
            r'^https://image\.tmdb\.org/t/p/w500/[a-zA-Z0-9_.-]+\.(png|jpg|webp)$',
          ).hasMatch(url));

  static Future<TitleLogoEntry?> read(String key, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = _decode(prefs.getString(storageKey))[key];
      if (value is! Map) return null;
      final expiry = value['expires'];
      if (expiry is! int ||
          expiry <= (now ?? DateTime.now()).millisecondsSinceEpoch ||
          !value.containsKey('url') ||
          !validUrl(value['url']))
        return null;
      return TitleLogoEntry(value['url'] as String?);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, String? url, {DateTime? now}) {
    if (!validUrl(url)) return Future<void>.value();
    final at = now ?? DateTime.now();
    return _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final entries = _decode(prefs.getString(storageKey));
        entries.removeWhere(
          (_, value) =>
              value is! Map ||
              value['expires'] is! int ||
              value['expires'] <= at.millisecondsSinceEpoch,
        );
        entries.remove(key);
        entries[key] = {
          'url': url,
          'expires': at
              .add(
                url == null
                    ? const Duration(hours: 6)
                    : const Duration(days: 30),
              )
              .millisecondsSinceEpoch,
        };
        while (entries.length > limit) {
          entries.remove(entries.keys.first);
        }
        await prefs.setString(storageKey, jsonEncode(entries));
      } catch (_) {
        /* Disk cache failure must never prevent display. */
      }
    });
  }
}
