import 'dart:convert';
import 'dart:io' show Platform;

import 'sync_hooks.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/custom_category.dart';

class SettingsService {
  static const _themeKey = 'theme_mode';
  static const _authMethodKey = 'auth_method';
  static const _xtreamServerKey = 'xtream_server';
  static const _xtreamUserKey = 'xtream_username';
  static const _xtreamPassKey = 'xtream_password';

  /// Kind of access ('link', 'portal'); absent for server, user and password.
  /// Not secret, so it stays in preferences even when the Keychain is used.
  static const _sourceKindKey = 'source_kind';

  /// Called after every credential change so the account sync can upload
  /// the new state. Set at app startup; kept as a loose hook to avoid a
  /// circular dependency between settings and sync.
  static void Function()? onCredentialsChanged;

  Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeKey) ?? 'dark';
  }

  Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode);
    SyncHooks.settingsChanged();
  }

  Future<String?> getAuthMethod() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_authMethodKey);
  }

  Future<void> setAuthMethod(String method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authMethodKey, method);
    onCredentialsChanged?.call();
  }

  /// iOS keeps the access data in the device-only Keychain: preferences
  /// reach iCloud and computer backups there. Android excludes every file
  /// from backup already, so it keeps preferences.
  static bool useKeychain = Platform.isIOS;
  static CredentialKeychain keychain = const SecureCredentialKeychain();

  // Set only once the Keychain holds the access data. A Keychain copy
  // without it survived an uninstall and is stale.
  static const _keychainMarkerKey = 'xtream_in_keychain';
  static const _credentialKeys = [
    _xtreamServerKey,
    _xtreamUserKey,
    _xtreamPassKey,
  ];

  Future<Map<String, String>?> getXtreamCredentials() async {
    final stored = await _getStoredCredentials();
    if (stored == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final kind = prefs.getString(_sourceKindKey);
    return kind == null ? stored : {...stored, 'kind': kind};
  }

  Future<Map<String, String>?> _getStoredCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (useKeychain) {
      try {
        if (prefs.getBool(_keychainMarkerKey) == true) {
          final stored = await _readKeychain();
          if (stored != null) return stored;
        } else {
          await _clearKeychain();
        }
        final legacy = _readPrefs(prefs);
        if (legacy != null && await _writeKeychain(legacy)) {
          await prefs.setBool(_keychainMarkerKey, true);
          for (final key in _credentialKeys) {
            await prefs.remove(key);
          }
        }
        return legacy;
      } catch (_) {
        // Keychain unavailable: the preference copy keeps the app usable.
      }
    }
    return _readPrefs(prefs);
  }

  Map<String, String>? _readPrefs(SharedPreferences prefs) {
    final server = prefs.getString(_xtreamServerKey);
    final user = prefs.getString(_xtreamUserKey);
    final pass = prefs.getString(_xtreamPassKey);
    if (server == null || user == null || pass == null) return null;
    return {'server': server, 'username': user, 'password': pass};
  }

  Future<Map<String, String>?> _readKeychain() async {
    final server = await keychain.read(_xtreamServerKey);
    final user = await keychain.read(_xtreamUserKey);
    final pass = await keychain.read(_xtreamPassKey);
    if (server == null || user == null || pass == null) return null;
    return {'server': server, 'username': user, 'password': pass};
  }

  /// True only when every value reads back unchanged.
  Future<bool> _writeKeychain(Map<String, String> credentials) async {
    try {
      await keychain.write(_xtreamServerKey, credentials['server']!);
      await keychain.write(_xtreamUserKey, credentials['username']!);
      await keychain.write(_xtreamPassKey, credentials['password']!);
      final back = await _readKeychain();
      return back != null &&
          back['server'] == credentials['server'] &&
          back['username'] == credentials['username'] &&
          back['password'] == credentials['password'];
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearKeychain() async {
    for (final key in _credentialKeys) {
      await keychain.delete(key);
    }
  }

  Future<void> setXtreamCredentials({
    required String server,
    required String username,
    required String password,
    String? kind,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (kind == null || kind == 'account') {
      await prefs.remove(_sourceKindKey);
    } else {
      await prefs.setString(_sourceKindKey, kind);
    }
    final saved =
        useKeychain &&
        await _writeKeychain({
          'server': server,
          'username': username,
          'password': password,
        });
    if (saved) {
      await prefs.setBool(_keychainMarkerKey, true);
      for (final key in _credentialKeys) {
        await prefs.remove(key);
      }
    } else {
      await prefs.setString(_xtreamServerKey, server);
      await prefs.setString(_xtreamUserKey, username);
      await prefs.setString(_xtreamPassKey, password);
      if (useKeychain) await prefs.remove(_keychainMarkerKey);
    }
    onCredentialsChanged?.call();
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authMethodKey);
    await prefs.remove(_sourceKindKey);
    for (final key in _credentialKeys) {
      await prefs.remove(key);
    }
    await prefs.remove(_keychainMarkerKey);
    if (useKeychain) {
      try {
        await _clearKeychain();
      } catch (_) {}
    }
  }

  static const _hiddenCategoriesKey = 'hidden_categories';

  /// Category labels the user chose to hide from catalogs, keyed per
  /// content type ("live", "movie", "series", "anime").
  Future<Map<String, List<String>>> getHiddenCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_hiddenCategoriesKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      return decoded.map(
        (k, v) => MapEntry(k, (v as List?)?.cast<String>() ?? <String>[]),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> setHiddenCategories(Map<String, List<String>> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hiddenCategoriesKey, jsonEncode(map));
    SyncHooks.settingsChanged();
  }

  static const _categoryOrderKey = 'category_order_v1';
  static const _customCategoriesKey = 'custom_categories_v1';

  /// User category order per content type; device-local like hidden
  /// categories because labels come from the provider.
  Future<Map<String, List<String>>> getCategoryOrder() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final decoded = jsonDecode(prefs.getString(_categoryOrderKey) ?? '{}');
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is List)
            e.key.toString(): (e.value as List).whereType<String>().toList(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> setCategoryOrder(Map<String, List<String>> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_categoryOrderKey, jsonEncode(map));
  }

  Future<List<CustomCategory>> getCustomCategories() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final decoded = jsonDecode(prefs.getString(_customCategoriesKey) ?? '[]');
      if (decoded is! List) return [];
      return decoded
          .map(CustomCategory.tryParse)
          .whereType<CustomCategory>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> setCustomCategories(List<CustomCategory> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _customCategoriesKey,
      jsonEncode([for (final c in list) c.toJson()]),
    );
  }
}

/// Device-only secret storage for the access data.
abstract class CredentialKeychain {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureCredentialKeychain implements CredentialKeychain {
  const SecureCredentialKeychain();

  // "This device only": never copied to backups or to a new phone.
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
