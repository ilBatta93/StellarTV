import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/apple_page_scaffold.dart';

import 'package:provider/provider.dart';

import '../widgets/catalog_section_status.dart';

import '../providers/app_provider.dart';
import '../providers/ui_settings.dart';
import '../models/content_type.dart';
import '../models/home_layout_preferences.dart';
import '../models/watch_completion_policy.dart';
import '../services/playlist_refresh_service.dart';
import '../theme/app_theme.dart';
import '../widgets/catalog_start_tiles.dart';
import '../widgets/settings_tiles.dart';
import '../widgets/phone_tap.dart';
import '../widgets/tv_focusable.dart';
import '../services/device_type_service.dart';
import 'account_screen.dart';
import 'xtream_edit_screen.dart';
import '../providers/sync_provider.dart';
import '../services/settings_logout.dart';
import 'history_settings_screen.dart';
import 'hidden_categories_screen.dart';
import 'dns_settings_screen.dart';
import 'vpn_settings_screen.dart';
import '../services/vpn_service.dart';
import 'epg_settings_screen.dart';
import 'player_settings_screen.dart';
import 'profile_picker_screen.dart';
import 'sync_settings_screen.dart';
import 'expiry_reminder_screen.dart';
import 'xtream_account_screen.dart';
import 'section_layout_screen.dart';
import 'home_rows_screen.dart';
import 'poster_badges_screen.dart';
import '../models/poster_badges.dart';
import '../models/banner_trailer.dart';
import '../models/poster_focus.dart';
import '../models/settings_preview_zone.dart';
import 'settings_preview.dart';
import 'downloads_screen.dart';
import 'multiview_settings_screen.dart';
import 'live_diagnostics_screen.dart';
import 'vod_diagnostics_screen.dart';
import 'performance_diagnostics_screen.dart';

