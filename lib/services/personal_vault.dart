import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-only key storage. Never persist keys in preferences or cloud rows.
class VaultKeyStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  Future<String?> read(String account) =>
      _storage.read(key: 'personal_vault_$account');
  Future<void> save(String account, String key) async {
    PersonalVault.keyBytes(key);
    await _storage.write(key: 'personal_vault_$account', value: key);
    if (await read(account) != key)
      throw StateError('Chiave non salvata sul dispositivo');
  }

  Future<void> forget(String account) =>
      _storage.delete(key: 'personal_vault_$account');
}

class PersonalVault {
  static final _aes = AesGcm.with256bits();
  static final _source = RegExp(
    r'https?://|ftp://|file://|www\.|[?&](password|username|token)=',
    caseSensitive: false,
  );
  static const settingKeys = {
    'theme_mode',
    'ui_accent',
    'ui_text_scale',
    'ui_grid_size',
    'ui_glow',
    'ui_animations',
    'ui_focus_glow',
    'ui_show_titles',
    'ui_show_posters',
    'ui_show_ratings',
    'ui_show_quality',
    'ui_compact',
    'ui_catalog_view',
    'ui_section_order',
    'ui_start_section',
    'ui_multiview_layout',
    'show_adult_content',
    'ui_home_shape',
    'ui_home_recent_shape',
    'ui_home_density',
    'ui_home_recent_density',
    'ui_home_recommendation_limit',
    'ui_home_recent_limit',
    'ui_home_banner_size',
    'ui_home_overview',
    'ui_home_titles',
    'ui_home_recent_titles',
    'ui_scale',
    'ui_watched_percent',
  };
  static const _fields = {
    'id',
    'type',
    'title',
    'name',
    'group',
    'pos',
    'dur',
    'watched',
    'deleted',
    'skey',
    'sname',
    'media_type',
    'overview',
    'release_date',
    'first_air_date',
    'vote_average',
    'genre_ids',
    'original_title',
    'original_name',
  };
  static Map<String, dynamic> object(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static String generateKey() {
    final r = Random.secure();
    return 'STV1-${List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
  }

  static List<int> keyBytes(String key) {
    final s = key
        .trim()
        .replaceFirst(RegExp(r'^STV1-', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(s))
      throw const FormatException('Chiave di recupero non valida');
    return [
      for (var i = 0; i < 64; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ];
  }

  static Future<String> keyId(String key, String account) async {
    final hash = await Sha256().hash([
      ...utf8.encode('StellarTV-vault-key:$account:'),
      ...keyBytes(key),
    ]);
    return hash.bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  }

  static dynamic preference(dynamic v) {
    if (v is bool || v is num && v.isFinite) return v;
    if (v is String) {
      if (RegExp(r'^[a-zA-Z0-9_-]{1,40}$').hasMatch(v)) return v;
      try {
        final d = jsonDecode(v);
        if (d is Map || d is List) return jsonEncode(preference(d));
      } catch (_) {}
      return null;
    }
    if (v is List) return v.map(preference).where((v) => v != null).toList();
    if (v is Map)
      return {
        for (final e in object(v).entries)
          if (RegExp(r'^[a-zA-Z0-9_-]{1,40}$').hasMatch(e.key) &&
              !RegExp(
                r'url|server|user|pass|token|secret|source|stream|channel|title|name|path|key|credential',
                caseSensitive: false,
              ).hasMatch(e.key) &&
              preference(e.value) != null)
            e.key: preference(e.value),
      };
    return null;
  }

  static Map<String, dynamic> _entry(dynamic raw) => {
    for (final e in object(raw).entries)
      if (_fields.contains(e.key) &&
          (e.value is bool ||
              e.value is num && (e.value as num).isFinite ||
              e.value is String && !_source.hasMatch(e.value as String) ||
              e.key == 'genre_ids' &&
                  e.value is List &&
                  (e.value as List).every((v) => v is num)))
        e.key: e.value,
  };
  static Map<String, dynamic> _history(dynamic raw) => {
    for (final e in object(raw).entries)
      if (!_source.hasMatch(e.key)) e.key: _entry(e.value),
  };
  static Map<String, dynamic> clean(dynamic raw) {
    final p = object(raw);
    return {
      'v': 4,
      'history': _history(p['history']),
      'profile_histories': {
        for (final e in object(p['profile_histories']).entries)
          if (!_source.hasMatch(e.key)) e.key: _history(e.value),
      },
      'favorite_ids':
          (p['favorite_ids'] is List ? p['favorite_ids'] as List : const [])
              .whereType<String>()
              .where((v) => !_source.hasMatch(v))
              .toList(),
      'tmdb_favorites':
          (p['tmdb_favorites'] is List ? p['tmdb_favorites'] as List : const [])
              .map(_entry)
              .toList(),
      'settings': {
        for (final e in object(p['settings']).entries)
          if (settingKeys.contains(e.key) && preference(e.value) != null)
            e.key: preference(e.value),
      },
    };
  }

  static int _at(dynamic v) =>
      DateTime.tryParse(object(v)['watched']?.toString() ?? '')
          ?.microsecondsSinceEpoch ??
      0;
  /// The cloud copy keeps only the newest titles so every save stays small;
  /// the full history always remains on the device.
  static const cloudHistoryLimit = 500;
  static Map<String, dynamic> capHistory(dynamic raw) {
    final h = object(raw);
    if (h.length <= cloudHistoryLimit) return h;
    final entries = h.entries.toList()
      ..sort((x, y) => _at(y.value).compareTo(_at(x.value)));
    return Map.fromEntries(entries.take(cloudHistoryLimit));
  }

  static Map<String, dynamic> mergeHistory(dynamic a, dynamic b) {
    final out = object(a);
    for (final e in object(b).entries) {
      final old = out[e.key];
      if (old == null ||
          _at(e.value) > _at(old) ||
          _at(e.value) == _at(old) &&
              (object(e.value)['deleted'] == true ||
                  object(old)['deleted'] != true))
        out[e.key] = e.value;
    }
    return out;
  }

  /// Favorite tombstones live in a reserved, encrypted profile lane, supported
  /// by the existing website sanitizer without exposing identifiers to cloud.
  static const favoriteLane = '__stellar_favorites_v1';
  static Map<String, dynamic> merge(dynamic remote, dynamic local) {
    final a = clean(remote), b = clean(local);
    final profiles = object(a['profile_histories']);
    for (final e in object(b['profile_histories']).entries) {
      profiles[e.key] = mergeHistory(profiles[e.key], e.value);
    }
    for (final k in profiles.keys.toList()) {
      if (k != favoriteLane) profiles[k] = capHistory(profiles[k]);
    }
    final ids = <String>{
      ...(a['favorite_ids'] as List).cast<String>(),
      ...(b['favorite_ids'] as List).cast<String>(),
    };
    final items = <String, dynamic>{
      for (final v in a['tmdb_favorites'] as List)
        '${v['media_type']}_${v['id']}': v,
    };
    for (final v in b['tmdb_favorites'] as List) {
      items['${v['media_type']}_${v['id']}'] = v;
    }
    for (final e in object(profiles[favoriteLane]).entries) {
      final event = object(e.value);
      if (e.key.startsWith('c:')) {
        final id = e.key.substring(2);
        if (event['deleted'] == true) {
          ids.remove(id);
        } else {
          ids.add(id);
        }
      }
      if (e.key.startsWith('t:')) {
        final id = e.key.substring(2);
        if (event['deleted'] == true) {
          items.remove(id);
        } else {
          items[id] = _entry(event);
        }
      }
    }
    return {
      'v': 4,
      'history': capHistory(mergeHistory(a['history'], b['history'])),
      'profile_histories': profiles,
      'favorite_ids': ids.toList(),
      'tmdb_favorites': items.values.toList(),
      'settings': {...object(a['settings']), ...object(b['settings'])},
    };
  }

  static String canonical(dynamic value) {
    if (value is Map) {
      final keys = object(value).keys.toList()..sort();
      return '{${keys.map((k) => '${jsonEncode(k)}:${canonical(value[k])}').join(',')}}';
    }
    if (value is List) return '[${value.map(canonical).join(',')}]';
    return jsonEncode(value);
  }

  static Future<Map<String, dynamic>> encrypt(
    dynamic raw,
    String recovery,
    String account,
  ) async {
    final id = await keyId(recovery, account);
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(clean(raw))),
      secretKey: SecretKey(keyBytes(recovery)),
      aad: utf8.encode('StellarTV:vault:1:$account:$id'),
    );
    return {
      'v': 1,
      'alg': 'A256GCM',
      'keyId': id,
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode([...box.cipherText, ...box.mac.bytes]),
    };
  }

  static Future<Map<String, dynamic>> decrypt(
    dynamic raw,
    String recovery,
    String account,
  ) async {
    final e = object(raw);
    if (e.length != 5 ||
        e['v'] != 1 ||
        e['alg'] != 'A256GCM' ||
        e['keyId'] != await keyId(recovery, account) ||
        e['nonce'] is! String ||
        e['ciphertext'] is! String)
      throw const FormatException('Chiave non corretta per questo account');
    final text = e['ciphertext'] as String;
    if (text.length > 12000000 ||
        !RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(text))
      throw const FormatException('Salvataggio non valido');
    final nonce = base64Decode(e['nonce'] as String), data = base64Decode(text);
    if (nonce.length != 12 || data.length < 16)
      throw const FormatException('Salvataggio non valido');
    final plain = await _aes.decrypt(
      SecretBox(
        data.sublist(0, data.length - 16),
        nonce: nonce,
        mac: Mac(data.sublist(data.length - 16)),
      ),
      secretKey: SecretKey(keyBytes(recovery)),
      aad: utf8.encode('StellarTV:vault:1:$account:${e['keyId']}'),
    );
    return clean(jsonDecode(utf8.decode(plain)));
  }
}
