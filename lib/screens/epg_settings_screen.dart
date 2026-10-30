import 'package:flutter/material.dart';

import '../widgets/apple_page_scaffold.dart';

import 'package:provider/provider.dart';

import '../providers/epg_provider.dart';
import '../services/playlist_refresh_service.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_tiles.dart';

/// Guide TV (EPG) settings: playlist guide, extra XMLTV sources, automatic
/// update interval and manual refresh.
class EpgSettingsScreen extends StatelessWidget {
  const EpgSettingsScreen({super.key});

  String _ago(DateTime? t) {
    if (t == null) return 'mai';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'adesso';
    if (d.inMinutes < 60) return '${d.inMinutes} min fa';
    if (d.inHours < 24) return '${d.inHours} h fa';
    return '${d.inDays} g fa';
  }

  Future<void> _addSource(BuildContext context, EpgProvider epg) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Aggiungi fonte EPG'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://.../guida.xml o .xml.gz',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Aggiungi'),
          ),
        ],
      ),
    );
    if (url == null) return;
    final clean = url.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inserisci un indirizzo che inizia con http'),
          ),
        );
      }
      return;
    }
    await epg.addSource(clean);
  }

  @override
  Widget build(BuildContext context) {
    final epg = context.watch<EpgProvider>();
    final interval = PlaylistRefreshInterval.fromMinutes(epg.intervalMinutes);
    return ApplePageScaffold(
      title: 'Guida TV (EPG)',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsSection(
            title: 'Stato',
            children: [
              SettingsValueTile(
                icon: Icons.event_note_rounded,
                title: epg.isLoading
                    ? 'Aggiornamento in corso...'
                    : epg.hasData
                    ? '${epg.channelCount} canali, ${epg.programmeCount} programmi'
                    : 'Nessuna guida caricata',
                subtitle:
                    epg.error ??
                    'Ultimo aggiornamento: ${_ago(epg.lastUpdate)}',
              ),
              SettingsValueTile(
                icon: Icons.refresh_rounded,
                title: 'Aggiorna ora',
                onTap: epg.isLoading ? null : epg.refresh,
              ),
            ],
          ),
          SettingsSection(
            title: 'Fonti',
            description: 'La guida disponibile viene usata in automatico.',
            children: [
              SettingsSwitchTile(
                icon: Icons.playlist_play_rounded,
                title: 'Guida disponibile',
                subtitle: epg.playlistSource == null
                    ? 'Non disponibile per questa connessione'
                    : 'Disponibile sul dispositivo',
                value: epg.usePlaylistGuide,
                onChanged: epg.setUsePlaylistGuide,
              ),
              for (final url in epg.manualSources)
                SettingsValueTile(
                  icon: Icons.link_rounded,
                  title: Uri.tryParse(url)?.host ?? url,
                  subtitle: url,
                  value: 'Rimuovi',
                  color: AppColors.error,
                  onTap: () => epg.removeSource(url),
                ),
              SettingsValueTile(
                icon: Icons.add_rounded,
                title: 'Aggiungi fonte',
                subtitle: 'Indirizzo XMLTV (.xml o .xml.gz)',
                onTap: () => _addSource(context, epg),
              ),
            ],
          ),
          SettingsSection(
            title: 'Aggiornamento automatico',
            children: [
              SettingsValueTile(
                icon: Icons.update_rounded,
                title: 'Frequenza aggiornamento',
                value: interval.label,
                onTap: () async {
                  final chosen = await pickOption<PlaylistRefreshInterval>(
                    context,
                    title: 'Aggiorna la guida ogni...',
                    options: PlaylistRefreshInterval.values,
                    current: interval,
                    label: (v) => v.label,
                  );
                  if (chosen != null) {
                    await epg.setIntervalMinutes(chosen.minutes);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
