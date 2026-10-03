import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';

class PlaylistService {
  static const _key = 'saved_playlists';

  Future<List<Playlist>> getPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Playlist.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addPlaylist(Playlist playlist) async {
    final playlists = await getPlaylists();
    playlists.add(playlist);
    await _save(playlists);
  }

  Future<void> removePlaylist(String id) async {
    final playlists = await getPlaylists();
    playlists.removeWhere((p) => p.id == id);
    await _save(playlists);
  }

  Future<void> _save(List<Playlist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(playlists.map((p) => p.toMap()).toList());
    await prefs.setString(_key, raw);
  }
}
