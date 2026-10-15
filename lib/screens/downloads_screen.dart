import 'package:flutter/material.dart';
import '../widgets/apple_page_scaffold.dart';
import 'package:provider/provider.dart';

import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../services/device_type_service.dart';
import '../services/download_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tv_focusable.dart';

/// Offline library: queue, progress, pause/resume, playback and deletion.
/// TV: every row and every row action is a single remote focus stop.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return ApplePageScaffold(
      title: 'Download',
      body: ListenableBuilder(
        listenable: DownloadService.instance,
        builder: (context, _) {
          final s = DownloadService.instance;
          final items = s.items
              .where((i) => !app.kidsMode || app.isKidsContent(i.channel))
              .toList();
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nessun download. Apri un film o un episodio e scegli '
                  '"Scarica" per guardarlo senza connessione.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Spazio occupato: ${formatBytes(s.usedBytes)} · '
                  'i video restano solo su questo dispositivo',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              for (var i = 0; i < items.length; i++)
                _DownloadRow(
                  key: ValueKey(items[i].id),
                  item: items[i],
                  autofocus: i == 0,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  final DownloadItem item;
  final bool autofocus;
  const _DownloadRow({super.key, required this.item, required this.autofocus});

  String get _status {
    final p = item.progress;
    return switch (item.status) {
      DownloadStatus.queued => 'In coda',
      DownloadStatus.running =>
        p == null
            ? 'Download · ${formatBytes(item.received)}'
            : 'Download ${(p * 100).round()}% · '
                  '${formatBytes(item.received)} di ${formatBytes(item.total)}',
      DownloadStatus.paused => 'In pausa · ${formatBytes(item.received)}',
      DownloadStatus.failed => item.error ?? 'Errore',
      DownloadStatus.completed =>
        'Disponibile offline · ${formatBytes(item.received)}',
    };
  }

  Widget _action(IconData icon, String tip, VoidCallback onPressed) {
    final b = IconButton(tooltip: tip, onPressed: onPressed, icon: Icon(icon));
    if (!DeviceTypeService.isTv) return b;
    return TvFocusable(
      onPressed: onPressed,
      focusedScale: 1.0,
      borderRadius: BorderRadius.circular(24),
      child: b,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = DownloadService.instance;
    final done = item.status == DownloadStatus.completed;
    final active =
        item.status == DownloadStatus.running ||
        item.status == DownloadStatus.queued;
    final c = item.channel;
    final title = c.season != null && c.episode != null
        ? '${c.displaySeriesName} · S${c.season} E${c.episode}'
        : c.name;
    void play() => playChannel(context, c);
    // OK on the row: play when ready, otherwise pause/resume.
    void primary() {
      if (done) {
        play();
      } else if (active) {
        s.pause(item.id);
      } else {
        s.start(c);
      }
    }

    final info = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        done ? Icons.offline_pin_rounded : Icons.downloading_rounded,
        color: done ? AppColors.primary : AppColors.textSecondary,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_status, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (!done && item.progress != null) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: item.progress, minHeight: 3),
          ],
        ],
      ),
      onTap: done ? play : null,
    );
    final actions = <Widget>[
      if (done) _action(Icons.play_arrow_rounded, 'Riproduci', play),
      if (active) _action(Icons.pause_rounded, 'Pausa', () => s.pause(item.id)),
      if (item.status == DownloadStatus.paused ||
          item.status == DownloadStatus.failed)
        _action(Icons.play_arrow_rounded, 'Riprendi', () => s.start(c)),
      _action(Icons.delete_outline_rounded, 'Elimina', () => s.remove(item.id)),
    ];
    final Widget main = DeviceTypeService.isTv
        ? TvFocusable(
            autofocus: autofocus,
            focusedScale: 1.0,
            onPressed: primary,
            child: info,
          )
        : info;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: FocusTraversalGroup(
          child: Row(
            children: [
              Expanded(child: main),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
