import 'package:flutter/material.dart';
import '../widgets/apple_page_scaffold.dart';
import 'package:provider/provider.dart';

import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../services/device_type_service.dart';
import '../services/recording_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tv_focusable.dart';

/// Scheduled, running and finished live recordings.
/// TV: each row and each row action is one remote focus stop.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  @override
  void initState() {
    super.initState();
    RecordingService.instance.init();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return ApplePageScaffold(
      title: 'Registrazioni',
      body: ListenableBuilder(
        listenable: RecordingService.instance,
        builder: (context, _) {
          final s = RecordingService.instance;
          final items = s.items
              .where((i) => !app.kidsMode || app.isKidsContent(i.channel))
              .toList();
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nessuna registrazione. Durante una diretta scegli '
                  '"Registra", oppure apri la guida di un canale e premi OK '
                  'su un programma futuro per programmarlo.',
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
                  'Spazio occupato: ${formatRecordingBytes(s.usedBytes)} · '
                  'le registrazioni restano su questo dispositivo e '
                  'proseguono solo con l\'app aperta',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              for (var i = 0; i < items.length; i++)
                _RecordingRow(
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

String _two(int v) => v.toString().padLeft(2, '0');
String _when(DateTime d) =>
    '${_two(d.day)}/${_two(d.month)} ${_two(d.hour)}:${_two(d.minute)}';

class _RecordingRow extends StatelessWidget {
  final RecordingItem item;
  final bool autofocus;
  const _RecordingRow({super.key, required this.item, required this.autofocus});

  String get _status => switch (item.status) {
    RecordingStatus.scheduled =>
      'Programmata · ${_when(item.start)} – ${_two(item.end.hour)}:${_two(item.end.minute)}',
    RecordingStatus.recording =>
      'In registrazione · ${formatRecordingBytes(item.bytes)} · fino alle '
          '${_two(item.end.hour)}:${_two(item.end.minute)}',
    RecordingStatus.completed =>
      'Registrata ${_when(item.start)} · ${formatRecordingBytes(item.bytes)}',
    RecordingStatus.failed => item.error ?? 'Registrazione non riuscita',
    RecordingStatus.cancelled => 'Annullata',
  };

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
    final s = RecordingService.instance;
    final done = item.status == RecordingStatus.completed;
    final running = item.status == RecordingStatus.recording;
    final scheduled = item.status == RecordingStatus.scheduled;
    void play() => playChannel(context, s.playable(item));
    void primary() {
      if (done || (running && item.bytes > 0)) {
        play();
      } else if (running || scheduled) {
        s.stop(item.id);
      }
    }

    final info = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        running
            ? Icons.fiber_manual_record_rounded
            : scheduled
            ? Icons.schedule_rounded
            : done
            ? Icons.video_library_rounded
            : Icons.error_outline_rounded,
        color: running ? AppColors.error : AppColors.textSecondary,
      ),
      title: Text(
        '${item.title} · ${item.channel.name}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(_status, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: done ? play : null,
    );
    final actions = <Widget>[
      if (done) _action(Icons.play_arrow_rounded, 'Riproduci', play),
      if (running)
        _action(
          Icons.stop_rounded,
          'Ferma registrazione',
          () => s.stop(item.id),
        ),
      if (scheduled)
        _action(Icons.close_rounded, 'Annulla', () => s.stop(item.id)),
      if (!scheduled)
        _action(
          Icons.delete_outline_rounded,
          'Elimina',
          () => s.remove(item.id),
        ),
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
