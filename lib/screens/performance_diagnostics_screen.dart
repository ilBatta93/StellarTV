import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_type_service.dart';
import '../services/frame_telemetry_service.dart';
import '../widgets/apple_page_scaffold.dart';
import '../widgets/settings_tiles.dart';

class PerformanceDiagnosticsScreen extends StatefulWidget {
  const PerformanceDiagnosticsScreen({super.key});
  @override
  State<PerformanceDiagnosticsScreen> createState() =>
      _PerformanceDiagnosticsScreenState();
}

class _PerformanceDiagnosticsScreenState
    extends State<PerformanceDiagnosticsScreen> {
  final service = FrameTelemetryService.instance;
  bool busy = false;
  String? message;

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
      if (mounted) {
        setState(
          () => message =
              'Operazione non riuscita. Verifica la connessione e riprova.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Map<String, Object?> _report() => {
    ...service.report(),
    'deviceKind': DeviceTypeService.isTv ? 'tv' : 'mobile',
  };

  Future<void> upload({bool previous = false}) async {
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
          'report': previous ? service.previousReport : _report(),
        });
      },
      'Rapporto inviato. Lo trovi su stellartv.lovable.app → Il mio account → Log errori.',
    );
  }

  String _ms(double v) => '${v.toStringAsFixed(1)} ms';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: service,
    builder: (context, _) {
      final s = service.stats;
      return ApplePageScaffold(
        title: 'Prestazioni e fluidità',
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SettingsSection(
              title: 'Sessione di misura',
              children: [
                SettingsSwitchTile(
                  icon: Icons.speed_rounded,
                  title: 'Misura fluidità',
                  value: service.recording,
                  onChanged: (v) => v ? service.start() : service.stop(),
                  subtitle: 'Attivala, muoviti nell\'app con il telecomando e torna qui. Si ferma da sola dopo 10 minuti. Solo su questo dispositivo.',
                ),
                SettingsSwitchTile(
                  icon: Icons.rocket_launch_outlined,
                  title: 'Avvia insieme all\'app',
                  value: service.autoStartEnabled,
                  onChanged: (v) => service.setAutoStart(v),
                  subtitle: 'Al prossimo avvio la misura parte subito e registra anche il caricamento iniziale. Si ferma comunque dopo 10 minuti.',
                ),
                SettingsValueTile(
                  icon: Icons.restart_alt_rounded,
                  title: 'Azzera contatori',
                  onTap: service.reset,
                ),
              ],
            ),
            SettingsSection(
              title: 'Risultati',
              children: [
                ListTile(
                  title: const Text('FPS stimati'),
                  trailing: Text(s.fps.toStringAsFixed(0)),
                ),
                ListTile(
                  title: const Text('Fotogrammi misurati'),
                  trailing: Text('${s.frames}'),
                ),
                ListTile(
                  title: const Text('Fotogrammi lenti (oltre 16,6 ms)'),
                  trailing: Text(
                    '${s.jank} (${s.jankPercent.toStringAsFixed(1)}%)',
                  ),
                ),
                ListTile(
                  title: const Text('Tempo di calcolo medio'),
                  trailing: Text(_ms(s.avgBuildMs)),
                ),
                ListTile(
                  title: const Text('Tempo di disegno medio'),
                  trailing: Text(_ms(s.avgRasterMs)),
                ),
                ListTile(
                  title: const Text('Scatti da calcolo / da disegno'),
                  trailing: Text('${s.buildBound} / ${s.rasterBound}'),
                ),
                ListTile(
                  title: const Text('Blocchi oltre 100 ms'),
                  trailing: Text('${s.histogram[4] + s.histogram[5]}'),
                ),
                ListTile(
                  title: const Text('Picco massimo'),
                  subtitle: Text(
                    'Calcolo ${_ms(s.peakBuildUs / 1000)} · disegno ${_ms(s.peakRasterUs / 1000)}${s.peakContext == null ? '' : ' · ${s.peakContext}'}',
                  ),
                  trailing: Text(_ms(s.peakUs / 1000)),
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
                  onTap: busy || s.frames == 0 ? null : upload,
                ),
                if (!DeviceTypeService.isTv)
                  SettingsValueTile(
                    icon: Icons.ios_share_outlined,
                    title: 'Esporta file JSON',
                    onTap: busy || s.frames == 0
                        ? null
                        : () {
                            final box = context.findRenderObject();
                            final origin = box is RenderBox
                                ? box.localToGlobal(Offset.zero) & box.size
                                : null;
                            action(() async {
                              final dir = await getTemporaryDirectory();
                              final file = File(
                                '${dir.path}/StellarTV-prestazioni.json',
                              );
                              await file.writeAsString(
                                const JsonEncoder.withIndent('  ')
                                    .convert(_report()),
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
              ],
            ),
            if (service.previousReport case final previous?)
              SettingsSection(
                title: 'Sessione precedente',
                children: [
                  ListTile(
                    title: const Text('Ultima misura salvata sul dispositivo'),
                    subtitle: Text(
                      '${previous['sessionStartedAt'] ?? previous['createdAt'] ?? ''} · ${previous['frames'] ?? 0} fotogrammi',
                    ),
                  ),
                  SettingsValueTile(
                    icon: Icons.cloud_upload_outlined,
                    title: 'Invia sessione precedente al mio account',
                    onTap: busy ? null : () => upload(previous: true),
                  ),
                  if (!DeviceTypeService.isTv)
                    SettingsValueTile(
                      icon: Icons.ios_share_outlined,
                      title: 'Esporta sessione precedente',
                      onTap: busy
                          ? null
                          : () {
                              final box = context.findRenderObject();
                              final origin = box is RenderBox
                                  ? box.localToGlobal(Offset.zero) & box.size
                                  : null;
                              action(() async {
                                final dir = await getTemporaryDirectory();
                                final file = File(
                                  '${dir.path}/StellarTV-prestazioni-precedente.json',
                                );
                                await file.writeAsString(
                                  jsonEncode(previous),
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
                ],
              ),
            if (busy) const LinearProgressIndicator(),
            if (message != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(message ?? ''),
              ),
          ],
        ),
      );
    },
  );
}
