import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'title_metadata_store.dart';

/// Large cached JSON kept in its own file instead of SharedPreferences.
/// The preferences arrive whole, and are decoded on the UI isolate, at every
/// getInstance and reload: 2 MB of TMDB lists there froze the TV's UI thread
/// for 300-600 ms each time at startup.
class DeviceJsonFile {
  const DeviceJsonFile(this.name, {this.legacyKey});

  final String name;

  /// Preferences key that held this value before. Read once, moved to the
  /// file and removed, so the preferences shrink back.
  final String? legacyKey;

  Future<String> _path() async =>
      '${(await getApplicationSupportDirectory()).path}/json_cache/$name.json';

  /// Decoded value, read and parsed off the UI isolate. Null when missing
  /// or unreadable.
  Future<Object?> read() async {
    if (TitleMetadataStore.disabled) return null;
    final path = await _path();
    final value = await Isolate.run(() => _decodeFile(path));
    if (value != null || legacyKey == null) return value;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(legacyKey!);
    if (raw == null) return null;
    await Isolate.run(() => _writeFile(path, raw));
    await prefs.remove(legacyKey!);
    return Isolate.run(() => _decodeText(raw));
  }

  /// Writes [value] off the UI isolate. Encoding stays here: sending the
  /// maps to the isolate would copy them, which costs about as much.
  Future<void> write(Object? value) async {
    if (TitleMetadataStore.disabled) return;
    final path = await _path();
    final text = jsonEncode(value);
    await Isolate.run(() => _writeFile(path, text));
  }
}

Object? _decodeText(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

Object? _decodeFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return _decodeText(file.readAsStringSync());
  } catch (_) {
    return null;
  }
}

void _writeFile(String path, String text) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  // Written beside and renamed, so a crash never leaves half a file.
  final tmp = File('$path.tmp')..writeAsStringSync(text, flush: true);
  tmp.renameSync(file.path);
}
