import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/device_backup_policy.dart';
import '../services/backup_transfer.dart';
import '../services/device_backup.dart';
import '../services/device_type_service.dart';
import '../services/tv_pairing_service.dart';
import '../theme/app_theme.dart';
import '../widgets/apple_page_scaffold.dart';
import '../widgets/settings_tiles.dart';
import '../widgets/tv_focusable.dart';
import 'account_screen.dart';

/// Full backup of this device saved as a file on the phone, and restore
/// from that file, through the QR and the site's /backup page.
class DeviceBackupScreen extends StatefulWidget {
  const DeviceBackupScreen({super.key, this.restoreOnly = false});

  /// Opened from the first sign-in screen: only the restore, which works
  /// without an account. The phone that sends the backup also approves a
  /// session of this device's own (TV pairing): sessions are never copied.
  final bool restoreOnly;

  @override
  State<DeviceBackupScreen> createState() => _DeviceBackupScreenState();
}

class _DeviceBackupScreenState extends State<DeviceBackupScreen> {
  static const _seconds = 1200;

  BackupTransfer? _t;
  Timer? _poll;
  bool _busy = false;
  int _left = _seconds;
  String? _status;
  String? _result;
  bool _resultOk = false;

  /// Restore on a signed-out device: the pairing the phone approves.
  TvPairing? _pairing;

  /// Data being replaced: nothing may interrupt it.
  bool _applying = false;

  String get _link {
    final t = _t!, p = _pairing;
    return p == null ? t.link : '${t.link}&p=${Uri.encodeComponent(p.code)}';
  }

  bool get _signedIn => Supabase.instance.client.auth.currentUser != null;

  @override
  void initState() {
    super.initState();
    if (widget.restoreOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _begin(restore: true);
      });
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _stop() {
    _poll?.cancel();
    _poll = null;
    _t?.cancel();
    _t?.forget();
    _t = null;
    _pairing = null;
    _busy = false;
  }

  void _end(String message, {bool ok = false}) {
    if (!mounted) return;
    setState(() {
      _stop();
      _status = null;
      _result = message;
      _resultOk = ok;
    });
  }

