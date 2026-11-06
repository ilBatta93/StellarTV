import 'dart:math' as math;

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
import 'epg_settings_screen.dart';
import 'player_settings_screen.dart';
import 'profile_picker_screen.dart';
import 'sync_settings_screen.dart';
import 'expiry_reminder_screen.dart';
import 'xtream_account_screen.dart';
import 'section_layout_screen.dart';
import 'home_rows_screen.dart';
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

  @override
  void dispose() {
    _detailNode.dispose();
    for (final node in _categoryNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _buildUiCustomization(BuildContext context) {
    final ui = context.watch<UiSettings>();
    Future<void> pick<T>(
      String title,
      List<T> options,
      T current,
      String Function(T) label,
      Future<void> Function(T) apply, {
      String? Function(T)? detail,
    }) async {
      final chosen = await pickOption<T>(
        context,
        title: title,
        options: options,
        current: current,
        label: label,
        detail: detail,
      );
      if (chosen != null) await apply(chosen);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Aspetto',
          description:
              'Colori, testo ed effetti. Tutto viene salvato nel cloud.',
          children: [
            _AccentPalette(
              current: ui.accentName,
              label: _accentLabel,
              onSelected: ui.setAccent,
            ),
            SettingsValueTile(
              icon: Icons.text_fields_rounded,
              title: 'Dimensione testo',
              subtitle: 'Utile sulle TV lontane dal divano',
              value: _textScaleLabel(ui.textScale),
              onTap: () => pick<String>(
                'Dimensione testo',
                UiSettings.textScales.keys.toList(),
                ui.textScale,
                _textScaleLabel,
                ui.setTextScale,
              ),
            ),
            SettingsSwitchTile(
              icon: Icons.auto_awesome_outlined,
              title: 'Bagliore di selezione',
              subtitle: 'Alone colorato attorno all\'elemento selezionato col telecomando',
              value: ui.focusGlow,
              onChanged: ui.setFocusGlow,
            ),
            SettingsSwitchTile(
              icon: Icons.animation_outlined,
              title: 'Animazioni',
              subtitle: 'Transizioni ed effetti al tocco',
              value: ui.animations,
              onChanged: ui.setAnimations,
            ),
          ],
        ),
        SettingsSection(
          title: 'Home',
          children: [
            _HomePosterPreview(ui: ui),
            SettingsValueTile(
              icon: Icons.view_day_outlined,
              title: 'Righe della Home',
              subtitle: 'Scegli quali righe vedere e in che ordine',
              value: homeRowsSummary(ui),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const HomeRowsScreen())),
            ),
            SettingsValueTile(
              icon: Icons.crop_portrait_rounded,
              title: 'Forma locandine consigliati e Top',
              value: ui.homePosterShape.label,
              onTap: () => pick<HomePosterShape>(
                'Forma locandine',
                HomePosterShape.values,
                ui.homePosterShape,
                (v) => v.label,
                ui.setHomePosterShape,
              ),
            ),
            SettingsValueTile(
              icon: Icons.view_column_rounded,
              title: 'Locandine visibili consigliati e Top',
              value: ui.homePosterDensity.label,
              onTap: () => pick<HomeDensity>(
                'Locandine visibili',
                HomeDensity.values,
                ui.homePosterDensity,
                (v) => v.label,
                ui.setHomePosterDensity,
              ),
            ),
            SettingsValueTile(
              icon: Icons.format_list_numbered_rounded,
              title: 'Numero titoli consigliati per riga',
              value: '${ui.homeRecommendationLimit}',
              onTap: () => pick<int>(
                'Titoli consigliati',
                HomeLayoutPolicy.recommendationLimits,
                ui.homeRecommendationLimit,
                (v) => '$v',
                ui.setHomeRecommendationLimit,
              ),
            ),
            SettingsValueTile(
              icon: Icons.crop_landscape_rounded,
              title: 'Forma locandine viste di recente',
              value: ui.homeRecentShape.label,
              onTap: () => pick<HomePosterShape>(
                'Forma recenti',
                HomePosterShape.values,
                ui.homeRecentShape,
                (v) => v.label,
                ui.setHomeRecentShape,
              ),
            ),
            SettingsValueTile(
              icon: Icons.view_carousel_rounded,
              title: 'Locandine visibili viste di recente',
              value: ui.homeRecentDensity.label,
              onTap: () => pick<HomeDensity>(
                'Locandine recenti visibili',
                HomeDensity.values,
                ui.homeRecentDensity,
                (v) => v.label,
                ui.setHomeRecentDensity,
              ),
            ),
            SettingsValueTile(
              icon: Icons.history_rounded,
              title: 'Numero titoli recenti per riga',
              value: '${ui.homeRecentLimit}',
              onTap: () => pick<int>(
                'Titoli recenti',
                HomeLayoutPolicy.itemLimits,
                ui.homeRecentLimit,
                (v) => '$v',
                ui.setHomeRecentLimit,
              ),
            ),
            SettingsValueTile(
              icon: Icons.panorama_outlined,
              title: 'Dimensione banner',
              value: ui.homeBannerSize.label,
              onTap: () => pick<HomeBannerSize>(
                'Dimensione banner',
                HomeBannerSize.values,
                ui.homeBannerSize,
                (v) => v.label,
                ui.setHomeBannerSize,
              ),
            ),
            SettingsValueTile(
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
                ui.setHomeBannerSource,
              ),
            ),
            SettingsSwitchTile(
              icon: Icons.subject_rounded,
              title: 'Trama nel banner',
              value: ui.homeOverview,
              onChanged: ui.setHomeOverview,
            ),
            SettingsSwitchTile(
              icon: Icons.title_rounded,
              title: 'Titoli sotto consigliati',
              value: ui.homeTitles,
              onChanged: ui.setHomeTitles,
            ),
            SettingsSwitchTile(
              icon: Icons.short_text_rounded,
              title: 'Titoli sotto viste di recente',
              value: ui.homeRecentTitles,
              onChanged: ui.setHomeRecentTitles,
            ),
            SettingsValueTile(
              icon: Icons.zoom_in_rounded,
              title: 'Scala interfaccia',
              value: '${ui.uiScalePercent}%',
              onTap: () => pick<int>(
                'Scala interfaccia',
                HomeLayoutPolicy.uiScales,
                ui.uiScalePercent,
                (v) => '$v%',
                ui.setUiScale,
              ),
            ),
            SettingsValueTile(
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
              SettingsValueTile(
                icon: ui.viewModeFor(type).icon,
                title: title,
                subtitle: ui.viewModeFor(type).description,
                value: ui.viewModeFor(type).label,
                onTap: () => pick<CatalogViewMode>(
                  title,
                  CatalogViewMode.values,
                  ui.viewModeFor(type),
                  (m) => m.label,
                  (m) => ui.setCatalogViewMode(m, type: type),
                  detail: (m) => m.description,
                ),
              ),
            SettingsValueTile(
              icon: Icons.photo_size_select_large_rounded,
              title: 'Dimensione dei poster',
              value: _gridLabel(ui.gridSize),
              onTap: () => pick<String>(
                'Dimensione dei poster',
                UiSettings.gridSizes.keys.toList(),
                ui.gridSize,
                _gridLabel,
                ui.setGridSize,
              ),
            ),
            SettingsValueTile(
              icon: Icons.rounded_corner_rounded,
              title: 'Angoli delle locandine',
              value: ui.posterCorners.label,
              onTap: () => pick<PosterCorners>(
                'Angoli delle locandine',
                PosterCorners.values,
                ui.posterCorners,
                (c) => c.label,
                ui.setPosterCorners,
              ),
            ),
            SettingsSwitchTile(
              icon: Icons.title_rounded,
              title: 'Titoli sotto le locandine',
              subtitle: 'Spegnili per un muro di sole copertine',
              value: ui.showTitles,
              onChanged: ui.setShowTitles,
            ),
            SettingsSwitchTile(
              icon: Icons.star_outline_rounded,
              title: 'Voti sulle locandine',
              value: ui.showRatings,
              onChanged: ui.setShowRatings,
            ),
            SettingsSwitchTile(
              icon: Icons.task_alt_rounded,
              title: 'Avanzamento sulle locandine',
              subtitle: 'Barra dei titoli iniziati e segno sui titoli visti',
              value: ui.posterProgress,
              onChanged: ui.setPosterProgress,
            ),
            SettingsSwitchTile(
              icon: Icons.event_note_outlined,
              title: 'Anno e durata sotto il titolo',
              subtitle: 'La durata compare dopo aver aperto la scheda',
              value: ui.posterDetails,
              onChanged: ui.setPosterDetails,
            ),
            SettingsSwitchTile(
              icon: Icons.hd_outlined,
              title: 'Etichette qualità',
              subtitle: '4K, FHD, HD sulle copertine',
              value: ui.showQuality,
              onChanged: ui.setShowQuality,
            ),
            SettingsSwitchTile(
              icon: Icons.favorite_border_rounded,
              title: 'Cuore su tutte le locandine',
              subtitle: 'Spento, resta solo sui titoli già nei preferiti',
              value: ui.favoriteHeart,
              onChanged: ui.setFavoriteHeart,
            ),
            SettingsSwitchTile(
              icon: Icons.image_outlined,
              title: 'Mostra anteprime',
              subtitle: 'Locandine e loghi nei cataloghi',
              value: ui.showPosters,
              onChanged: ui.setShowPosters,
            ),
            SettingsSwitchTile(
              icon: Icons.view_agenda_outlined,
              title: 'Modalità compatta',
              subtitle: 'Righe più fitte per vedere più contenuti',
              value: ui.compact,
              onChanged: ui.setCompact,
            ),
          ],
        ),
        SettingsSection(
          title: 'Diretta',
          description: 'Guida dei canali sulla TV.',
          children: [
            SettingsSwitchTile(
              icon: Icons.pin_outlined,
              title: 'Numeri dei canali',
              subtitle: "Gli stessi dei tasti numerici, nell'ordine predefinito di una categoria",
              value: ui.liveNumbers,
              onChanged: ui.setLiveNumbers,
            ),
            SettingsSwitchTile(
              icon: Icons.smart_display_outlined,
              title: 'Anteprima video',
              subtitle:
                  'Il canale selezionato parte accanto alla guida. Spenta, '
                  'non usa connessioni finché non premi OK',
              value: ui.livePreview,
              onChanged: ui.setLivePreview,
            ),
          ],
        ),
        SettingsSection(
          title: 'Navigazione',
          children: [
            SettingsValueTile(
              icon: Icons.view_week_outlined,
              title: 'Ordine e sezione iniziale',
              subtitle: 'Riordina le sezioni',
              value: ui.startSection.label,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SectionLayoutScreen()),
              ),
            ),
            SettingsValueTile(
              icon: Icons.download_for_offline_outlined,
              title: 'Download',
              subtitle: 'Contenuti da guardare senza connessione',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
              ),
            ),
            SettingsValueTile(
              icon: Icons.restart_alt_rounded,
              title: 'Ripristina aspetto predefinito',
              subtitle: 'Colore, testo e cataloghi tornano come all\'inizio',
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Ripristinare l\'aspetto?'),
                    content: const Text('Le altre impostazioni non cambiano.'),
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
                  child: ListView(
                    key: ValueKey(_category),
                    padding: const EdgeInsets.fromLTRB(12, 8, 32, 32),
                    children: _sectionsFor(_category, provider),
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
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: _sectionsFor(_category, provider),
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
/// Sketch of the two Home rows with the current shape, density and titles:
/// the effect of each choice shows at once, without loading any image.
class _HomePosterPreview extends StatelessWidget {
  const _HomePosterPreview({required this.ui});

  final UiSettings ui;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _strip(
            'Consigliati e Top',
            ui.homePosterShape,
            ui.homePosterDensity,
            ui.homeTitles,
            progress: false,
          ),
          const SizedBox(height: 12),
          _strip(
            'Viste di recente',
            ui.homeRecentShape,
            ui.homeRecentDensity,
            ui.homeRecentTitles,
            progress: true,
          ),
        ],
      ),
    ),
  );

  Widget _strip(
    String label,
    HomePosterShape shape,
    HomeDensity density,
    bool titles, {
    required bool progress,
  }) {
    final tv = DeviceTypeService.isTv;
    final visible = density.visibleCards(tv);
    final count = visible == 0 ? (tv ? 5.0 : 2.5) : visible;
    const gap = 8.0;
    const maxHeight = 72.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, box) {
            final width = math.min(
              (box.maxWidth - gap * (count - 1)) / count,
              maxHeight * shape.aspectRatio,
            );
            final cards = math.max(1, (box.maxWidth / (width + gap)).ceil());
            return ClipRect(
              child: SizedBox(
                height: width / shape.aspectRatio + (titles ? 14 : 0),
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: Row(
                    children: [
                      for (var i = 0; i < cards; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        _card(width, shape, titles, progress, i),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _card(
    double width,
    HomePosterShape shape,
    bool titles,
    bool progress,
    int index,
  ) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: width,
          height: width / shape.aspectRatio,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(
                  alpha: (0.35 - index * 0.04).clamp(0.08, 0.35),
                ),
                AppColors.card,
              ],
            ),
          ),
          alignment: Alignment.bottomLeft,
          padding: const EdgeInsets.all(4),
          child: progress
              ? FractionallySizedBox(
                  widthFactor: 0.25 + (index % 3) * 0.2,
                  child: Container(height: 3, color: AppColors.primary),
                )
              : null,
        ),
        if (titles) ...[
          const SizedBox(height: 6),
          Container(
            width: width * 0.7,
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.textMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ],
    ),
  );
}

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
