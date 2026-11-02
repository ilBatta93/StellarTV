import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import 'personal_vault.dart';
import 'sync_hooks.dart';
import 'sync_service.dart';

/// Built-in avatar catalog: a fixed set of icons and colors the user can
/// pick from. Keys are stored in the `user_profiles` table columns.
class ProfileAvatars {
  static const entries = <String, IconData>{
    'rocket': Icons.rocket_launch_outlined,
    'popcorn': Icons.local_movies_outlined,
    'sports': Icons.sports_soccer_outlined,
    'music': Icons.music_note_outlined,
    'star': Icons.star_border_rounded,
    'bolt': Icons.bolt_outlined,
    'ghost': Icons.face_outlined,
    'paw': Icons.pets_outlined,
  };

  static const colors = <String, int>{
    'arancio': 0xFFFF5A1F,
    'verde': 0xFF34C77B,
    'azzurro': 0xFF38BDF8,
    'rosso': 0xFFEF4444,
    'giallo': 0xFFFACC15,
    'ciano': 0xFF22D3EE,
    'rosa': 0xFFF472B6,
  };

  static bool exists(String key) => entries.containsKey(key);
  static bool colorExists(String key) => colors.containsKey(key);

  static IconData iconOf(String key) => entries[key] ?? entries['rocket']!;
}

/// CRUD for user profiles against the `user_profiles` table. Access is keyed
/// on the device's sync code (the app has no accounts, like the cloud sync).
class ProfileService {
  ProfileService(this._client);

  final SupabaseClient _client;
  static const _localProfileKey = 'selected_profile_id';

  Future<List<UserProfile>> listProfiles(String syncCode) async {
    final rows = await _client
        .from('user_profiles')
        .select()
        .eq('sync_code', syncCode)
        .order('created_at', ascending: true);
    return rows.map(UserProfile.fromJson).toList();
  }

  Future<UserProfile> createProfile({
    required String syncCode,
    required String name,
    required String avatarKey,
    required String avatarColor,
    bool isKids = false,
  }) async {
    final rows = await _client.from('user_profiles').insert({
      'sync_code': syncCode,
      'name': name,
      'avatar_key': ProfileAvatars.exists(avatarKey) ? avatarKey : 'rocket',
      'avatar_color': ProfileAvatars.colorExists(avatarColor)
          ? avatarColor
          : 'arancio',
      'is_kids': isKids,
    }).select();
    return UserProfile.fromJson(rows.first);
  }

  Future<void> updateProfile({
    required String id,
    required String syncCode,
    String? name,
    String? avatarKey,
    String? avatarColor,
    bool? isKids,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (isKids != null) updates['is_kids'] = isKids;
    if (avatarKey != null && ProfileAvatars.exists(avatarKey)) {
      updates['avatar_key'] = avatarKey;
    }
    if (avatarColor != null && ProfileAvatars.colorExists(avatarColor)) {
      updates['avatar_color'] = avatarColor;
    }
    if (updates.isEmpty) return;
    await _client
        .from('user_profiles')
        .update(updates)
        .eq('id', id)
        .eq('sync_code', syncCode);
  }

  Future<void> deleteProfile({
    required String id,
    required String syncCode,
  }) async {
    await _client
        .from('user_profiles')
        .delete()
        .eq('id', id)
        .eq('sync_code', syncCode);
  }

  // ----- encrypted names -----

  /// Name events of every profile (vault lane format) kept on this device.
  Future<Map<String, dynamic>> nameEvents() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      return PersonalVault.object(
        jsonDecode(prefs.getString(SyncService.profileNamesKey) ?? '{}'),
      );
    } catch (_) {
      return {};
    }
  }

  /// Records a name (or a removal) for the encrypted vault and asks for a
  /// cloud save. [at] orders concurrent edits across devices.
  Future<void> recordName(
    String id, {
    String? name,
    bool deleted = false,
    DateTime? at,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final events = await nameEvents();
    events[id] = {
      'id': id,
      if (!deleted && name != null) 'name': name,
      if (deleted) 'deleted': true,
      'watched': (at ?? DateTime.now()).toUtc().toIso8601String(),
    };
    await prefs.setString(SyncService.profileNamesKey, jsonEncode(events));
    SyncHooks.settingsChanged();
  }

  /// Replaces the plain name in the table with the empty placeholder, once
  /// the encrypted copy is confirmed in the cloud.
  Future<void> clearTableName({
    required String id,
    required String syncCode,
  }) async {
    await _client
        .from('user_profiles')
        .update({'name': ''})
        .eq('id', id)
        .eq('sync_code', syncCode);
  }

  Future<String?> getSelectedProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_localProfileKey);
  }

  Future<void> setSelectedProfileId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_localProfileKey);
    } else {
      await prefs.setString(_localProfileKey, id);
    }
  }
}
