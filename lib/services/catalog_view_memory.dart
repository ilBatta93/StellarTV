import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog_start_category.dart';
import '../models/content_type.dart';
import 'catalog_sort.dart';

/// Per-device memory of how the user left the catalog tabs: the sort order
/// of Diretta, Film and Serie TV, the last category of each and the
/// category each one opens on. Category
/// labels come from the user's source, so they stay on the device and are
/// never part of the cloud settings.
class CatalogViewMemory {
  static const _sortPrefix = 'catalog_sort_';
  static const _liveCategoryKey = 'live_last_category';
  static const _lastCategoryPrefix = 'catalog_last_category_';
  static const _startCategoryPrefix = 'catalog_start_category_';

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

  /// Film and Serie TV: last category picked; null means the default view.
  static Future<String?> lastCategory(ContentType type) async {
    if (type == ContentType.live) return (await liveCategory()).label;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.get('$_lastCategoryPrefix${type.name}');
    return value is String && value.isNotEmpty ? value : null;
  }

  static Future<void> saveLastCategory(ContentType type, String? label) async {
    if (type == ContentType.live) return saveLiveCategory(label);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_lastCategoryPrefix${type.name}', label ?? '');
  }

  /// Category each tab opens on (Impostazioni → Categorie).
  static Future<CatalogStartCategory> startCategory(ContentType type) async {
    final prefs = await SharedPreferences.getInstance();
    return CatalogStartCategory.parse(
      prefs.get('$_startCategoryPrefix${type.name}'),
      type,
    );
  }

  static Future<void> saveStartCategory(
    ContentType type,
    CatalogStartCategory value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_startCategoryPrefix${type.name}', value.encode());
  }
}
