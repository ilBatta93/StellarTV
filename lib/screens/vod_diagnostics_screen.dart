import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_type_service.dart';
import '../services/vod_diagnostics_service.dart';
import '../widgets/apple_page_scaffold.dart';
import '../widgets/settings_tiles.dart';
import '../models/diagnostic_guide.dart';
import '../widgets/diagnostic_guide_section.dart';
import '../widgets/player/provider_check_button.dart';

class VodDiagnosticsScreen extends StatefulWidget {
  const VodDiagnosticsScreen({super.key});
  @override
  State<VodDiagnosticsScreen> createState() => _VodDiagnosticsScreenState();
}

class _VodDiagnosticsScreenState extends State<VodDiagnosticsScreen> {
  final service = VodDiagnosticsService.instance;
  bool busy = false;
  String? message;
  DiagnosticProblem? problem;

  @override
  void initState() {
    super.initState();
    unawaited(service.initialize());
  }

  Future<void> action(Future<void> Function() work, String success) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await work();
      if (mounted) setState(() => message = success);
    } catch (_) {
      if (mounted)
        setState(
          () => message =
              'Operazione non riuscita. Verifica la connessione e riprova.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> upload() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      setState(
        () => message =
            'Accedi al tuo account StellarTV per inviare il rapporto al sito.',
      );
      return;
    }
    await action(
      () async {
        await client.from('live_diagnostic_reports').insert({
          'user_id': user.id,
          'report': jsonDecode(
            guidedDiagnosticReport(await service.report(), problem),
          ),
        });
      },
      'Rapporto inviato. Lo trovi su stellartv.lovable.app → Il mio account → Log errori.',
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: service,
    builder: (context, _) => ApplePageScaffold(
      title: 'Diagnostica film e serie',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SettingsSection(
            title: 'Verifica servizio',
            children: [ProviderCheckButton()],
          ),
          DiagnosticGuideSection(
            selected: problem,
            onChanged: (value) => setState(() => problem = value),
          ),
          SettingsSection(
            title: 'Registrazione',
            children: [
              SettingsSwitchTile(
                icon: Icons.movie_filter_outlined,
                title: 'Diagnostica film e serie',
                value: service.enabled,
                onChanged: (v) => action(
                  () => service.setEnabled(v),
                  v ? 'Registrazione attiva' : 'Registrazione disattivata',
                ),
                subtitle: 'Solo su questo dispositivo. Rapporti con modello, sistema, versione app e dati del lettore; senza password o indirizzi IPTV.',
              ),
              ListTile(
                title: Text('${service.log.events.length} eventi salvati'),
                subtitle: const Text(
                  'Avvio, primo fotogramma, attese, fotogrammi scartati, buffer quasi vuoto, scatti e errori. Ultimi 1000 eventi.',
                ),
              ),
            ],
          ),
          SettingsSection(
            title: 'Rapporto',
            children: [
              SettingsValueTile(
                icon: Icons.cloud_upload_outlined,
                title: 'Invia al mio account',
                subtitle: 'Disponibile sul sito solo dopo il tuo invio, nel tuo account.',
                onTap: busy ? null : upload,
              ),
              if (!DeviceTypeService.isTv)
                SettingsValueTile(
                  icon: Icons.ios_share_outlined,
                  title: 'Esporta file JSON',
                  onTap: busy
                      ? null
                      : () {
                          final box = context.findRenderObject();
                          final origin = box is RenderBox
                              ? box.localToGlobal(Offset.zero) & box.size
                              : null;
                          action(() async {
                            final file = await service.exportFile();
                            if (problem != null)
                              await file.writeAsString(
                                guidedDiagnosticReport(
                                  await file.readAsString(),
                                  problem,
                                ),
                                flush: true,
                              );
                            await SharePlus.instance.share(
                              ShareParams(
                                files: [XFile(file.path)],
                                sharePositionOrigin: origin,
                              ),
                            );
                          }, 'Esportazione completata');
                        },
                ),
              SettingsValueTile(
                icon: Icons.delete_outline,
                title: 'Cancella dati locali',
                onTap: busy
                    ? null
                    : () async {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Cancellare gli eventi?'),
                            content: const Text(
                              'I rapporti già inviati al sito non saranno eliminati.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Annulla'),
                              ),
                              TextButton(
                                autofocus: true,
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Cancella'),
                              ),
                            ],
                          ),
                        );
                        if (yes == true)
                          await action(service.clear, 'Dati locali cancellati');
                      },
              ),
            ],
          ),
          if (busy) const LinearProgressIndicator(),
          if (message != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(message ?? ''),
            ),
          ...service.log.events.reversed
              .take(30)
              .map(
                (e) => ListTile(
                  title: Text('${e['type']}'),
                  subtitle: Text(
                    '${e['at']}\n${e['engine'] ?? ''} ${e['hwdec'] ?? ''} ${e['codec'] ?? ''} ${e['category'] ?? ''} ${e['droppedFrames'] ?? e['stallMs'] ?? e['jumpMs'] ?? e['cacheMs'] ?? e['avSyncMs'] ?? e['durationMs'] ?? e['startupMs'] ?? e['elapsedMs'] ?? ''} ',
                  ),
                  isThreeLine: true,
                ),
              ),
        ],
      ),
    ),
  );
}
