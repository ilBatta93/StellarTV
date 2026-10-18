import 'package:flutter/material.dart';

import '../widgets/apple_page_scaffold.dart';

import 'package:provider/provider.dart';

import '../widgets/catalog_section_status.dart';

import '../providers/app_provider.dart';
import '../providers/ui_settings.dart';
import '../models/home_layout_preferences.dart';
import '../models/watch_completion_policy.dart';
import '../services/playlist_refresh_service.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_tiles.dart';
import '../widgets/tv_focusable.dart';
import 'account_screen.dart';
import 'xtream_edit_screen.dart';
import '../providers/sync_provider.dart';
import '../services/settings_logout.dart';
import 'history_settings_screen.dart';
import 'hidden_categories_screen.dart';
import 'epg_settings_screen.dart';
import 'player_settings_screen.dart';
import 'profile_picker_screen.dart';
import 'sync_settings_screen.dart';
import 'expiry_reminder_screen.dart';
import 'xtream_account_screen.dart';
import 'section_layout_screen.dart';
import 'downloads_screen.dart';
import 'multiview_settings_screen.dart';
import 'live_diagnostics_screen.dart';
import '../services/app_update_service.dart';

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
            SettingsValueTile(
              icon: Icons.check_circle_outline_rounded,
              title: 'Soglia contenuto visto',
              value: '${ui.watchedPercent}%',
              onTap: () => pick<int>(
                'Soglia contenuto visto',
                WatchCompletionPolicy.options,
                ui.watchedPercent,
                (v) => '$v%',
                ui.setWatchedPercent,
              ),
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
            SettingsSwitchTile(
              icon: Icons.subject_rounded,
              title: 'Trama nel banner',
              value: ui.homeOverview,
              onChanged: ui.setHomeOverview,
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
            SettingsValueTile(
              icon: ui.viewMode.icon,
              title: 'Disposizione delle schede',
              subtitle: ui.viewMode.description,
              value: ui.viewMode.label,
              onTap: () => pick<CatalogViewMode>(
                'Disposizione delle schede',
                CatalogViewMode.values,
                ui.viewMode,
                (m) => m.label,
                ui.setCatalogViewMode,
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
              icon: Icons.hd_outlined,
              title: 'Etichette qualità',
              subtitle: '4K, FHD, HD sulle copertine',
              value: ui.showQuality,
              onChanged: ui.setShowQuality,
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
        'xtream' => 'Connessione locale',
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
              _refreshMinutes = null;
              _lastRefreshLabel = _formatLastRefresh(_lastRefresh);
            });
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return ApplePageScaffold(
      title: 'Impostazioni',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsSection(
            title: 'Riproduzione',
            children: [
              SettingsValueTile(
                icon: Icons.monitor_heart_outlined,
                title: 'Diagnostica dirette',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LiveDiagnosticsScreen(),
                  ),
                ),
              ),
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
                subtitle: 'Motori, audio, sottotitoli, buffer, HDR e Picture-in-Picture',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PlayerSettingsScreen(),
                  ),
                ),
              ),
              SettingsValueTile(
                icon: Icons.history_rounded,
                title: 'Cronologia',
                subtitle:
                    'Gestisci i contenuti visti e le posizioni di ripresa',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const HistorySettingsScreen(),
                  ),
                ),
              ),
              SettingsValueTile(
                icon: Icons.visibility_off_outlined,
                title: 'Categorie nascoste',
                subtitle: 'Nascondi le categorie che non ti interessano',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const HiddenCategoriesScreen(),
                  ),
                ),
              ),
              SettingsSwitchTile(
                icon: Icons.no_adult_content_outlined,
                title: 'Mostra contenuti per adulti',
                subtitle: 'Contenuti riservati agli adulti (nascosti di base)',
                value: provider.showAdult,
                onChanged: provider.setShowAdult,
              ),
            ],
          ),
          SettingsSection(
            title: 'Account',
            description: 'Profili e dati personali protetti tra dispositivi autorizzati.',
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
            description: 'Un profilo per ogni persona che usa l\'app. Il profilo scelto resta attivo al prossimo avvio.',
            children: [
              SettingsValueTile(
                icon: Icons.people_outline_rounded,
                title: 'Gestisci profili',
                subtitle:
                    'Cambia profilo, creane uno nuovo o imposta il predefinito',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProfilePickerScreen(),
                  ),
                ),
              ),
            ],
          ),
          _buildUiCustomization(context),
          _buildPlaylistRefresh(context, provider),
          SettingsSection(
            title: 'Guida TV',
            children: [
              SettingsValueTile(
                icon: Icons.calendar_view_day_rounded,
                title: 'Guida TV (EPG)',
                subtitle:
                    'Fonti, aggiornamento automatico (ogni 12 ore di base)',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EpgSettingsScreen()),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: 'Account',
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
                  subtitle: 'Server URL, nome utente e password',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const XtreamEditScreen()),
                  ),
                ),
              if (provider.authMethod.name == 'xtream')
                SettingsValueTile(
                  icon: Icons.badge_outlined,
                  title: 'Connessione locale',
                  subtitle: 'Scadenza, stato, connessioni e dati del provider',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const XtreamAccountScreen(),
                    ),
                  ),
                ),
              if (provider.authMethod.name == 'xtream')
                SettingsValueTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Promemoria scadenza',
                  subtitle: 'Avvisi prima della scadenza dell\'abbonamento',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ExpiryReminderScreen(),
                    ),
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
