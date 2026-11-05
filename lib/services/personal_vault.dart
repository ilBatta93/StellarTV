import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data' show BytesBuilder;

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
    if (await read(account) != key) {
      throw StateError('Chiave non salvata sul dispositivo');
    }
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
    'ui_show_favorite_heart',
    'ui_live_numbers',
    'ui_live_preview',
    'ui_poster_corners',
    'ui_compact',
    'ui_catalog_view',
    'ui_catalog_view_movie',
    'ui_catalog_view_series',
    'ui_section_order',
    'ui_start_section',
    'ui_multiview_layout',
    'ui_home_shape',
    'ui_home_recent_shape',
    'ui_home_density',
    'ui_home_recent_density',
    'ui_home_recommendation_limit',
    'ui_home_recent_limit',
    'ui_home_banner_size',
    'ui_home_banner_source',
    'ui_home_overview',
    'ui_home_titles',
    'ui_home_recent_titles',
    'ui_home_row_order',
    'ui_home_hidden_rows',
    'ui_scale',
    'ui_watched_percent',
    'ui_auto_next_episode',
    'ui_player_languages',
    'kids_pin',
  };

  /// Layout choices kept apart for TVs and for phones/tablets: in the vault
  /// they travel as `key@tv` / `key@touch`. A plain key (older versions)
  /// is only the starting value of a class that has none of its own.
  static const layoutKeys = {
    'ui_text_scale',
    'ui_grid_size',
    'ui_show_titles',
    'ui_compact',
    'ui_catalog_view',
    'ui_catalog_view_movie',
    'ui_catalog_view_series',
    'ui_section_order',
    'ui_start_section',
    'ui_multiview_layout',
    'ui_home_shape',
    'ui_home_recent_shape',
    'ui_home_density',
    'ui_home_recent_density',
    'ui_home_recommendation_limit',
    'ui_home_recent_limit',
    'ui_home_banner_size',
    'ui_home_banner_source',
    'ui_home_overview',
    'ui_scale',
    'ui_home_titles',
    'ui_home_recent_titles',
    'ui_home_row_order',
    'ui_home_hidden_rows',
  };
  static const layoutClasses = {'tv', 'touch'};

  /// True for every key the vault may hold in its settings.
  static bool isVaultSettingKey(String key) {
    final at = key.indexOf('@');
    if (at < 0) return settingKeys.contains(key);
    return layoutKeys.contains(key.substring(0, at)) &&
        layoutClasses.contains(key.substring(at + 1));
  }

  /// Device settings (plain keys) as stored in the vault for [deviceClass].
  static Map<String, dynamic> settingsToVault(
    Map<String, dynamic> local,
    String deviceClass,
  ) => {
    for (final e in local.entries)
      layoutKeys.contains(e.key) ? '${e.key}@$deviceClass' : e.key: e.value,
  };

  /// Vault settings seen by a device of [deviceClass], with plain keys.
  static Map<String, dynamic> settingsFromVault(
    Map<String, dynamic> vault,
    String deviceClass,
  ) {
    final out = <String, dynamic>{};
    for (final e in vault.entries) {
      if (e.key.contains('@')) continue;
      out[e.key] = e.value;
    }
    for (final key in layoutKeys) {
      final own = '$key@$deviceClass';
      if (vault.containsKey(own)) out[key] = vault[own];
    }
    return out;
  }

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
    'vote',
    'poster_path',
    'backdrop_path',
  };

  /// TMDB image paths are relative file names, never addresses.
  static final _imagePath = RegExp(
    r'^/[A-Za-z0-9_-]{1,80}\.(jpg|jpeg|png|svg|webp)$',
  );
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
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(s)) {
      throw const FormatException('Chiave di recupero non valida');
    }
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
    if (v is Map) {
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
    }
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
        if (!e.key.endsWith('_path') ||
            e.value is String && _imagePath.hasMatch(e.value as String))
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
          if (isVaultSettingKey(e.key) && preference(e.value) != null)
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
    final controls = h.entries.where(
      (e) => object(e.value)['type'] == '__stellar_seen_v1',
    );
    final entries =
        h.entries
            .where((e) => object(e.value)['type'] != '__stellar_seen_v1')
            .toList()
          ..sort((x, y) => _at(y.value).compareTo(_at(x.value)));
    return Map.fromEntries([...controls, ...entries.take(cloudHistoryLimit)]);
  }

  static Map<String, dynamic> mergeHistory(dynamic a, dynamic b) {
    final out = object(a);
    for (final e in object(b).entries) {
      final old = out[e.key];
      final control =
          object(e.value)['type'] == '__stellar_seen_v1' &&
          object(old)['type'] == '__stellar_seen_v1';
      if (old == null ||
          _at(e.value) > _at(old) ||
          _at(e.value) == _at(old) &&
              (control
                  ? ((object(e.value)['pos'] as num?) ?? 3) <
                        ((object(old)['pos'] as num?) ?? 3)
                  : object(e.value)['deleted'] == true ||
                        object(old)['deleted'] != true)) {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  /// Favorite tombstones live in a reserved, encrypted profile lane, supported
  /// by the existing website sanitizer without exposing identifiers to cloud.
  static const favoriteLane = '__stellar_favorites_v1';

  /// Likes and dislikes of every profile, keyed `scope|itemKey`; vote 0 is
  /// the removal marker. Newest `watched` wins like any other lane.
  static const reactionsLane = '__stellar_reactions_v1';

  /// Profile names keyed by profile id (`name`, `watched`, `deleted`): the
  /// `user_profiles` table keeps only avatar, color and kids flag.
  static const profilesLane = '__stellar_profiles_v1';

  /// Reserved lanes that are not watch histories.
  static const reservedLanes = {favoriteLane, reactionsLane, profilesLane};

  /// Device reactions (`{scope: {itemKey: {vote, at, item}}}`) as lane rows.
  static Map<String, dynamic> reactionsToLane(dynamic all) => {
    for (final profile in object(all).entries)
      for (final e in object(profile.value).entries)
        if (object(e.value)['at'] is String)
          '${profile.key}|${e.key}': _entry({
            ...object(object(e.value)['item']),
            'vote': object(e.value)['vote'] ?? 0,
            'watched': object(e.value)['at'],
          }),
  };

  /// Lane rows back to the device reactions format.
  static Map<String, dynamic> laneToReactions(dynamic lane) {
    final out = <String, dynamic>{};
    for (final e in object(lane).entries) {
      final split = e.key.indexOf('|');
      final row = object(e.value);
      if (split <= 0 || row['watched'] is! String) continue;
      final item = Map<String, dynamic>.from(row)
        ..remove('vote')
        ..remove('watched');
      (out[e.key.substring(0, split)] ??= <String, dynamic>{})[e.key.substring(
        split + 1,
      )] = {
        'vote': (row['vote'] as num?)?.toInt() ?? 0,
        'at': row['watched'],
        'item': item,
      };
    }
    return out;
  }

  static Map<String, dynamic> merge(dynamic remote, dynamic local) {
    final a = clean(remote), b = clean(local);
    final profiles = object(a['profile_histories']);
    for (final e in object(b['profile_histories']).entries) {
      profiles[e.key] = mergeHistory(profiles[e.key], e.value);
    }
    for (final k in profiles.keys.toList()) {
      if (!reservedLanes.contains(k)) {
        profiles[k] = capHistory(profiles[k]);
      }
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

  /// Envelope written today. v2 gzips the JSON before encryption (a history
  /// compresses several times); v1 (plain JSON) is still read.
  static const envelopeVersion = 2;

  /// Upper bound for a decompressed snapshot, against compression bombs.
  static const maxPlainBytes = 32 * 1024 * 1024;

  static List<int> _aad(int version, String account, String id) =>
      utf8.encode('StellarTV:vault:$version:$account:$id');

  static Future<Map<String, dynamic>> encrypt(
    dynamic raw,
    String recovery,
    String account,
  ) async {
    final id = await keyId(recovery, account);
    final box = await _aes.encrypt(
      gzip.encode(utf8.encode(jsonEncode(clean(raw)))),
      secretKey: SecretKey(keyBytes(recovery)),
      aad: _aad(envelopeVersion, account, id),
    );
    return {
      'v': envelopeVersion,
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
    final version = e['v'];
    if (e.length != 5 ||
        (version != 1 && version != 2) ||
        e['alg'] != 'A256GCM' ||
        e['keyId'] != await keyId(recovery, account) ||
        e['nonce'] is! String ||
        e['ciphertext'] is! String) {
      throw const FormatException('Chiave non corretta per questo account');
    }
    final text = e['ciphertext'] as String;
    if (text.length > 12000000 ||
        !RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(text)) {
      throw const FormatException('Salvataggio non valido');
    }
    final nonce = base64Decode(e['nonce'] as String), data = base64Decode(text);
    if (nonce.length != 12 || data.length < 16) {
      throw const FormatException('Salvataggio non valido');
    }
    final plain = await _aes.decrypt(
      SecretBox(
        data.sublist(0, data.length - 16),
        nonce: nonce,
        mac: Mac(data.sublist(data.length - 16)),
      ),
      secretKey: SecretKey(keyBytes(recovery)),
      aad: _aad(version as int, account, e['keyId'] as String),
    );
    final compressed = version == 2;
    // Unzipping, decoding and cleaning a full history held the TV's UI
    // thread for about 0.4 s at each pull; the map comes back without a copy.
    return plain.length < 16 * 1024
        ? _openPlain(plain, compressed)
        : Isolate.run(() => _openPlain(plain, compressed));
  }

  /// Vaults with fewer history rows than this are merged on the calling
  /// isolate: a small one is done before an isolate would start.
  static const offUiRows = 300;

  /// History rows in [vault], every lane included, without copying it.
  static int historyRows(dynamic vault) {
    if (vault is! Map) return 0;
    final history = vault['history'];
    var rows = history is Map ? history.length : 0;
    final lanes = vault['profile_histories'];
    if (lanes is Map) {
      for (final lane in lanes.values) {
        if (lane is Map) rows += lane.length;
      }
    }
    return rows;
  }

  /// Runs [work] off the UI isolate when it covers [rows] history rows or
  /// more. [work] must be built where only its own inputs are in scope.
  static Future<R> offUiWhenLarge<R>(int rows, R Function() work) =>
      rows < offUiRows ? Future.sync(work) : Isolate.run(work);

  static Map<String, dynamic> _openPlain(List<int> plain, bool compressed) {
    final bytes = compressed ? _gunzip(plain) : plain;
    return clean(jsonDecode(utf8.decode(bytes)));
  }

  static List<int> _gunzip(List<int> data) {
    final out = BytesBuilder(copy: false);
    final input = gzip.decoder.startChunkedConversion(
      _LimitedSink(out, maxPlainBytes),
    );
    input.add(data);
    input.close();
    return out.takeBytes();
  }
}

/// Collects decompressed bytes and stops once [limit] is exceeded.
class _LimitedSink implements Sink<List<int>> {
  _LimitedSink(this._out, this._limit);
  final BytesBuilder _out;
  final int _limit;

  @override
  void add(List<int> chunk) {
    if (_out.length + chunk.length > _limit) {
      throw const FormatException('Salvataggio non valido');
    }
    _out.add(chunk);
  }

  @override
  void close() {}
}
