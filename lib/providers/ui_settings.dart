import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../models/content_type.dart';
import '../models/multiview_layout.dart';
import '../models/home_layout_preferences.dart';
import '../models/watch_completion_policy.dart';

enum AppSection { home, live, movies, series }

/// How movie/series catalogs show their posters. Inspired by popular apps:
/// poster wall (Netflix), dense grid (TiviMate), detailed list (Plex),
/// wide artwork (Apple TV) and a spotlight panel for the focused title
/// (Infuse).
enum CatalogViewMode { grid, compact, list, landscape, spotlight }

extension CatalogViewModeInfo on CatalogViewMode {
  String get label => switch (this) {
    CatalogViewMode.grid => 'Poster',
    CatalogViewMode.compact => 'Griglia densa',
    CatalogViewMode.list => 'Lista dettagliata',
    CatalogViewMode.landscape => 'Panoramica',
    CatalogViewMode.spotlight => 'In evidenza',
  };

  String get description => switch (this) {
    CatalogViewMode.grid => 'Locandine grandi, come Netflix',
    CatalogViewMode.compact => 'Tanti titoli insieme, come TiviMate',
    CatalogViewMode.list => 'Locandina, categoria e voto in righe',
    CatalogViewMode.landscape => 'Copertine larghe, come Apple TV',
    CatalogViewMode.spotlight =>
      'Scheda grande del titolo selezionato, come Infuse',
  };

  IconData get icon => switch (this) {
    CatalogViewMode.grid => Icons.grid_view_rounded,
    CatalogViewMode.compact => Icons.apps_rounded,
    CatalogViewMode.list => Icons.view_list_rounded,
    CatalogViewMode.landscape => Icons.view_carousel_rounded,
    CatalogViewMode.spotlight => Icons.featured_video_rounded,
  };

  CatalogViewMode get next =>
      CatalogViewMode.values[(index + 1) % CatalogViewMode.values.length];
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
  static const _viewModeMovieKey = 'ui_catalog_view_movie';
  static const _viewModeSeriesKey = 'ui_catalog_view_series';
  static const sectionOrderKey = 'ui_section_order';
  static const startSectionKey = 'ui_start_section';
  static const multiViewLayoutKey = 'ui_multiview_layout';
  static const _textScaleKey = 'ui_text_scale';
  static const _ratingsKey = 'ui_show_ratings';
  static const _qualityKey = 'ui_show_quality';
  static const _titlesKey = 'ui_show_titles';
  static const _focusGlowKey = 'ui_focus_glow';
  static const _favoriteHeartKey = 'ui_show_favorite_heart';
  static const _liveNumbersKey = 'ui_live_numbers';
  static const _livePreviewKey = 'ui_live_preview';

  static const homeKeys = {
    'ui_home_shape',
    'ui_home_recent_shape',
    'ui_home_density',
    'ui_home_recent_density',
    'ui_home_recommendation_limit',
    'ui_home_recent_limit',
    'ui_home_banner_size',
    homeBannerSourceKey,
    'ui_home_overview',
    'ui_home_titles',
    'ui_home_recent_titles',
    'ui_scale',
    homeRowOrderKey,
    homeHiddenRowsKey,
  };
  static const homeBannerSourceKey = 'ui_home_banner_source';
  static const homeRowOrderKey = 'ui_home_row_order';
  static const homeHiddenRowsKey = 'ui_home_hidden_rows';
  HomePosterShape homePosterShape = HomePosterShape.portrait;
  HomePosterShape homeRecentShape = HomePosterShape.portrait;
  HomeDensity homePosterDensity = HomeDensity.automatic;
  HomeDensity homeRecentDensity = HomeDensity.automatic;
  int homeRecommendationLimit = 10;
  int homeRecentLimit = 50;
  HomeBannerSize homeBannerSize = HomeBannerSize.compact;
  HomeBannerSource homeBannerSource = HomeBannerSource.automatic;
  bool homeOverview = true;
  bool homeTitles = false;
  bool homeRecentTitles = false;
  int uiScalePercent = 100;

