import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

class UiSettings extends ChangeNotifier {
  static const _accentKey = 'ui_accent';
  static const _gridSizeKey = 'ui_grid_size';
  static const _postersKey = 'ui_show_posters';
  static const _animationsKey = 'ui_animations';
  static const _compactKey = 'ui_compact';

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

  Color get accent => _accent;
  String get gridSize => _gridSize;
  double get gridMaxExtent => gridSizes[_gridSize] ?? 140;
  bool get showPosters => _showPosters;
  bool get animations => _animations;
  bool get compact => _compact;

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

  Future<void> setCompact(bool value) async {
    _compact = value;
    await _save(_compactKey, value);
    notifyListeners();
  }
}