import '../services/app_update_service.dart';
import 'category_manager_screen.dart';
import '../models/source_access.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int? _refreshMinutes;
  int _loadedRefreshMinutes = 0;
  DateTime? _lastRefresh;
  String? _lastRefreshLabel;
  // TV: the settings pane, entered from the categories on its first row.
  final FocusNode _detailNode = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// Right enters the pane on its first setting (not the geometrically
  /// nearest one); Left stays on the categories instead of jumping to Back.
  KeyEventResult _onCategoryKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.handled;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    final first = _detailNode.traversalDescendants
        .where((node) => node.canRequestFocus && !node.skipTraversal)
        .firstOrNull;
    first?.requestFocus();
    return KeyEventResult.handled;
  }

  late final List<FocusNode> _categoryNodes = [
    for (var i = 0; i < _categories.length; i++) FocusNode(),
  ];

  @override
  void initState() {
    super.initState();
    _loadRefreshState();
  }

  Future<void> _loadRefreshState() async {
    final service = PlaylistRefreshService(() async {});
    final minutes = await service.loadIntervalMinutes();
    final last = await service.lastRun();
    if (!mounted) return;
    setState(() {
      _loadedRefreshMinutes = minutes;
      _lastRefresh = last;
      _lastRefreshLabel = _formatLastRefresh(last);
    });
  }

  String _formatLastRefresh(DateTime? last) {
    if (last == null) return 'mai';
    final diff = DateTime.now().difference(last);
    if (diff.inMinutes < 1) return 'adesso';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min fa';
    if (diff.inHours < 24) return '${diff.inHours} h fa';
    return '${diff.inDays} g fa';
  }

  /// "Aspetto e Home": the live preview and the values it opened with.
  SettingsPreviewController? _preview;

  @override
  void dispose() {
    _preview?.dispose();
    _detailNode.dispose();
    for (final node in _categoryNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _buildUiCustomization(BuildContext context) {
    final ui = context.watch<UiSettings>();
    _preview ??= SettingsPreviewController(ui);
    Future<void> pick<T>(
      String title,
      List<T> options,
      T current,
      String Function(T) label,
      Future<void> Function(UiSettings, T) apply, {
      String? Function(T)? detail,
    }) => pickWithPreview<T>(
      context,
      controller: _preview,
      title: title,
      options: options,
      current: current,
      label: label,
      apply: apply,
      detail: detail,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Aspetto',
          description:
              'Colori, testo ed effetti. Tutto viene salvato nel cloud.',
          children: [
            PreviewTarget(
              zone: PreviewZone.homePage,
              child: _AccentPalette(
                current: ui.accentName,
                label: _accentLabel,
                onSelected: ui.setAccent,
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.homePage,
              child: SettingsValueTile(
                icon: Icons.text_fields_rounded,
                title: 'Dimensione testo',
                subtitle: 'Utile sulle TV lontane dal divano',
                value: _textScaleLabel(ui.textScale),
                onTap: () => pick<String>(
                  'Dimensione testo',
                  UiSettings.textScales.keys.toList(),
                  ui.textScale,
                  _textScaleLabel,
                  (s, v) => s.setTextScale(v),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.focus,
              child: SettingsSwitchTile(
                icon: Icons.auto_awesome_outlined,
                title: 'Bagliore di selezione',
                subtitle: 'Alone colorato attorno all\'elemento selezionato col telecomando',
                value: ui.focusGlow,
                onChanged: ui.setFocusGlow,
              ),
            ),
            if (DeviceTypeService.isTv) ...[
              PreviewTarget(
                zone: PreviewZone.focus,
                child: SettingsValueTile(
                  icon: Icons.zoom_in_rounded,
                  title: 'Ingrandimento della selezione',
                  subtitle: 'Quanto cresce la locandina selezionata',
                  value: ui.focusZoom.label,
                  onTap: () => pick<PosterFocusZoom>(
                    'Ingrandimento della selezione',
                    PosterFocusZoom.values,
                    ui.focusZoom,
                    (z) => z.label,
                    (s, v) => s.setFocusZoom(v),
                  ),
                ),
              ),
              PreviewTarget(
                zone: PreviewZone.focus,
                child: SettingsValueTile(
                  icon: Icons.crop_square_rounded,
                  title: 'Contorno della selezione',
                  subtitle: 'Senza ingrandimento il contorno resta sempre',
                  value: ui.focusRing.label,
                  onTap: () => pick<PosterFocusRing>(
                    'Contorno della selezione',
                    PosterFocusRing.values,
                    ui.focusRing,
                    (r) => r.label,
                    (s, v) => s.setFocusRing(v),
                  ),
                ),
              ),
              PreviewTarget(
                zone: PreviewZone.focus,
                child: SettingsSwitchTile(
                  icon: Icons.panorama_wide_angle_outlined,
                  title: 'Scena sulla locandina selezionata',
                  subtitle:
                      'Nelle righe della Home, fermandoti su una locandina '
                      "diventa un'immagine di scena",
                  value: ui.focusScene,
                  onChanged: ui.setFocusScene,
                ),
              ),
              if (ui.focusScene) ...[
                PreviewTarget(
                  zone: PreviewZone.focus,
                  child: SettingsSwitchTile(
                    icon: Icons.branding_watermark_outlined,
                    title: 'Scena: logo del titolo',
                    subtitle: "Il nome scritto finché il logo non c'è",
                    value: ui.focusSceneLogo,
                    onChanged: ui.setFocusSceneLogo,
                  ),
                ),
                PreviewTarget(
                  zone: PreviewZone.focus,
                  child: SettingsSwitchTile(
                    icon: Icons.info_outline_rounded,
                    title: 'Scena: anno, durata e voto',
                    value: ui.focusSceneDetails,
                    onChanged: ui.setFocusSceneDetails,
                  ),
                ),
                PreviewTarget(
                  zone: PreviewZone.focus,
                  child: SettingsSwitchTile(
                    icon: Icons.video_library_outlined,
                    title: 'Scena: episodio',
                    subtitle:
                        "Stagione, numero e titolo dell'episodio mostrato",
                    value: ui.focusSceneEpisode,
                    onChanged: ui.setFocusSceneEpisode,
                  ),
                ),
                PreviewTarget(
                  zone: PreviewZone.focus,
                  child: SettingsSwitchTile(
                    icon: Icons.sell_outlined,
                    title: 'Scena: avanzamento e badge',
                    subtitle:
                        'Barra di avanzamento e badge scelti per le locandine',
                    value: ui.focusSceneBadges,
                    onChanged: ui.setFocusSceneBadges,
                  ),
                ),
              ],
            ],
            PreviewTarget(
              zone: PreviewZone.homePage,
              child: SettingsSwitchTile(
                icon: Icons.animation_outlined,
                title: 'Animazioni',
                subtitle: 'Transizioni ed effetti al tocco',
                value: ui.animations,
                onChanged: ui.setAnimations,
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Home',
          children: [
            PreviewTarget(
              zone: PreviewZone.homePage,
              child: SettingsValueTile(
                icon: Icons.view_day_outlined,
                title: 'Righe della Home',
                subtitle: 'Scegli quali righe vedere e in che ordine',
                value: homeRowsSummary(ui),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HomeRowsScreen()),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.recommended,
              child: SettingsValueTile(
                icon: Icons.crop_portrait_rounded,
                title: 'Forma locandine consigliati e Top',
                value: ui.homePosterShape.label,
                onTap: () => pick<HomePosterShape>(
                  'Forma locandine',
                  HomePosterShape.values,
                  ui.homePosterShape,
                  (v) => v.label,
                  (s, v) => s.setHomePosterShape(v),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.recommended,
              child: SettingsValueTile(
                icon: Icons.view_column_rounded,
                title: 'Locandine visibili consigliati e Top',
                value: ui.homePosterDensity.label,
                onTap: () => pick<HomeDensity>(
                  'Locandine visibili',
                  HomeDensity.values,
                  ui.homePosterDensity,
                  (v) => v.label,
                  (s, v) => s.setHomePosterDensity(v),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.recommended,
              child: SettingsValueTile(
                icon: Icons.format_list_numbered_rounded,
                title: 'Numero titoli consigliati per riga',
                value: '${ui.homeRecommendationLimit}',
                onTap: () => pick<int>(
                  'Titoli consigliati',
                  HomeLayoutPolicy.recommendationLimits,
                  ui.homeRecommendationLimit,
                  (v) => '$v',
                  (s, v) => s.setHomeRecommendationLimit(v),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.recent,
              child: SettingsValueTile(
                icon: Icons.crop_landscape_rounded,
                title: 'Forma locandine viste di recente',
                value: ui.homeRecentShape.label,
                onTap: () => pick<HomePosterShape>(
                  'Forma recenti',
                  HomePosterShape.values,
                  ui.homeRecentShape,
                  (v) => v.label,
                  (s, v) => s.setHomeRecentShape(v),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.recent,
              child: SettingsValueTile(
                icon: Icons.view_carousel_rounded,
                title: 'Locandine visibili viste di recente',
                value: ui.homeRecentDensity.label,
                onTap: () => pick<HomeDensity>(
                  'Locandine recenti visibili',
                  HomeDensity.values,
                  ui.homeRecentDensity,
                  (v) => v.label,
                  (s, v) => s.setHomeRecentDensity(v),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.recent,
              child: SettingsValueTile(
                icon: Icons.history_rounded,
                title: 'Numero titoli recenti per riga',
                value: '${ui.homeRecentLimit}',
                onTap: () => pick<int>(
                  'Titoli recenti',
                  HomeLayoutPolicy.itemLimits,
                  ui.homeRecentLimit,
                  (v) => '$v',
                  (s, v) => s.setHomeRecentLimit(v),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.banner,
              child: SettingsValueTile(
                icon: Icons.panorama_outlined,
                title: 'Dimensione banner',
                value: ui.homeBannerSize.label,
                onTap: () => pick<HomeBannerSize>(
                  'Dimensione banner',
                  HomeBannerSize.values,
                  ui.homeBannerSize,
                  (v) => v.label,
                  (s, v) => s.setHomeBannerSize(v),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.banner,
              child: SettingsValueTile(
                icon: Icons.auto_awesome_motion_rounded,
                title: 'Contenuto del banner',
                value: ui.homeBannerSource
                    .on(tv: DeviceTypeService.isTv)
                    .label(tv: DeviceTypeService.isTv),
                onTap: () => pick<HomeBannerSource>(
                  'Contenuto del banner',
                  HomeBannerSourceInfo.options(tv: DeviceTypeService.isTv),
                  ui.homeBannerSource.on(tv: DeviceTypeService.isTv),
                  (v) => v.label(tv: DeviceTypeService.isTv),
                  (s, v) => s.setHomeBannerSource(v),
                ),
              ),
            ),
            if (DeviceTypeService.isTv) ...[
              PreviewTarget(
                zone: PreviewZone.banner,
                child: SettingsValueTile(
                  icon: Icons.movie_filter_outlined,
                  title: 'Trailer nella Home',
                  subtitle: ui.bannerTrailer.description,
                  value: ui.bannerTrailer.label,
                  onTap: () => pick<BannerTrailerMode>(
                    'Trailer nella Home',
                    BannerTrailerMode.values,
                    ui.bannerTrailer,
                    (m) => m.label,
                    (s, v) => s.setBannerTrailer(v),
                    detail: (m) => m.description,
                  ),
                ),
              ),
              if (ui.bannerTrailer != BannerTrailerMode.off) ...[
                PreviewTarget(
                  zone: PreviewZone.banner,
                  child: SettingsValueTile(
                    icon: Icons.timer_outlined,
                    title: 'Partenza del trailer',
                    subtitle: 'Secondi fermo sullo stesso titolo',
                    value: '${ui.bannerTrailerDelay} secondi',
                    onTap: () => pick<int>(
                      'Partenza del trailer',
                      bannerTrailerDelays,
                      ui.bannerTrailerDelay,
                      (s) => '$s secondi',
                      (s, v) => s.setBannerTrailerDelay(v),
                    ),
                  ),
                ),
                PreviewTarget(
                  zone: PreviewZone.banner,
                  child: SettingsValueTile(
                    icon: Icons.volume_up_outlined,
                    title: 'Audio del trailer',
                    subtitle: ui.bannerTrailerAudio.description,
                    value: ui.bannerTrailerAudio.label,
                    onTap: () => pick<BannerTrailerAudio>(
                      'Audio del trailer',
                      BannerTrailerAudio.values,
                      ui.bannerTrailerAudio,
                      (a) => a.label,
                      (s, v) => s.setBannerTrailerAudio(v),
                      detail: (a) => a.description,
                    ),
                  ),
                ),
              ],
            ],
            PreviewTarget(
              zone: PreviewZone.banner,
              child: SettingsSwitchTile(
                icon: Icons.subject_rounded,
                title: 'Trama nel banner',
                value: ui.homeOverview,
                onChanged: ui.setHomeOverview,
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.recommended,
              child: SettingsSwitchTile(
                icon: Icons.title_rounded,
                title: 'Titoli sotto consigliati',
                value: ui.homeTitles,
                onChanged: ui.setHomeTitles,
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.recent,
              child: SettingsSwitchTile(
                icon: Icons.short_text_rounded,
                title: 'Titoli sotto viste di recente',
                value: ui.homeRecentTitles,
                onChanged: ui.setHomeRecentTitles,
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.homePage,
              child: SettingsValueTile(
                icon: Icons.zoom_in_rounded,
                title: 'Scala interfaccia',
                value: '${ui.uiScalePercent}%',
                onTap: () => pick<int>(
                  'Scala interfaccia',
                  HomeLayoutPolicy.uiScales,
                  ui.uiScalePercent,
                  (v) => '$v%',
                  (s, v) => s.setUiScale(v),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.homePage,
              child: SettingsValueTile(
                icon: Icons.restart_alt_rounded,
                title: 'Ripristina Home e scala',
                onTap: () async {
                  final ok = await pickOption<bool>(
                    context,
                    title: 'Ripristinare Home e scala?',
                    options: const [false, true],
                    current: false,
                    label: (v) => v ? 'Ripristina' : 'Annulla',
                  );
                  if (ok == true) await ui.resetHomeLayout();
                },
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Cataloghi',
          description: 'Aspetto dei contenuti.',
          children: [
            for (final (type, title) in const [
              (ContentType.movie, 'Disposizione Film'),
              (ContentType.series, 'Disposizione Serie TV'),
            ])
              PreviewTarget(
                zone: type == ContentType.series
                    ? PreviewZone.catalogSeries
                    : PreviewZone.catalogPage,
                child: SettingsValueTile(
                  icon: ui.viewModeFor(type).icon,
                  title: title,
                  subtitle: ui.viewModeFor(type).description,
                  value: ui.viewModeFor(type).label,
                  onTap: () => pick<CatalogViewMode>(
                    title,
                    CatalogViewMode.values,
                    ui.viewModeFor(type),
                    (m) => m.label,
                    (s, m) => s.setCatalogViewMode(m, type: type),
                    detail: (m) => m.description,
                  ),
                ),
              ),
            PreviewTarget(
              zone: PreviewZone.catalogPage,
              child: SettingsValueTile(
                icon: Icons.photo_size_select_large_rounded,
                title: 'Dimensione dei poster',
                subtitle: ui.gridColumns > 0
                    ? 'Con le colonne fisse conta per Diretta e vista orizzontale'
                    : null,
                value: _gridLabel(ui.gridSize),
                onTap: () => pick<String>(
                  'Dimensione dei poster',
                  UiSettings.gridSizes.keys.toList(),
                  ui.gridSize,
                  _gridLabel,
                  (s, v) => s.setGridSize(v),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.catalogPage,
              child: SettingsValueTile(
                icon: Icons.view_column_rounded,
                title: 'Colonne della griglia',
                subtitle: 'Locandine per riga in cataloghi e Preferiti',
                value: _columnsLabel(ui.gridColumns),
                onTap: () => pick<int>(
                  'Colonne della griglia',
                  [0, ...UiSettings.gridColumnChoices()],
                  ui.gridColumns,
                  _columnsLabel,
                  (s, v) => s.setGridColumns(v),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.catalogPage,
              child: SettingsValueTile(
                icon: Icons.rounded_corner_rounded,
                title: 'Angoli delle locandine',
                value: ui.posterCorners.label,
                onTap: () => pick<PosterCorners>(
                  'Angoli delle locandine',
                  PosterCorners.values,
                  ui.posterCorners,
                  (c) => c.label,
                  (s, v) => s.setPosterCorners(v),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.catalogPage,
              child: SettingsValueTile(
                icon: Icons.title_rounded,
                title: 'Titoli delle locandine',
                subtitle: ui.titlePlacement.description,
                value: ui.titlePlacement.label,
                onTap: () => pick<TitlePlacement>(
                  'Titoli delle locandine',
                  TitlePlacement.values,
                  ui.titlePlacement,
                  (p) => p.label,
                  (s, v) => s.setTitlePlacement(v),
                  detail: (p) => p.description,
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.catalogPage,
              child: SettingsSwitchTile(
                icon: Icons.event_note_outlined,
                title: 'Anno e durata sotto il titolo',
                subtitle: 'La durata compare dopo aver aperto la scheda',
                value: ui.posterDetails,
                onChanged: ui.setPosterDetails,
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.catalogPage,
              child: SettingsSwitchTile(
                icon: Icons.landscape_outlined,
                title: 'Immagine di scena',
                subtitle: 'In Panoramica e In evidenza, per i titoli che la hanno già',
                value: ui.sceneArt,
                onChanged: ui.setSceneArt,
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.catalogPage,
              child: SettingsSwitchTile(
                icon: Icons.branding_watermark_outlined,
                title: 'Logo al posto del titolo',
                subtitle:
                    'In Panoramica, In evidenza, Muro e sulle copertine, '
                    'quando il logo è già noto',
                value: ui.titleLogos,
                onChanged: ui.setTitleLogos,
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.catalogPage,
              child: SettingsValueTile(
                icon: Icons.sell_outlined,
                title: 'Badge sulle locandine',
                subtitle:
                    'Voto, Nuovo, qualità, piattaforma, cuore, avanzamento',
                value: posterBadgesSummary(ui),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PosterBadgesScreen()),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.catalogPage,
              child: SettingsSwitchTile(
                icon: Icons.image_outlined,
                title: 'Mostra anteprime',
                subtitle: 'Locandine e loghi nei cataloghi',
                value: ui.showPosters,
                onChanged: ui.setShowPosters,
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.catalogPage,
              child: SettingsSwitchTile(
                icon: Icons.view_agenda_outlined,
                title: 'Modalità compatta',
                subtitle: 'Righe più fitte per vedere più contenuti',
                value: ui.compact,
                onChanged: ui.setCompact,
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Diretta',
          description: 'Guida dei canali sulla TV.',
          children: [
            PreviewTarget(
              zone: null,
              child: SettingsSwitchTile(
                icon: Icons.pin_outlined,
                title: 'Numeri dei canali',
                subtitle: "Gli stessi dei tasti numerici, nell'ordine predefinito di una categoria",
                value: ui.liveNumbers,
                onChanged: ui.setLiveNumbers,
              ),
            ),
            PreviewTarget(
              zone: null,
              child: SettingsSwitchTile(
                icon: Icons.smart_display_outlined,
                title: 'Anteprima video',
                subtitle:
                    'Il canale selezionato parte accanto alla guida. Spenta, '
                    'non usa connessioni finché non premi OK',
                value: ui.livePreview,
                onChanged: ui.setLivePreview,
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Navigazione',
          children: [
            PreviewTarget(
              zone: null,
              child: SettingsValueTile(
                icon: Icons.view_week_outlined,
                title: 'Ordine e sezione iniziale',
                subtitle: 'Riordina le sezioni',
                value: ui.startSection.label,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SectionLayoutScreen(),
                  ),
                ),
              ),
            ),
            PreviewTarget(
              zone: null,
              child: SettingsValueTile(
                icon: Icons.download_for_offline_outlined,
                title: 'Download',
                subtitle: 'Contenuti da guardare senza connessione',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                ),
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.homePage,
              child: SettingsValueTile(
                icon: Icons.restart_alt_rounded,
                title: 'Ripristina aspetto predefinito',
                subtitle: 'Colore, testo e cataloghi tornano come all\'inizio',
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Ripristinare l\'aspetto?'),
                      content: const Text(
                        'Le altre impostazioni non cambiano.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Annulla'),
                        ),
                        TextButton(
                          autofocus: true,
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Ripristina'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await ui.resetAppearance();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _textScaleLabel(String key) => switch (key) {
    'normale' => 'Normale',
    'grande' => 'Grande',
    'molto_grande' => 'Molto grande',
    _ => key,
  };

  String _accentLabel(String key) => switch (key) {
    'arancio' => 'Arancione',
    'verde' => 'Verde',
    'azzurro' => 'Azzurro',
    'rosso' => 'Rosso',
    'giallo' => 'Giallo',
    'ciano' => 'Ciano',
    'rosa' => 'Rosa',
    'viola' => 'Viola cosmico',
    'blu' => 'Blu spaziale',
    'smeraldo' => 'Smeraldo',
    'titanio' => 'Titanio',
    _ => key,
  };

  String _columnsLabel(int columns) =>
      columns == 0 ? 'Automatiche' : '$columns colonne';

  String _gridLabel(String key) => switch (key) {
    'piccola' => 'Piccola',
    'media' => 'Media',
    'grande' => 'Grande',
    _ => key,
  };

  String _connectionLabel(AppProvider provider) =>
      switch (provider.authMethod.name) {
        'xtream' => switch (provider.sourceKind) {
          SourceKind.account => 'Nome utente e password',
          SourceKind.link => 'Indirizzo unico',
          SourceKind.portal => 'Portale con indirizzo MAC',
        },
        _ => 'Non connesso',
      };

  Widget _buildPlaylistRefresh(BuildContext context, AppProvider provider) {
    final current = PlaylistRefreshInterval.fromMinutes(
      _refreshMinutes ?? _loadedRefreshMinutes,
    );
    return SettingsSection(
      title: 'Aggiornamento contenuti',
      description: 'Stato dei contenuti: scegli la sezione da aggiornare.',
      children: [
        if (provider.authMethod.name == 'xtream') const PlaylistStatusList(),
        if (provider.authMethod.name == 'xtream')
          SettingsValueTile(
            icon: Icons.sync_rounded,
            title: 'Aggiorna tutto ora',
            subtitle: provider.isRefreshingAny
                ? 'Aggiornamento in corso...'
                : 'Aggiorna tutti i contenuti',
            onTap: provider.isRefreshingAny
                ? null
                : () async {
                    await provider.refreshAllSections();
                    if (!mounted) return;
                    await _loadRefreshState();
                  },
          ),
        SettingsValueTile(
          icon: Icons.update_rounded,
          title: 'Frequenza aggiornamento',
          subtitle: current == PlaylistRefreshInterval.off
              ? 'I contenuti si aggiornano solo aprendo l\'app'
              : 'Ultimo aggiornamento: ${_lastRefreshLabel ?? 'in corso'}',
          value: current.label,
          onTap: () async {
            final chosen = await pickOption<PlaylistRefreshInterval>(
              context,
              title: 'Aggiorna i contenuti ogni...',
              options: PlaylistRefreshInterval.values,
              current: current,
              label: (v) => v.label,
            );
            if (chosen == null || !mounted) return;
            setState(() => _refreshMinutes = chosen.minutes);
            await provider.saveRefreshInterval(chosen.minutes);
            if (!mounted) return;
            setState(() {
              // Keep the saved choice visible instead of the stale value.
              _loadedRefreshMinutes = chosen.minutes;
              _refreshMinutes = null;
              _lastRefreshLabel = _formatLastRefresh(_lastRefresh);
            });
          },
        ),
      ],
    );
  }

  /// Settings macro areas (tvOS-style sidebar on TV, drill-down on phone).
  int _category = 0;
  bool _phoneDetail = false;

  static const _categories = <(IconData, String, String)>[
    (
      Icons.person_rounded,
      'Account e profili',
      'Accesso, sincronizzazione, profili e connessione',
    ),
    (
      Icons.palette_rounded,
      'Aspetto e Home',
      'Colori, testo, locandine, banner e cataloghi',
    ),
    (
      Icons.play_circle_fill_rounded,
      'Riproduzione',
      'Player, sottotitoli, MultiView e cronologia',
    ),
    (
      Icons.video_library_rounded,
      'Contenuti',
      'Categorie, aggiornamento e guida TV',
    ),
    (
      Icons.monitor_heart_rounded,
      'Diagnostica',
      'Rapporti di dirette, film, serie e fluidità',
    ),
    (Icons.info_rounded, 'Informazioni', 'Versione e aggiornamenti'),
  ];

  List<Widget> _sectionsFor(int index, AppProvider provider) => switch (index) {
    0 => [
      SettingsSection(
        title: 'Account',
        description:
            'Profili e dati personali protetti tra dispositivi autorizzati.',
        children: [
          SettingsValueTile(
            icon: Icons.cloud_sync_outlined,
            title: 'Backup e sincronizzazione',
            subtitle: 'Email, sincronizzazione e uscita dall\'account',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SyncSettingsScreen()),
            ),
          ),
        ],
      ),
      SettingsSection(
        title: 'Profili',
        children: [
          SettingsValueTile(
            icon: Icons.people_outline_rounded,
            title: 'Gestisci profili',
            subtitle:
                'Cambia profilo, creane uno nuovo o imposta il predefinito',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfilePickerScreen()),
            ),
          ),
        ],
      ),
      SettingsSection(
        title: 'Connessione',
        children: [
          SettingsValueTile(
            icon: Icons.login_rounded,
            title: 'Metodo di connessione',
            value: _connectionLabel(provider),
          ),
          if (provider.authMethod.name == 'xtream')
            SettingsValueTile(
              icon: Icons.edit_outlined,
              title: 'Modifica connessione locale',
              subtitle: switch (provider.sourceKind) {
                SourceKind.account => 'Server URL, nome utente e password',
                SourceKind.link => 'Indirizzo unico dei contenuti',
                SourceKind.portal => 'Indirizzo del portale e MAC',
              },
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const XtreamEditScreen()),
              ),
            ),
          if (provider.authMethod.name == 'xtream' &&
              provider.sourceKind == SourceKind.account)
            SettingsValueTile(
              icon: Icons.badge_outlined,
              title: 'Connessione locale',
              subtitle: 'Scadenza, stato, connessioni e dati della sorgente',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const XtreamAccountScreen()),
              ),
            ),
          if (provider.authMethod.name == 'xtream' &&
              provider.sourceKind == SourceKind.account)
            SettingsValueTile(
              icon: Icons.notifications_active_outlined,
              title: 'Promemoria scadenza',
              subtitle: 'Avvisi prima della scadenza dell\'accesso',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExpiryReminderScreen()),
              ),
            ),
          if (provider.allChannels.isNotEmpty)
            SettingsValueTile(
              icon: Icons.tv_rounded,
              title: 'Contenuti caricati',
              value: '${provider.allChannels.length}',
            ),
          if (provider.isAuthenticated)
            SettingsValueTile(
              icon: Icons.logout_rounded,
              title: 'Disconnetti',
              color: AppColors.error,
              onTap: () => _handleLogout(provider),
            ),
        ],
      ),
    ],
    1 => [_buildUiCustomization(context)],
    2 => [
      SettingsSection(
        title: 'Riproduzione',
        children: [
          SettingsValueTile(
            icon: Icons.dashboard_customize_outlined,
            title: 'MultiView',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MultiViewSettingsScreen(),
              ),
            ),
          ),
          SettingsValueTile(
            icon: Icons.play_circle_outline_rounded,
            title: 'Player video',
            subtitle:
                'Motori, audio, sottotitoli, buffer, HDR e Picture-in-Picture',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlayerSettingsScreen()),
            ),
          ),
          SettingsValueTile(
            icon: Icons.check_circle_outline_rounded,
            title: 'Soglia contenuto visto',
            subtitle: 'Da quale percentuale un titolo conta come visto',
            value: '${context.watch<UiSettings>().watchedPercent}%',
            onTap: () async {
              final ui = context.read<UiSettings>();
              final chosen = await pickOption<int>(
                context,
                title: 'Soglia contenuto visto',
                options: WatchCompletionPolicy.options,
                current: ui.watchedPercent,
                label: (v) => '$v%',
              );
              if (chosen != null) await ui.setWatchedPercent(chosen);
            },
          ),
          SettingsValueTile(
            icon: Icons.history_rounded,
            title: 'Cronologia',
            subtitle: 'Gestisci i contenuti visti e le posizioni di ripresa',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistorySettingsScreen()),
            ),
          ),
          SettingsValueTile(
            icon: Icons.dns_outlined,
            title: 'DNS',
            subtitle: 'Server che trova gli indirizzi, cifrato e senza filtri',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DnsSettingsScreen()),
            ),
          ),
          if (VpnService.supported)
            SettingsValueTile(
              icon: Icons.vpn_lock_outlined,
              title: 'VPN personale',
              subtitle: 'Il tuo servizio VPN, attivo già prima dell\'accesso',
              value: VpnService.instance.enabled
                  ? VpnService.instance.label
                  : 'Spenta',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VpnSettingsScreen()),
              ),
            ),
        ],
      ),
    ],
    3 => [
      SettingsSection(
        title: 'Categorie',
        children: [
          SettingsValueTile(
            icon: Icons.reorder_rounded,
            title: 'Categorie personali e ordine',
            subtitle: 'Crea le tue categorie e riordina quelle della playlist',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CategoryManagerScreen()),
            ),
          ),
          SettingsValueTile(
            icon: Icons.visibility_off_outlined,
            title: 'Categorie nascoste',
            subtitle: 'Nascondi le categorie che non ti interessano',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HiddenCategoriesScreen()),
            ),
          ),
          const CatalogStartTiles(),
          SettingsSwitchTile(
            icon: Icons.no_adult_content_outlined,
            title: 'Mostra contenuti per adulti',
            subtitle: 'Contenuti riservati agli adulti (nascosti di base)',
            value: provider.showAdult,
            onChanged: provider.setShowAdult,
          ),
        ],
      ),
      _buildPlaylistRefresh(context, provider),
      SettingsSection(
        title: 'Guida TV',
        children: [
          SettingsValueTile(
            icon: Icons.calendar_view_day_rounded,
            title: 'Guida TV (EPG)',
            subtitle: 'Fonti, aggiornamento automatico (ogni 12 ore di base)',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EpgSettingsScreen()),
            ),
          ),
        ],
      ),
    ],
    4 => [
      SettingsSection(
        title: 'Diagnostica',
        children: [
          SettingsValueTile(
            icon: Icons.monitor_heart_outlined,
            title: 'Diagnostica dirette',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LiveDiagnosticsScreen()),
            ),
          ),
          SettingsValueTile(
            icon: Icons.movie_filter_outlined,
            title: 'Diagnostica film e serie',
            subtitle: 'Fotogrammi scartati, buffer e scatti del lettore mpv/ExoPlayer',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VodDiagnosticsScreen()),
            ),
          ),
          SettingsValueTile(
            icon: Icons.speed_rounded,
            title: 'Prestazioni e fluidità',
            subtitle: 'FPS, fotogrammi lenti, tempi di calcolo e disegno',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PerformanceDiagnosticsScreen(),
              ),
            ),
          ),
        ],
      ),
    ],
    _ => [
      SettingsSection(
        title: 'Informazioni',
        children: [
          SettingsValueTile(
            icon: Icons.info_outline_rounded,
            title: 'Versione',
            value: AppUpdateService.currentVersion,
          ),
          SettingsValueTile(
            icon: Icons.system_update_rounded,
            title: 'Verifica aggiornamenti',
            subtitle: 'Scarica e installa la nuova versione',
            onTap: () => AppUpdateService.checkManually(context),
          ),
          const SettingsValueTile(
            icon: Icons.phone_android_rounded,
            title: 'Piattaforma',
            value: 'Android e iOS',
          ),
        ],
      ),
    ],
  };

  /// "Aspetto e Home" keeps its preview in view while the list scrolls.
  Widget _withPreview(Widget list) {
    if (_category != 1) return list;
    // Built with the list: the settings below report to this controller.
    final controller = _preview ??= SettingsPreviewController(
      context.read<UiSettings>(),
    );
    return SettingsPreviewLayout(controller: controller, list: list);
  }

  Widget _categoryTile(int i, {required bool tv}) {
    final (icon, title, subtitle) = _categories[i];
    final selected = tv && i == _category;
    void open() => setState(() {
      _category = i;
      if (!tv) _phoneDetail = true;
    });
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TvFocusable(
        focusNode: tv ? _categoryNodes[i] : null,
        autofocus: tv && i == 0,
        borderRadius: BorderRadius.circular(14),
        onFocusChange: tv
            ? (f) {
                if (f && _category != i) setState(() => _category = i);
              }
            : null,
        onPressed: open,
        child: PhoneTap(
          onTap: open,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: tv ? 14 : 12,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.16)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 20, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: tv ? 17 : 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!tv)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final tv = DeviceTypeService.isTv;
    if (tv) {
      return ApplePageScaffold(
        title: 'Impostazioni',
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 320,
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _onCategoryKey,
                child: FocusTraversalGroup(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 12, 32),
                    children: [
                      for (var i = 0; i < _categories.length; i++)
                        _categoryTile(i, tv: true),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Focus(
                focusNode: _detailNode,
                onKeyEvent: (_, event) {
                  if (event is! KeyUpEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    _categoryNodes[_category].requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: FocusTraversalGroup(
                  child: _withPreview(
                    ListView(
                      key: ValueKey(_category),
                      padding: EdgeInsets.fromLTRB(
                        12,
                        8,
                        _category == 1 ? 12 : 32,
                        32,
                      ),
                      children: _sectionsFor(_category, provider),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_phoneDetail) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _phoneDetail = false);
        },
        child: ApplePageScaffold(
          title: _categories[_category].$2,
          actions: [
            IconButton(
              tooltip: 'Tutte le impostazioni',
              icon: const Icon(Icons.grid_view_rounded),
              onPressed: () => setState(() => _phoneDetail = false),
            ),
          ],
          body: _withPreview(
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: _sectionsFor(_category, provider),
            ),
          ),
        ),
      );
    }
    return ApplePageScaffold(
      title: 'Impostazioni',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (var i = 0; i < _categories.length; i++)
            _categoryTile(i, tv: false),
        ],
      ),
    );
  }

  Future<void> _handleLogout(AppProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Disconnettere?'),
        content: const Text(
          'Verranno rimossi la connessione salvata e tutti i canali caricati. Dovrai accedere di nuovo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Disconnetti',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final sync = context.read<SyncProvider>();
    try {
      await logoutFromSettings(
        signOut: sync.signOut,
        resetGuest: () => AccountScreen.setGuest(false),
        clearPlaylist: provider.logout,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnessione non completata. Riprova.'),
        ),
      );
      return;
    }
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AccountScreen()),
        (_) => false,
      );
    }
  }
}

/// Row of colour dots: pick the accent directly with the remote.
class _AccentPalette extends StatelessWidget {
  const _AccentPalette({
    required this.current,
    required this.label,
    required this.onSelected,
  });

  final String current;
  final String Function(String) label;
  final Future<void> Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Colore principale · ${label(current)}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final e in UiSettings.accents.entries)
                TvFocusable(
                  borderRadius: BorderRadius.circular(22),
                  focusedScale: 1.15,
                  onPressed: () => onSelected(e.key),
                  child: GestureDetector(
                    onTap: () => onSelected(e.key),
                    child: Tooltip(
                      message: label(e.key),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: e.value,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: e.key == current
                                ? AppColors.textPrimary
                                : AppColors.clear,
                            width: 3,
                          ),
                        ),
                        child: e.key == current
                            ? const Icon(
                                Icons.check_rounded,
                                color: AppColors.background,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
