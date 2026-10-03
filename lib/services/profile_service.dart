import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';

/// Built-in avatar catalog: a fixed set of icons and colors the user can
/// pick from. Keys are stored in the `user_profiles` table columns.
class ProfileAvatars {
  static const entries = <String, int>{
    'rocket': 0xe9b1,
    'popcorn': 0xe7aa,
    'sports': 0xe1c5,
    'music': 0xe043,
    'star': 0xe062,
    'bolt': 0xe0e7,
    'ghost': 0xe2c3,
    'paw': 0xe52c,
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
      'avatar_color':
          ProfileAvatars.colorExists(avatarColor) ? avatarColor : 'arancio',
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
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
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
