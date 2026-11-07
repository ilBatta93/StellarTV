import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/trakt_provider.dart';
import '../services/service_keys.dart';
import '../services/trakt_client.dart';
import '../theme/app_theme.dart';
import '../widgets/apple_page_scaffold.dart';
import '../widgets/settings_tiles.dart';
import '../widgets/tv_focusable.dart';

/// Trakt link of the selected profile: connect with a code (TV) or QR,
/// sync state, "now watching", and the user's own Trakt app keys.
class TraktSettingsScreen extends StatefulWidget {
  const TraktSettingsScreen({super.key});

  @override
  State<TraktSettingsScreen> createState() => _TraktSettingsScreenState();
}

class _TraktSettingsScreenState extends State<TraktSettingsScreen> {
  bool _connecting = false;
  final _keys = ServiceKeys.instance;

  @override
  void initState() {
    super.initState();
    _keys.load();
  }

  String _when(DateTime? at) {
    if (at == null) return 'Mai';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'Adesso';
    if (d.inMinutes < 60) return '${d.inMinutes} min fa';
    if (d.inHours < 24) return '${d.inHours} h fa';
    return '${at.day}/${at.month} alle ${at.hour}:${at.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _disconnect(TraktProvider trakt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Scollegare Trakt?'),
        content: const Text(
          'La cronologia di StellarTV resta com\'è. Su Trakt restano i dati già '
          'inviati.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Scollega'),
          ),
        ],
      ),
    );
    if (ok == true) await trakt.disconnect();
  }

  Future<void> _editKeys(TraktProvider trakt) async {
    final id = TextEditingController(text: _keys.traktClientId);
    final secret = TextEditingController(text: _keys.traktClientSecret);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('La tua app Trakt'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Crea un\'app su trakt.tv (Impostazioni › Your API Apps) con '
                'redirect http://localhost e copia qui il Client ID. Il '
                'segreto serve solo per le app create prima di ottobre 2026. '
                'Lascia vuoto per usare l\'app di StellarTV.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: id,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Client ID'),
              ),
              TextField(
                controller: secret,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Client Secret (facoltativo)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    final newId = id.text.trim(), newSecret = secret.text.trim();
    id.dispose();
    secret.dispose();
    if (saved != true || !mounted) return;
    final changed =
        newId != _keys.traktClientId || newSecret != _keys.traktClientSecret;
    if (!changed) return;
    // A sign-in belongs to the Trakt app that issued it.
    if (trakt.connected) await trakt.disconnect();
    await _keys.setTrakt(newId, newSecret);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newId.isEmpty
              ? 'Torni all\'app Trakt di StellarTV: collega di nuovo Trakt'
              : 'Chiavi salvate: collega di nuovo Trakt',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trakt = context.watch<TraktProvider>();
    return ListenableBuilder(
      listenable: _keys,
      builder: (context, _) => PopScope(
        // Back closes the code panel first, then the screen.
        canPop: !_connecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _connecting) setState(() => _connecting = false);
        },
        child: ApplePageScaffold(
          title: 'Trakt',
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              SettingsSection(
                title: 'Account Trakt',
                description:
                    'Collega Trakt al profilo in uso: i contenuti visti e i '
                    'punti in cui ti sei fermato passano da StellarTV a Trakt '
                    'e viceversa. Ogni profilo collega il suo account. La '
                    'diretta non viene inviata.',
                children: [
                  if (!trakt.allowed)
                    const SettingsValueTile(
                      icon: Icons.child_care_rounded,
                      title: 'Non disponibile nel profilo bambino',
                    )
                  else if (trakt.connected) ...[
                    SettingsValueTile(
                      icon: Icons.verified_user_outlined,
                      title: 'Collegato',
                      value: trakt.user.isEmpty ? 'Trakt' : trakt.user,
                      subtitle: trakt.ownKeys
                          ? 'Con la tua app Trakt'
                          : 'Con l\'app Trakt di StellarTV',
                    ),
                    SettingsValueTile(
                      icon: Icons.sync_rounded,
                      title: trakt.syncing
                          ? 'Sincronizzazione in corso...'
                          : 'Sincronizza ora',
                      subtitle:
                          trakt.error ?? 'Ultima: ${_when(trakt.lastSync)}',
                      onTap: trakt.syncing
                          ? null
                          : () => trakt.sync(force: true),
                    ),
                    SettingsSwitchTile(
                      icon: Icons.play_circle_outline_rounded,
                      title: 'Mostra cosa stai guardando',
                      subtitle:
                          'Trakt vede il titolo in riproduzione e dove ti '
                          'fermi; a fine visione lo segna come visto',
                      value: trakt.scrobble,
                      onChanged: trakt.setScrobble,
                    ),
                    SettingsValueTile(
                      icon: Icons.link_off_rounded,
                      title: 'Scollega Trakt',
                      onTap: () => _disconnect(trakt),
                    ),
                  ] else if (_connecting)
                    _TraktCodePanel(
                      trakt: trakt,
                      onClose: (message) {
                        setState(() => _connecting = false);
                        if (message != null) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(message)));
                        }
                      },
                    )
                  else
                    SettingsValueTile(
                      icon: Icons.link_rounded,
                      title: 'Collega Trakt',
                      subtitle:
                          trakt.error ??
                          'Ti mostriamo un codice da confermare su trakt.tv',
                      onTap: TraktClient.available
                          ? () => setState(() => _connecting = true)
                          : null,
                    ),
                ],
              ),
              SettingsSection(
                title: 'Chiavi personali',
                description:
                    'Di base StellarTV usa la sua app Trakt. Puoi usare la tua, '
                    'per esempio se l\'app di StellarTV non risponde. Le chiavi '
                    'restano solo su questo dispositivo.',
                children: [
                  SettingsValueTile(
                    icon: Icons.key_rounded,
                    title: 'La tua app Trakt',
                    value: _keys.traktOwn ? 'In uso' : 'Spenta',
                    subtitle: _keys.traktOwn
                        ? 'Client ID ${_short(_keys.traktClientId)}'
                        : 'Inserisci il Client ID della tua app',
                    onTap: () => _editKeys(trakt),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _short(String id) => id.length <= 8
      ? id
      : '${id.substring(0, 4)}…${id.substring(id.length - 4)}';
}

/// Code and QR to approve on trakt.tv, polled until done.
class _TraktCodePanel extends StatefulWidget {
  const _TraktCodePanel({required this.trakt, required this.onClose});
  final TraktProvider trakt;
  final ValueChanged<String?> onClose;

  @override
  State<_TraktCodePanel> createState() => _TraktCodePanelState();
}

class _TraktCodePanelState extends State<_TraktCodePanel> {
  TraktDeviceCode? _code;
  Timer? _tick;
  Timer? _poll;
  int _left = 0;
  Duration _interval = const Duration(seconds: 5);
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final TraktDeviceCode code;
    try {
      code = await widget.trakt.startConnect();
    } on TraktException catch (e) {
      _finish(e.message);
      return;
    } catch (_) {
      _finish('Codice non creato. Verifica la connessione e riprova.');
      return;
    }
    if (!mounted || _done) return;
    setState(() {
      _code = code;
      _left = code.expiresIn.inSeconds;
      _interval = code.interval;
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _done) return;
      setState(() => _left--);
      if (_left <= 0) _finish('Codice scaduto. Generane uno nuovo.');
    });
    _schedule();
  }

  void _schedule() {
    _poll?.cancel();
    _poll = Timer(_interval, _check);
  }

  Future<void> _check() async {
    final code = _code;
    if (code == null || _done || !mounted) return;
    TraktPollState state;
    try {
      state = await widget.trakt.pollConnect(code);
    } catch (_) {
      state = TraktPollState.pending;
    }
    if (_done || !mounted) return;
    switch (state) {
      case TraktPollState.ok:
        _finish('Trakt collegato: sincronizzazione avviata');
      case TraktPollState.pending:
      case TraktPollState.error:
        _schedule();
      case TraktPollState.slowDown:
        _interval += const Duration(seconds: 5);
        _schedule();
      case TraktPollState.expired:
        _finish('Codice scaduto. Generane uno nuovo.');
      case TraktPollState.denied:
        _finish('Collegamento rifiutato su Trakt');
      case TraktPollState.invalid:
        _finish('Codice non valido. Generane uno nuovo.');
    }
  }

  void _finish(String? message) {
    if (_done) return;
    _done = true;
    _tick?.cancel();
    _poll?.cancel();
    widget.onClose(message);
  }

  @override
  void dispose() {
    _done = true;
    _tick?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    final scheme = Theme.of(context).colorScheme;
    if (code == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(),
      );
    }
    final host = code.verificationUrl.replaceFirst('https://', '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Container(
            color: scheme.onSurface,
            padding: const EdgeInsets.all(6),
            child: QrImageView(
              data: code.verificationUrl,
              size: 140,
              padding: EdgeInsets.zero,
              backgroundColor: scheme.onSurface,
              eyeStyle: QrEyeStyle(color: scheme.surface),
              dataModuleStyle: QrDataModuleStyle(color: scheme.surface),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inquadra il QR o apri $host e inserisci il codice',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  code.userCode,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                  ),
                ),
                Text(
                  'In attesa della conferma… ${_left.clamp(0, 9999)} s',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 6),
                TvFocusable(
                  autofocus: true,
                  onPressed: () => _finish(null),
                  child: OutlinedButton.icon(
                    onPressed: () => _finish(null),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Annulla'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
