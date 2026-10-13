import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/catalog_section_status.dart';

import '../providers/app_provider.dart';
import '../providers/ui_settings.dart';
import '../services/playlist_refresh_service.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_tiles.dart';
import 'login_screen.dart';
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
    return SettingsSection(
      title: 'Personalizzazione',
      description: 'Adatta l\'aspetto dell\'app ai tuoi gusti.',
      children: [
        SettingsValueTile(
          icon: Icons.palette_outlined,
          title: 'Colore principale',
          value: _accentLabel(ui.accentName),
          onTap: () async {
            final chosen = await pickOption<String>(
              context,
              title: 'Colore principale',
              options: UiSettings.accents.keys.toList(),
              current: ui.accentName,
              label: _accentLabel,
            );
            if (chosen != null) await ui.setAccent(chosen);
          },
        ),
        SettingsValueTile(
          icon: Icons.download_for_offline_outlined,
          title: 'Download',
          subtitle: 'Film ed episodi da guardare senza connessione',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DownloadsScreen()),
          ),
        ),
        SettingsValueTile(
          icon: Icons.view_week_outlined,
          title: 'Ordine delle sezioni',
          subtitle: 'Riordina Home, Diretta, Film e Serie TV',
          value: ui.startSection.label,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SectionLayoutScreen()),
          ),
        ),
        SettingsValueTile(
          icon: Icons.grid_view_outlined,
          title: 'Dimensione dei poster',
          value: _gridLabel(ui.gridSize),
          onTap: () async {
            final chosen = await pickOption<String>(
              context,
              title: 'Dimensione dei poster',
              options: UiSettings.gridSizes.keys.toList(),
              current: ui.gridSize,
              label: _gridLabel,
            );
            if (chosen != null) await ui.setGridSize(chosen);
          },
        ),
        SettingsSwitchTile(
          icon: Icons.image_outlined,
          title: 'Mostra anteprime',
          subtitle: 'Locandine e loghi nei cataloghi',
          value: ui.showPosters,
          onChanged: ui.setShowPosters,
        ),
        SettingsSwitchTile(
          icon: Icons.animation_outlined,
          title: 'Animazioni',
          subtitle: 'Transizioni ed effetti al tocco',
          value: ui.animations,
          onChanged: ui.setAnimations,
        ),
        SettingsSwitchTile(
          icon: Icons.view_agenda_outlined,
          title: 'Modalità compatta',
          subtitle: 'Righe più fitte per vedere più contenuti',
          value: ui.compact,
          onChanged: ui.setCompact,
        ),
      ],
    );
  }

  String _accentLabel(String key) => switch (key) {
    'arancio' => 'Arancione',
    'verde' => 'Verde',
    'azzurro' => 'Azzurro',
    'rosso' => 'Rosso',
    'giallo' => 'Giallo',
    'ciano' => 'Ciano',
    'rosa' => 'Rosa',
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
        'xtream' => 'Xtream Codes',
        _ => 'Non connesso',
      };

  Widget _buildPlaylistRefresh(BuildContext context, AppProvider provider) {
    final current = PlaylistRefreshInterval.fromMinutes(
      _refreshMinutes ?? _loadedRefreshMinutes,
    );
    return SettingsSection(
      title: 'Aggiornamento playlist',
      description:
          'Stato di Diretta, Film e Serie TV: tocca una sezione per ricaricare solo quella.',
      children: [
        if (provider.authMethod.name == 'xtream') const PlaylistStatusList(),
        if (provider.authMethod.name == 'xtream')
          SettingsValueTile(
            icon: Icons.sync_rounded,
            title: 'Aggiorna tutto ora',
            subtitle: provider.isRefreshingAny
                ? 'Aggiornamento in corso...'
                : 'Ricarica Diretta, Film e Serie TV insieme',
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
              ? 'La lista si aggiorna solo aprendo l\'app'
              : 'Ultimo aggiornamento: ${_lastRefreshLabel ?? 'in corso'}',
          value: current.label,
          onTap: () async {
            final chosen = await pickOption<PlaylistRefreshInterval>(
              context,
              title: 'Aggiorna la playlist ogni...',
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

    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsSection(
            title: 'Riproduzione',
            children: [
              SettingsValueTile(
                icon: Icons.play_circle_outline_rounded,
                title: 'Player video',
                subtitle:
                    'Motori, audio, sottotitoli, buffer, HDR e Picture-in-Picture',
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
                subtitle:
                    'Canali, film e serie XXX o "for adults" (nascosti di base)',
                value: provider.showAdult,
                onChanged: provider.setShowAdult,
              ),
            ],
          ),
          SettingsSection(
            title: 'Account',
            description:
                'Playlist, profili, cronologia e preferiti sincronizzati su tutti i dispositivi.',
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
            description:
                'Un profilo per ogni persona che usa l\'app. Il profilo scelto resta attivo al prossimo avvio.',
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
                  icon: Icons.badge_outlined,
                  title: 'Account playlist',
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
          const SettingsSection(
            title: 'Informazioni',
            children: [
              SettingsValueTile(
                icon: Icons.info_outline_rounded,
                title: 'Versione',
                value: '1.0.0',
              ),
              SettingsValueTile(
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
    await provider.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }
}
