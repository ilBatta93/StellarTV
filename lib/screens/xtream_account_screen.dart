import 'package:flutter/material.dart';

import '../widgets/apple_page_scaffold.dart';

import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/device_type_service.dart';
import '../services/expiry_reminder_service.dart';
import '../services/xtream_service.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_tiles.dart';
import '../widgets/tv_focusable.dart';

/// Details of the Xtream subscription as reported by the provider
/// (expiry, status, connections, server info). Read-only.
class XtreamAccountScreen extends StatefulWidget {
  const XtreamAccountScreen({super.key});

  @override
  State<XtreamAccountScreen> createState() => _XtreamAccountScreenState();
}

class _XtreamAccountScreenState extends State<XtreamAccountScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() {
    final c = context.read<AppProvider>().xtreamCredentials;
    if (c == null) {
      return Future.error(
        Exception('Nessuna configurazione locale collegata.'),
      );
    }
    return XtreamService()
        .accountInfo(
          server: c['server']!,
          username: c['username']!,
          password: c['password']!,
        )
        .then((info) {
          ExpiryReminderService.instance.applyAccountInfo(
            '${c['server']}|${c['username']}',
            info,
          );
          return info;
        });
  }

  static String _date(Object? unix) {
    final n = int.tryParse('${unix ?? ''}');
    if (n == null || n <= 0) return 'Illimitata';
    final d = DateTime.fromMillisecondsSinceEpoch(n * 1000);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  static String? _daysLeft(Object? unix) {
    final n = int.tryParse('${unix ?? ''}');
    if (n == null || n <= 0) return null;
    final left = DateTime.fromMillisecondsSinceEpoch(n * 1000)
        .difference(DateTime.now());
    if (left.isNegative) return 'Scaduto';
    return left.inDays == 0 ? 'Scade oggi' : 'Mancano ${left.inDays} giorni';
  }

  static String _status(Object? v) => switch ('${v ?? ''}'.toLowerCase()) {
    'active' => 'Attivo',
    'expired' => 'Scaduto',
    'banned' => 'Bloccato',
    'disabled' => 'Disattivato',
    '' => 'Non indicato',
    final other => other,
  };

  static String _bool(Object? v) =>
      '${v ?? ''}' == '1' || v == true ? 'Sì' : 'No';

  static String _text(Object? v) {
    if (v == null) return 'Non indicato';
    if (v is List) return v.isEmpty ? 'Non indicato' : v.join(', ');
    final s = '$v'.trim();
    return s.isEmpty ? 'Non indicato' : s;
  }

  Widget _row(IconData icon, String title, String value, {Color? color}) {
    final tile = ListTile(
      leading: Icon(icon, color: color ?? AppColors.textSecondary),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(
        value,
        style: TextStyle(color: color ?? AppColors.textSecondary),
      ),
    );
    if (!DeviceTypeService.isTv) return tile;
    // Focus stop so the remote can scroll through every detail.
    return TvFocusable(
      onPressed: () {},
      focusedScale: 1,
      borderRadius: BorderRadius.circular(12),
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ApplePageScaffold(
      title: 'Connessione locale',
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${snap.error}'.replaceFirst('Exception: ', ''),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      autofocus: DeviceTypeService.isTv,
                      onPressed: () => setState(() => _future = _load()),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Riprova'),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snap.data!;
          final u = Map<String, dynamic>.from(data['user_info'] as Map);
          final srv = data['server_info'] is Map
              ? Map<String, dynamic>.from(data['server_info'] as Map)
              : <String, dynamic>{};
          final left = _daysLeft(u['exp_date']);
          final expired = left == 'Scaduto';
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              SettingsSection(
                title: 'Accesso',
                children: [
                  _row(
                    Icons.verified_user_outlined,
                    'Stato',
                    _status(u['status']),
                    color: '${u['status']}'.toLowerCase() == 'active'
                        ? null
                        : AppColors.error,
                  ),
                  _row(
                    Icons.event_outlined,
                    'Scadenza',
                    left == null
                        ? _date(u['exp_date'])
                        : '${_date(u['exp_date'])} · $left',
                    color: expired ? AppColors.error : null,
                  ),
                  _row(
                    Icons.today_outlined,
                    'Attivato il',
                    _date(u['created_at']),
                  ),
                  _row(Icons.science_outlined, 'Prova', _bool(u['is_trial'])),
                  _row(
                    Icons.devices_outlined,
                    'Connessioni',
                    '${_text(u['active_cons'])} attive su '
                        '${_text(u['max_connections'])} consentite',
                  ),
                  _row(
                    Icons.movie_filter_outlined,
                    'Formati consentiti',
                    _text(u['allowed_output_formats']),
                  ),
                  _row(Icons.person_outline, 'Utente', _text(u['username'])),
                  if (u['message'] != null && '${u['message']}'.isNotEmpty)
                    _row(
                      Icons.campaign_outlined,
                      'Messaggio della sorgente',
                      _text(u['message']),
                    ),
                ],
              ),
              if (srv.isNotEmpty)
                SettingsSection(
                  title: 'Server',
                  children: [
                    _row(Icons.dns_outlined, 'Indirizzo', _text(srv['url'])),
                    _row(
                      Icons.lan_outlined,
                      'Porte',
                      'HTTP ${_text(srv['port'])} · HTTPS '
                          '${_text(srv['https_port'])}',
                    ),
                    _row(
                      Icons.http_outlined,
                      'Protocollo',
                      _text(srv['server_protocol']),
                    ),
                    _row(
                      Icons.public_outlined,
                      'Fuso orario',
                      _text(srv['timezone']),
                    ),
                    _row(
                      Icons.schedule_outlined,
                      'Ora del server',
                      _text(srv['time_now']),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
