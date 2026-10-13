import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../services/device_type_service.dart';
import '../services/download_service.dart';
import '../theme/app_theme.dart';
import 'tv_focusable.dart';

/// Download control for a single film or episode. Hidden when the content
/// cannot be saved offline. On TV it is one focus stop activated with OK.
class DownloadButton extends StatelessWidget {
  final Channel channel;

  /// Full-width labelled button (title page) instead of a compact icon.
  final bool expanded;

  const DownloadButton({
    super.key,
    required this.channel,
    this.expanded = false,
  });

  void _onPressed(BuildContext context, DownloadItem? item) {
    final s = DownloadService.instance;
    switch (item?.status) {
      case null:
      case DownloadStatus.paused:
      case DownloadStatus.failed:
        s.start(channel);
        if (item == null) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text(
                'Download avviato: lo trovi in Impostazioni > Download',
              ),
            ),
          );
        }
      case DownloadStatus.queued:
      case DownloadStatus.running:
        s.pause(channel.id);
      case DownloadStatus.completed:
        _confirmDelete(context);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare il download?'),
        content: Text(channel.name),
        actions: [
          TvFocusable(
            autofocus: DeviceTypeService.isTv,
            onPressed: () => Navigator.pop(ctx, false),
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
          ),
          TvFocusable(
            onPressed: () => Navigator.pop(ctx, true),
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Elimina'),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await DownloadService.instance.remove(channel.id);
  }

  @override
  Widget build(BuildContext context) {
    if (!DownloadService.canDownload(channel)) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: DownloadService.instance,
      builder: (context, _) {
        final item = DownloadService.instance.itemFor(channel.id);
        final status = item?.status;
        final percent = ((item?.progress ?? 0) * 100).round();
        final (IconData icon, String label) = switch (status) {
          null => (Icons.download_rounded, 'Scarica'),
          DownloadStatus.queued => (Icons.schedule_rounded, 'In coda · pausa'),
          DownloadStatus.running => (
              Icons.pause_rounded,
              'Download $percent% · pausa',
            ),
          DownloadStatus.paused => (
              Icons.play_arrow_rounded,
              'Riprendi download',
            ),
          DownloadStatus.failed => (Icons.refresh_rounded, 'Riprova download'),
          DownloadStatus.completed => (
              Icons.download_done_rounded,
              'Scaricato · elimina',
            ),
        };
        final color = status == DownloadStatus.completed
            ? AppColors.primary
            : AppColors.textSecondary;
        void press() => _onPressed(context, item);
        final Widget button = expanded
            ? OutlinedButton.icon(
                onPressed: press,
                icon: Icon(icon, color: color),
                label: Text(label),
              )
            : IconButton(
                tooltip: label,
                onPressed: press,
                icon: status == DownloadStatus.running && item?.progress != null
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          value: item!.progress,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Icon(icon, color: color),
              );
        if (!DeviceTypeService.isTv) return button;
        return TvFocusable(
          onPressed: press,
          focusedScale: 1.0,
          borderRadius: BorderRadius.circular(expanded ? 12 : 24),
          child: button,
        );
      },
    );
  }
}
