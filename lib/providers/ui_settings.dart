import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../models/multiview_layout.dart';

enum AppSection { home, live, movies, series }

/// How movie/series catalogs show their posters.
enum CatalogViewMode { grid, compact, list }

extension CatalogViewModeInfo on CatalogViewMode {
  String get label => switch (this) {
    CatalogViewMode.grid => 'Griglia',
    CatalogViewMode.compact => 'Griglia compatta',
    CatalogViewMode.list => 'Lista',
  };
}

extension AppSectionInfo on AppSection {
  String get id => name;
  String get label => switch (this) {
    AppSection.home => 'Home',
    AppSection.live => 'Diretta',
    AppSection.movies => 'Film',
    AppSection.series => 'Serie TV',
  };
}

class UiSettings extends ChangeNotifier {
  static const _accentKey = 'ui_accent';
  static const _gridSizeKey = 'ui_grid_size';
  static const _postersKey = 'ui_show_posters';
  static const _animationsKey = 'ui_animations';
  static const _compactKey = 'ui_compact';
  static const _viewModeKey = 'ui_catalog_view';
  static const sectionOrderKey = 'ui_section_order';
  static const startSectionKey = 'ui_start_section';
  static const multiViewLayoutKey = 'ui_multiview_layout';
  MultiViewLayout _multiViewLayout = MultiViewLayout.automatic;
  MultiViewLayout get multiViewLayout => _multiViewLayout;
  Future<void> setMultiViewLayout(MultiViewLayout layout) async {
    _multiViewLayout = layout;
    await _save(multiViewLayoutKey, layout.name);
    notifyListeners();
  }

  static const accents = {
    'arancio': Color(0xFFFF5A1F),
    'verde': Color(0xFF22C55E),
    'azzurro': Color(0xFF38BDF8),
    'rosso': Color(0xFFEF4444),
    'giallo': Color(0xFFFBBF24),
    'ciano': Color(0xFF2EC4B6),
    'rosa': Color(0xFFEC4899),
  };

  static const gridSizes = {'piccola': 120.0, 'media': 140.0, 'grande': 170.0};

  Color _accent = accents['arancio']!;
  String _gridSize = 'media';
  bool _showPosters = true;
  bool _animations = true;
  bool _compact = false;
  CatalogViewMode _viewMode = CatalogViewMode.grid;
  bool _loaded = false;
  List<AppSection> _sectionOrder = List.of(AppSection.values);
  AppSection _startSection = AppSection.home;

  Color get accent => _accent;
  String get gridSize => _gridSize;
  double get gridMaxExtent => gridSizes[_gridSize] ?? 140;
  bool get showPosters => _showPosters;
  bool get animations => _animations;
  bool get compact => _compact;
  CatalogViewMode get viewMode => _viewMode;
  bool get loaded => _loaded;
  List<AppSection> get sectionOrder => List.unmodifiable(_sectionOrder);
  AppSection get startSection => _startSection;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final accentName = prefs.getString(_accentKey);
    if (accentName != null && accents.containsKey(accentName)) {
      _accent = accents[accentName]!;
    }
    _gridSize = prefs.getString(_gridSizeKey) ?? 'media';
    _showPosters = prefs.getBool(_postersKey) ?? true;
    _animations = prefs.getBool(_animationsKey) ?? true;
    _compact = prefs.getBool(_compactKey) ?? false;
    _viewMode =
        CatalogViewMode.values.asNameMap()[prefs.getString(_viewModeKey)] ??
        CatalogViewMode.grid;
    _sectionOrder = _parseSectionOrder(prefs.getStringList(sectionOrderKey));
    _startSection =
        _parseSection(prefs.getString(startSectionKey)) ?? AppSection.home;
    _multiViewLayout = MultiViewLayout.parse(
      prefs.getString(multiViewLayoutKey),
    );
    _loaded = true;
    AppColors.primary = _accent;
    notifyListeners();
  }

  Future<void> _save(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is String) await prefs.setString(key, value);
    if (value is bool) await prefs.setBool(key, value);
  }

  Future<void> setAccent(String name) async {
    if (!accents.containsKey(name)) return;
    _accent = accents[name]!;
    AppColors.primary = _accent;
    await _save(_accentKey, name);
    notifyListeners();
  }

  String get accentName =>
      accents.entries.where((e) => e.value == _accent).firstOrNull?.key ??
      'arancio';

  Future<void> setGridSize(String size) async {
    if (!gridSizes.containsKey(size)) return;
    _gridSize = size;
    await _save(_gridSizeKey, size);
    notifyListeners();
  }

  Future<void> setShowPosters(bool value) async {
    _showPosters = value;
    await _save(_postersKey, value);
    notifyListeners();
  }

  Future<void> setAnimations(bool value) async {
    _animations = value;
    await _save(_animationsKey, value);
    notifyListeners();
  }

  Future<void> setSectionOrder(List<AppSection> value) async {
    if (value.length != AppSection.values.length ||
        value.toSet().length != AppSection.values.length)
      return;
    _sectionOrder = List.of(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(sectionOrderKey, value.map((e) => e.id).toList());
    notifyListeners();
  }

  Future<void> moveSection(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _sectionOrder.length ||
        newIndex < 0 ||
        newIndex >= _sectionOrder.length ||
        oldIndex == newIndex) {
      return;
    }
    final next = List<AppSection>.of(_sectionOrder);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    await setSectionOrder(next);
  }

  Future<void> setStartSection(AppSection value) async {
    _startSection = value;
    await _save(startSectionKey, value.id);
    notifyListeners();
  }

  Future<void> resetSectionLayout() async {
    _sectionOrder = List.of(AppSection.values);
    _startSection = AppSection.home;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(sectionOrderKey);
    await prefs.remove(startSectionKey);
    notifyListeners();
  }

  static AppSection? _parseSection(String? id) {
    for (final section in AppSection.values) {
      if (section.id == id) return section;
    }
    return null;
  }

  static List<AppSection> _parseSectionOrder(List<String>? ids) {
    if (ids == null) return List.of(AppSection.values);
    final parsed = ids.map(_parseSection).whereType<AppSection>().toList();
    if (parsed.length != AppSection.values.length ||
        parsed.toSet().length != AppSection.values.length) {
      return List.of(AppSection.values);
    }
    return parsed;
  }

  Future<void> setCompact(bool value) async {
    _compact = value;
    await _save(_compactKey, value);
    notifyListeners();
  }

  Future<void> setCatalogViewMode(CatalogViewMode value) async {
    if (value == _viewMode) return;
    _viewMode = value;
    await _save(_viewModeKey, value.name);
    notifyListeners();
  }
}