  /// Saved Home row order (ids from [HomeRows]); empty means the default.
  List<String> homeRowOrder = const [];
  Set<String> homeHiddenRows = const {};
  int watchedPercent = WatchCompletionPolicy.defaultPercent;

  Future<void> setWatchedPercent(int value) async {
    watchedPercent = WatchCompletionPolicy.normalize(value);
    await _save(WatchCompletionPolicy.key, watchedPercent);
    notifyListeners();
  }

  Future<void> setHomePosterShape(HomePosterShape value) async {
    homePosterShape = value;
    await _save('ui_home_shape', value.name);
    notifyListeners();
  }

  Future<void> setHomeRecentShape(HomePosterShape value) async {
    homeRecentShape = value;
    await _save('ui_home_recent_shape', value.name);
    notifyListeners();
  }

  Future<void> setHomePosterDensity(HomeDensity value) async {
    homePosterDensity = value;
    await _save('ui_home_density', value.name);
    notifyListeners();
  }

  Future<void> setHomeRecentDensity(HomeDensity value) async {
    homeRecentDensity = value;
    await _save('ui_home_recent_density', value.name);
    notifyListeners();
  }

  Future<void> setHomeRecommendationLimit(int value) async {
    homeRecommendationLimit = HomeLayoutPolicy.recommendationLimit(value);
    await _save('ui_home_recommendation_limit', homeRecommendationLimit);
    notifyListeners();
  }

  Future<void> setHomeRecentLimit(int value) async {
    homeRecentLimit = HomeLayoutPolicy.itemLimit(value, fallback: 50);
    await _save('ui_home_recent_limit', homeRecentLimit);
    notifyListeners();
  }

  Future<void> setHomeBannerSize(HomeBannerSize value) async {
    homeBannerSize = value;
    await _save('ui_home_banner_size', value.name);
    notifyListeners();
  }

  Future<void> setHomeBannerSource(HomeBannerSource value) async {
    homeBannerSource = value;
    await _save(homeBannerSourceKey, value.name);
    notifyListeners();
  }

  Future<void> setHomeOverview(bool value) async {
    homeOverview = value;
    await _save('ui_home_overview', value);
    notifyListeners();
  }

  Future<void> setHomeTitles(bool value) async {
    homeTitles = value;
    await _save('ui_home_titles', value);
    notifyListeners();
  }

  Future<void> setHomeRecentTitles(bool value) async {
    homeRecentTitles = value;
    await _save('ui_home_recent_titles', value);
    notifyListeners();
  }

  Future<void> setUiScale(int value) async {
    uiScalePercent = HomeLayoutPolicy.uiScale(value);
    await _save('ui_scale', uiScalePercent);
    notifyListeners();
  }

  Future<void> setHomeRowOrder(List<String> value) async {
    homeRowOrder = List.unmodifiable(value);
    await _save(homeRowOrderKey, homeRowOrder);
    notifyListeners();
  }

  Future<void> setHomeRowVisible(String id, bool visible) async {
    final next = {...homeHiddenRows};
    visible ? next.remove(id) : next.add(id);
    homeHiddenRows = Set.unmodifiable(next);
    await _save(homeHiddenRowsKey, homeHiddenRows.toList());
    notifyListeners();
  }

  Future<void> resetHomeRows() async {
    homeRowOrder = const [];
    homeHiddenRows = const {};
    await _save(homeRowOrderKey, <String>[]);
    await _save(homeHiddenRowsKey, <String>[]);
    notifyListeners();
  }

