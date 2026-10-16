import 'dart:convert';

import 'sync_hooks.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _themeKey = 'theme_mode';
  static const _authMethodKey = 'auth_method';
  static const _xtreamServerKey = 'xtream_server';
  static const _xtreamUserKey = 'xtream_username';
  static const _xtreamPassKey = 'xtream_password';

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

  Future<Map<String, String>?> getXtreamCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString(_xtreamServerKey);
    final user = prefs.getString(_xtreamUserKey);
    final pass = prefs.getString(_xtreamPassKey);
    if (server == null || user == null || pass == null) return null;
    return {'server': server, 'username': user, 'password': pass};
  }

  Future<void> setXtreamCredentials({
    required String server,
    required String username,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_xtreamServerKey, server);
    await prefs.setString(_xtreamUserKey, username);
    await prefs.setString(_xtreamPassKey, password);
    onCredentialsChanged?.call();
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authMethodKey);
    await prefs.remove(_xtreamServerKey);
    await prefs.remove(_xtreamUserKey);
    await prefs.remove(_xtreamPassKey);
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
      return decoded.map((k, v) =>
          MapEntry(k, (v as List?)?.cast<String>() ?? <String>[]));
    } catch (_) {
      return {};
    }
  }

  Future<void> setHiddenCategories(Map<String, List<String>> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hiddenCategoriesKey, jsonEncode(map));
    SyncHooks.settingsChanged();
  }
}
