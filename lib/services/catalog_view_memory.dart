import 'package:shared_preferences/shared_preferences.dart';

import '../models/content_type.dart';
import 'catalog_sort.dart';

/// Per-device memory of how the user left the catalog tabs: the sort order
/// of Diretta, Film and Serie TV and the last Diretta category. Category
/// labels come from the user's source, so they stay on the device and are
/// never part of the cloud settings.
class CatalogViewMemory {
  static const _sortPrefix = 'catalog_sort_';
  static const _liveCategoryKey = 'live_last_category';

  static Future<CatalogSort?> sort(ContentType type) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.get('$_sortPrefix${type.name}');
    return CatalogSort.values.asNameMap()[name];
  }

  static Future<void> saveSort(ContentType type, CatalogSort? sort) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_sortPrefix${type.name}',
      (sort ?? CatalogSort.provider).name,
    );
  }

  /// `saved` is false until the user picks a category once; `label` null
  /// means "Tutti".
  static Future<({bool saved, String? label})> liveCategory() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.get(_liveCategoryKey);
    if (value is! String) return (saved: false, label: null);
    return (saved: true, label: value.isEmpty ? null : value);
  }

  static Future<void> saveLiveCategory(String? label) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_liveCategoryKey, label ?? '');
  }
}