  Future<void> resetHomeLayout() async {
    // Write defaults (not remove keys): defaults must replace remote settings.
    homePosterShape = HomePosterShape.portrait;
    homeRecentShape = HomePosterShape.portrait;
    homePosterDensity = homeRecentDensity = HomeDensity.automatic;
    homeRecommendationLimit = 10;
    homeRecentLimit = 50;
    homeBannerSize = HomeBannerSize.compact;
    homeBannerSource = HomeBannerSource.automatic;
    homeOverview = true;
    homeTitles = homeRecentTitles = false;
    uiScalePercent = 100;
    homeRowOrder = const [];
    homeHiddenRows = const {};
    for (final e in <String, Object>{
      'ui_home_shape': homePosterShape.name,
      'ui_home_recent_shape': homeRecentShape.name,
      'ui_home_density': homePosterDensity.name,
      'ui_home_recent_density': homeRecentDensity.name,
      'ui_home_recommendation_limit': homeRecommendationLimit,
      'ui_home_recent_limit': homeRecentLimit,
      'ui_home_banner_size': homeBannerSize.name,
      homeBannerSourceKey: homeBannerSource.name,
      'ui_home_overview': homeOverview,
      'ui_home_titles': homeTitles,
      'ui_home_recent_titles': homeRecentTitles,
      'ui_scale': uiScalePercent,
      homeRowOrderKey: <String>[],
      homeHiddenRowsKey: <String>[],
    }.entries) {
      await _save(e.key, e.value);
    }
    notifyListeners();
  }

