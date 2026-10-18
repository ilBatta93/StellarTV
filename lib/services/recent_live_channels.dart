import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Visti di recente" of the Diretta page.
///
/// Live channels are deliberately kept out of the watch history (Home rows,
/// progress and the encrypted cloud lane are for films and episodes only),
/// so the Diretta category had nothing to show. This device-local list keeps
/// only channel ids, newest first; it never leaves the device.
class RecentLiveChannels extends ChangeNotifier {
  RecentLiveChannels._();
  static final instance = RecentLiveChannels._();

  static const _key = 'recent_live_channels_v1';
  static const limit = 50;

  List<String> _ids = const [];
  Future<void>? _loading;

  /// Channel ids, most recently opened first.
  List<String> get ids => _ids;

  Future<void> load() => _loading ??= () async {
    final prefs = await SharedPreferences.getInstance();
    _ids = List.unmodifiable(prefs.getStringList(_key) ?? const <String>[]);
    notifyListeners();
  }();

  /// Moves [channelId] to the top of the list (duplicates removed).
  Future<void> record(String channelId) async {
    if (channelId.isEmpty) return;
    await load();
    _ids = List.unmodifiable(push(_ids, channelId));
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _ids);
  }

  Future<void> clear() async {
    _ids = const [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Pure list update, newest first and bounded to [max] entries.
  @visibleForTesting
  static List<String> push(List<String> ids, String id, {int max = limit}) =>
      [id, ...ids.where((e) => e != id)].take(max).toList();
}