  Future<void> _begin({required bool restore}) async {
    final t = BackupTransfer(Supabase.instance.client, restore: restore);
    setState(() {
      _result = null;
      _status = 'Creazione del codice…';
      _left = _seconds;
    });
    try {
      await t.start();
    } catch (_) {
      _end('Codice non creato. Verifica la connessione e riprova.');
      return;
    }
    // Not signed in yet: the phone will also sign this device in. Without the
    // pairing the restore still works, and the account is entered afterwards.
    TvPairing? pairing;
    if (restore && !_signedIn) {
      try {
        pairing = await TvPairingService(Supabase.instance.client).create();
      } catch (_) {}
    }
    if (!mounted) {
      t.cancel();
      return;
    }
    setState(() {
      _t = t;
      _pairing = pairing;
      _status = restore
          ? 'Sul telefono scegli il file di backup e la sua password.'
          : 'Sul telefono apri la pagina: il backup parte da solo.';
    });
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tick(t));
  }

  Future<void> _tick(BackupTransfer t) async {
    if (!mounted || _busy || _t != t) return;
    setState(() => _left -= 2);
    _busy = true;
    try {
      if (t.restore) {
        await _tickRestore(t);
      } else {
        await _tickSave(t);
      }
      if (_left <= 0 && _t == t) {
        _end('Codice scaduto. Generane uno nuovo.');
      }
    } catch (_) {
      if (_t == t) {
        _end(
          t.restore
              ? 'Ricezione non riuscita o codice scaduto. Riprova.'
              : 'Invio non riuscito o codice scaduto. Riprova.',
        );
      }
    } finally {
      _busy = false;
    }
  }

  bool _uploaded = false;

  Future<void> _tickSave(BackupTransfer t) async {
    if (_uploaded) {
      if (await t.taken()) {
        _uploaded = false;
        _end('Backup salvato sul telefono.', ok: true);
      }
      return;
    }
    final phone = await t.phoneKey();
    if (phone == null) return;
    setState(() => _status = 'Preparazione del backup…');
    final account = Supabase.instance.client.auth.currentUser?.id;
    final payload = await DeviceBackup.create(account: account);
    if (!mounted || _t != t) return;
    await t.upload(
      payload,
      phone,
      onProgress: (p) {
        if (mounted) {
          setState(() => _status = 'Invio al telefono… ${(p * 100).round()}%');
        }
      },
    );
    _uploaded = true;
    if (mounted) {
      setState(
        () => _status = 'Inviato. Sul telefono scegli la password e salva.',
      );
    }
  }

  Future<void> _tickRestore(BackupTransfer t) async {
    final payload = await t.receive(
      onProgress: (p) {
        if (mounted) {
          setState(() => _status = 'Ricezione… ${(p * 100).round()}%');
        }
      },
    );
    if (payload == null) return;
    _poll?.cancel();
    final summary = await DeviceBackup.inspect(payload);
    if (!mounted) return;
    if (summary == null) {
      _end('Il file ricevuto non è un backup di StellarTV valido.');
      return;
    }
    final confirmed = await _confirm(summary);
    if (!mounted) return;
    if (confirmed != true) {
      _end('Ripristino annullato: nessun dato è stato cambiato.');
      return;
    }
    setState(() => _applying = true);
    final token = await _pairingToken();
    if (!mounted) return;
    setState(() => _status = 'Ripristino in corso…');
    int failed;
    try {
      failed = await DeviceBackup.restore(payload);
    } catch (_) {
      setState(() => _applying = false);
      _end(
        'Ripristino non riuscito: il file potrebbe essere danneggiato. '
        'Nessun dato è stato cambiato.',
      );
      return;
    }
    var signedIn = _signedIn;
    if (token != null) {
      try {
        await TvPairingService(Supabase.instance.client)
            .completeWithToken(token);
        await AccountScreen.setGuest(false);
        signedIn = true;
      } catch (_) {}
    }
    final parts = [
      'Ripristino completato.',
      if (failed > 0) '$failed dati protetti non sono stati scritti.',
      if (!signedIn) 'Alla riapertura accedi al tuo account.',
      'L\'app si chiude: riaprila per usare i dati ripristinati.',
    ];
    _end(parts.join(' '), ok: true);
    await Future<void>.delayed(const Duration(seconds: 4));
    // Services still hold the old state in memory and would write it back.
    exit(0);
  }

  /// The magic-link token of the pairing the phone approved right after
  /// sending the backup; null when there is none or it does not arrive.
  Future<String?> _pairingToken() async {
    final pairing = _pairing;
    if (pairing == null) return null;
    setState(() => _status = 'Accesso all\'account del telefono…');
    final service = TvPairingService(Supabase.instance.client);
    for (var i = 0; i < 15 && mounted; i++) {
      try {
        final token = await service.pollToken(pairing);
        if (token != null) return token;
      } on PairingExpired {
        return null;
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  Future<bool?> _confirm(DeviceBackupSummary s) {
    final me = Supabase.instance.client.auth.currentUser?.id;
    final created = s.created?.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final when = created == null
        ? 'data sconosciuta'
        : '${two(created.day)}/${two(created.month)}/${created.year} '
              '${two(created.hour)}:${two(created.minute)}';
    final from = s.tv
        ? 'TV'
        : (s.platform.isEmpty ? 'dispositivo' : s.platform);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ripristinare questo backup?'),
        content: Text(
          'Backup del $when da $from${s.appVersion.isEmpty ? '' : ' (versione ${s.appVersion})'}.\n'
          '${s.prefs} impostazioni, ${s.secrets} dati protetti, ${s.files} file '
          '(${(s.bytes / 1048576).toStringAsFixed(1)} MB).\n\n'
          'Impostazioni, sorgente, profili e dati di questo dispositivo '
          'verranno sostituiti da quelli del backup. '
          '${me == null ? 'La TV accederà con l\'account del telefono.' : 'L\'accesso all\'account resta quello attuale.'}'
          '${s.account != null && me != null && s.account != me ? '\n\nAttenzione: il backup viene da un altro account.' : ''}',
        ),
        actions: [
          TvFocusable(
            onPressed: () => Navigator.pop(ctx, false),
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
          ),
          TvFocusable(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ripristina'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return PopScope(
      canPop: t == null && !_applying,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_applying) setState(_stop);
      },
      child: ApplePageScaffold(
        title: 'Backup sul telefono',
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SettingsSection(
              title: 'Come funziona',
              description:
                  'Il backup comprende impostazioni, aspetto, sorgente e '
                  'accessi, profili, preferiti, cronologia, PIN, VPN, chiavi '
                  'dei dati cifrati, catalogo e guida già scaricati. Restano '
                  'fuori i download e la sessione dell\'account: al '
                  'ripristino il telefono collega la TV con un accesso nuovo, '
                  'così il vecchio dispositivo resta collegato. Il backup '
                  'viaggia cifrato passando dal sito, che lo cancella appena '
                  'letto: il file resta solo sul telefono, protetto dalla '
                  'password che scegli.',
              children: const [],
            ),
            if (t != null)
              _panel(t)
            else
              SettingsSection(
                title: 'Scegli',
                children: [
                  if (!widget.restoreOnly)
                    SettingsValueTile(
                      icon: Icons.save_alt_rounded,
                      title: 'Salva un backup sul telefono',
                      subtitle: _signedIn
                          ? 'Scarica tutto questo dispositivo in un file'
                          : 'Serve l\'accesso all\'account StellarTV',
                      onTap: _status == null && _signedIn
                          ? () => _begin(restore: false)
                          : null,
                    ),
                  SettingsValueTile(
                    icon: Icons.settings_backup_restore_rounded,
                    title: 'Ripristina un backup dal telefono',
                    subtitle: 'Sostituisce i dati di questo dispositivo',
                    onTap: _status == null ? () => _begin(restore: true) : null,
                  ),
                ],
              ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                child: Row(
                  children: [
                    Icon(
                      _resultOk
                          ? Icons.check_circle_rounded
                          : Icons.info_outline_rounded,
                      size: 18,
                      color: _resultOk ? AppColors.success : AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_result!)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _panel(BackupTransfer t) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            color: scheme.onSurface,
            padding: const EdgeInsets.all(6),
            child: QrImageView(
              data: _link,
              size: 170,
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
                const Text(
                  'Inquadra il QR o apri stellartv.vercel.app/backup',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  t.code,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                  ),
                ),
                if (_status != null)
                  Text(_status!, style: const TextStyle(fontSize: 13)),
                Text(
                  'Scade tra ${(_left.clamp(0, _seconds) / 60).ceil()} min',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                // On a phone or tablet the page can open on this same device.
                if (!DeviceTypeService.isTv)
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(_link),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                    label: const Text('Apri la pagina su questo dispositivo'),
                  ),
                if (!_applying)
                  TvFocusable(
                    autofocus: true,
                    onPressed: () => _end('Operazione annullata.'),
                    child: OutlinedButton.icon(
                      onPressed: () => _end('Operazione annullata.'),
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