  static const textScales = {
    'normale': 1.0,
    'grande': 1.12,
    'molto_grande': 1.25,
  };
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
    'viola': Color(0xFFA855F7),
    'blu': Color(0xFF3B82F6),
    'smeraldo': Color(0xFF10B981),
    'titanio': Color(0xFFC7C7CC),
  };

  static const gridSizes = {'piccola': 120.0, 'media': 140.0, 'grande': 170.0};

  Color _accent = accents['arancio']!;
  String _gridSize = 'grande';
  bool _showPosters = true;
  bool _animations = true;
  bool _compact = false;
  CatalogViewMode _viewMode = CatalogViewMode.grid;
  CatalogViewMode? _viewModeMovie;
  CatalogViewMode? _viewModeSeries;
  String _textScale = 'normale';
  bool _showRatings = true;
  bool _showQuality = true;
  bool _showTitles = true;
  bool _focusGlow = true;
  bool _favoriteHeart = true;
  bool _liveNumbers = false;
  bool _livePreview = true;
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

  /// Film and Serie TV may keep their own layout (picked from the catalog
  /// toolbar); otherwise they follow the common one.
  CatalogViewMode viewModeFor(ContentType type) => switch (type) {
    ContentType.movie => _viewModeMovie ?? _viewMode,
    ContentType.series || ContentType.anime => _viewModeSeries ?? _viewMode,
    ContentType.live => _viewMode,
  };
  bool get loaded => _loaded;
  String get textScale => _textScale;
  double get textScaleFactor => textScales[_textScale] ?? 1.0;
  bool get showRatings => _showRatings;
  bool get showQuality => _showQuality;
  bool get showTitles => _showTitles;
  bool get focusGlow => _focusGlow;

  /// Off: the heart shows only on titles already in the favorites.
  bool get favoriteHeart => _favoriteHeart;

  /// Diretta guide: channel numbers as typed with the remote digits.
  bool get liveNumbers => _liveNumbers;

  /// Diretta: the selected channel plays muted beside the guide.
  bool get livePreview => _livePreview;

  /// Changes whenever any saved look-and-feel preference changes: used to
  /// push the new values to the cloud at once.
  String get signature => [
    watchedPercent,
    accentName,
    _gridSize,
    _showPosters,
    _animations,
    _compact,
    _viewMode.name,
    _viewModeMovie?.name,
    _viewModeSeries?.name,
    _sectionOrder.map((e) => e.id).join(','),
    _startSection.id,
    _multiViewLayout.name,
    _textScale,
    _showRatings,
    _showQuality,
    _showTitles,
    _focusGlow,
    _favoriteHeart,
    _liveNumbers,
    _livePreview,
    homePosterShape.name,
    homeRecentShape.name,
    homePosterDensity.name,
    homeRecentDensity.name,
    homeRecommendationLimit,
    homeRecentLimit,
    homeBannerSize.name,
    homeBannerSource.name,
    homeOverview,
    homeTitles,
    homeRecentTitles,
    uiScalePercent,
    homeRowOrder.join(','),
    (homeHiddenRows.toList()..sort()).join(','),
  ].join('|');
  List<AppSection> get sectionOrder => List.unmodifiable(_sectionOrder);
  AppSection get startSection => _startSection;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final accentName = prefs.getString(_accentKey);
    if (accentName != null && accents.containsKey(accentName)) {
      _accent = accents[accentName]!;
    }
    _gridSize = prefs.getString(_gridSizeKey) ?? 'grande';
    _showPosters = prefs.getBool(_postersKey) ?? true;
    _animations = prefs.getBool(_animationsKey) ?? true;
    _compact = prefs.getBool(_compactKey) ?? false;
    _viewMode =
        CatalogViewMode.values.asNameMap()[prefs.getString(_viewModeKey)] ??
        CatalogViewMode.grid;
    _viewModeMovie = CatalogViewMode.values
        .asNameMap()[prefs.get(_viewModeMovieKey)];
    _viewModeSeries = CatalogViewMode.values
        .asNameMap()[prefs.get(_viewModeSeriesKey)];
    _sectionOrder = _parseSectionOrder(prefs.getStringList(sectionOrderKey));
    _startSection =
        _parseSection(prefs.getString(startSectionKey)) ?? AppSection.home;
    _multiViewLayout = MultiViewLayout.parse(
      prefs.getString(multiViewLayoutKey),
    );
    _textScale = prefs.getString(_textScaleKey) ?? 'normale';
    if (!textScales.containsKey(_textScale)) _textScale = 'normale';
    _showRatings = prefs.getBool(_ratingsKey) ?? true;
    _showQuality = prefs.getBool(_qualityKey) ?? true;
    _showTitles = prefs.getBool(_titlesKey) ?? true;
    _focusGlow = prefs.getBool(_focusGlowKey) ?? true;
    _favoriteHeart = prefs.getBool(_favoriteHeartKey) ?? true;
    _liveNumbers = prefs.getBool(_liveNumbersKey) ?? false;
    _livePreview = prefs.getBool(_livePreviewKey) ?? true;
    homePosterShape =
        HomePosterShape.values.asNameMap()[prefs.get('ui_home_shape')] ??
        HomePosterShape.portrait;
    homeRecentShape =
        HomePosterShape.values.asNameMap()[prefs.get('ui_home_recent_shape')] ??
        HomePosterShape.portrait;
    homePosterDensity =
        HomeDensity.values.asNameMap()[prefs.get('ui_home_density')] ??
        HomeDensity.automatic;
    homeRecentDensity =
        HomeDensity.values.asNameMap()[prefs.get('ui_home_recent_density')] ??
        HomeDensity.automatic;
    homeRecommendationLimit = HomeLayoutPolicy.recommendationLimit(
      prefs.get('ui_home_recommendation_limit'),
    );
    homeRecentLimit = HomeLayoutPolicy.itemLimit(
      prefs.get('ui_home_recent_limit'),
      fallback: 50,
    );
    homeBannerSize =
        HomeBannerSize.values.asNameMap()[prefs.get('ui_home_banner_size')] ??
        HomeBannerSize.compact;
    homeBannerSource = HomeBannerSourceInfo.parse(
      prefs.get(homeBannerSourceKey),
    );
    homeTitles = prefs.get('ui_home_titles') is bool
        ? prefs.get('ui_home_titles') as bool
        : false;
    homeRecentTitles = prefs.get('ui_home_recent_titles') is bool
        ? prefs.get('ui_home_recent_titles') as bool
        : false;
    homeOverview = prefs.get('ui_home_overview') is bool
        ? prefs.get('ui_home_overview') as bool
        : true;
    uiScalePercent = HomeLayoutPolicy.uiScale(prefs.get('ui_scale'));
    homeRowOrder = List.unmodifiable(_stringList(prefs.get(homeRowOrderKey)));
    homeHiddenRows = Set.unmodifiable(
      _stringList(prefs.get(homeHiddenRowsKey)),
    );
    watchedPercent = WatchCompletionPolicy.normalize(
      prefs.get(WatchCompletionPolicy.key),
    );
    _loaded = true;
    AppColors.primary = _accent;
    notifyListeners();
  }

  static List<String> _stringList(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];

  Future<void> _save(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is List<String>) await prefs.setStringList(key, value);
    if (value is String) await prefs.setString(key, value);
    if (value is bool) await prefs.setBool(key, value);
    if (value is int) await prefs.setInt(key, value);
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
        value.toSet().length != AppSection.values.length) {
      return;
    }
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

  /// Without [type] the layout becomes the common one for every catalog
  /// and the Film / Serie TV choices are cleared.
  Future<void> setCatalogViewMode(
    CatalogViewMode value, {
    ContentType? type,
  }) async {
    switch (type) {
      case ContentType.movie:
        if (_viewModeMovie == value) return;
        _viewModeMovie = value;
        await _save(_viewModeMovieKey, value.name);
      case ContentType.series || ContentType.anime:
        if (_viewModeSeries == value) return;
        _viewModeSeries = value;
        await _save(_viewModeSeriesKey, value.name);
      case ContentType.live || null:
        if (value == _viewMode &&
            _viewModeMovie == null &&
            _viewModeSeries == null) {
          return;
        }
        _viewMode = value;
        _viewModeMovie = _viewModeSeries = null;
        await _save(_viewModeKey, value.name);
        // A value (not a removed key) also clears the cloud copy.
        await _save(_viewModeMovieKey, 'common');
        await _save(_viewModeSeriesKey, 'common');
    }
    notifyListeners();
  }

  Future<void> setTextScale(String value) async {
    if (!textScales.containsKey(value)) return;
    _textScale = value;
    await _save(_textScaleKey, value);
    notifyListeners();
  }

  Future<void> setShowRatings(bool value) async {
    _showRatings = value;
    await _save(_ratingsKey, value);
    notifyListeners();
  }

  Future<void> setShowQuality(bool value) async {
    _showQuality = value;
    await _save(_qualityKey, value);
    notifyListeners();
  }

  Future<void> setShowTitles(bool value) async {
    _showTitles = value;
    await _save(_titlesKey, value);
    notifyListeners();
  }

  Future<void> setFavoriteHeart(bool value) async {
    _favoriteHeart = value;
    await _save(_favoriteHeartKey, value);
    notifyListeners();
  }

  Future<void> setLiveNumbers(bool value) async {
    _liveNumbers = value;
    await _save(_liveNumbersKey, value);
    notifyListeners();
  }

  Future<void> setLivePreview(bool value) async {
    _livePreview = value;
    await _save(_livePreviewKey, value);
    notifyListeners();
  }

  Future<void> setFocusGlow(bool value) async {
    _focusGlow = value;
    await _save(_focusGlowKey, value);
    notifyListeners();
  }

  /// Restores every look-and-feel preference to its default value.
  Future<void> resetAppearance() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _accentKey,
      _gridSizeKey,
      _postersKey,
      _animationsKey,
      _compactKey,
      _viewModeKey,
      _viewModeMovieKey,
      _viewModeSeriesKey,
      _textScaleKey,
      _ratingsKey,
      _qualityKey,
      _titlesKey,
      _focusGlowKey,
      _favoriteHeartKey,
      _liveNumbersKey,
      _livePreviewKey,
    ]) {
      await prefs.remove(key);
    }
    await resetHomeLayout();
    await load();
  }
}
