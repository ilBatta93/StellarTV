import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/key_handoff.dart';
import '../providers/sync_provider.dart';
import '../providers/history_provider.dart';
import '../services/personal_vault.dart';
import '../widgets/apple_page_scaffold.dart';
import '../widgets/tv_text_field.dart';
import '../widgets/tv_focusable.dart';

class PersonalVaultScreen extends StatefulWidget {
  const PersonalVaultScreen({super.key});
  @override
  State<PersonalVaultScreen> createState() => _PersonalVaultScreenState();
}

class _PersonalVaultScreenState extends State<PersonalVaultScreen> {
  final _input = TextEditingController();
  bool _busy = false, _saved = false, _reveal = false;
  String? _generated;
  String _status = '';
  KeyHandoff? _handoff;
  Timer? _poll;
  int _left = 0;
  @override
  void dispose() {
    _stopPhone();
    _input.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      await action();
    } catch (_) {
      if (mounted)
        setState(
          () => _status =
              'Operazione non riuscita. Verifica la chiave e la connessione. Nessun dato precedente è stato eliminato.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() => _run(() async {
    if (await context.read<SyncProvider>().hasCloudVault()) {
      if (mounted)
        setState(
          () => _status =
              'Esiste già un salvataggio: importa la chiave del dispositivo autorizzato.',
        );
      return;
    }
    final key = PersonalVault.generateKey();
    if (mounted)
      setState(() {
        _generated = key;
        _input.text = key;
        _reveal = true;
        _saved = false;
      });
  });
  Future<void> _authorize() => _run(() async {
    final sync = context.read<SyncProvider>();
    final history = context.read<HistoryProvider>();
    await sync.authorizeVault(_input.text.trim());
    // Merge existing ciphertext before publishing the device copy.
    if (await sync.hasCloudVault() && !await history.pullFromCloud())
      throw StateError('Ripristino non riuscito');
    if (!await sync.pushNow(silent: true))
      throw StateError('Salvataggio non verificato');
    if (!await history.pullFromCloud())
      throw StateError('Ripristino non riuscito');
    if (mounted)
      setState(
        () => _status =
            'Salvataggio cifrato verificato. Sincronizzazione attiva; copie precedenti conservate.',
      );
  });
  Future<void> _show() => _run(() async {
    final key = await context.read<SyncProvider>().recoveryKey();
    if (mounted)
      setState(() {
        _input.text = key ?? '';
        _reveal = key != null;
        _status = key == null
            ? 'Importa una chiave o creane una se non esiste un salvataggio.'
            : '';
      });
  });
  void _stopPhone() {
    _poll?.cancel();
    _poll = null;
    _handoff?.cancel();
    _handoff?.forget();
    _handoff = null;
  }

  Future<void> _fromPhone() async {
    _stopPhone();
    final handoff = KeyHandoff(Supabase.instance.client);
    try {
      await handoff.start();
    } catch (_) {
      if (mounted) setState(() => _status = 'Codice non creato. Verifica la connessione e riprova.');
      return;
    }
    if (!mounted) return handoff.cancel();
    setState(() {
      _handoff = handoff;
      _left = 120;
      _status = '';
    });
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _handoff != handoff) return;
      setState(() => _left -= 2);
      try {
        final key = await handoff.poll();
        if (key == null) {
          if (_left <= 0) throw TimeoutException('scaduto');
          return;
        }
        _stopPhone();
        if (!mounted) return;
        setState(() {
          _input.text = key;
          _reveal = false;
          _generated = null;
        });
        _authorize();
      } catch (_) {
        _stopPhone();
        if (mounted) setState(() => _status = 'Codice scaduto o non valido. Generane uno nuovo.');
      }
    });
  }

  Widget _phonePanel(KeyHandoff h) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      children: [
        const Text('Inquadra il QR col telefono, oppure apri stellartv.lovable.app/chiave e inserisci il codice.', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        SizedBox(
          width: 220,
          height: 220,
          child: QrImageView(
            data: h.link,
            size: 220,
            backgroundColor: Theme.of(context).colorScheme.onSurface,
            eyeStyle: QrEyeStyle(color: Theme.of(context).colorScheme.surface),
            dataModuleStyle: QrDataModuleStyle(color: Theme.of(context).colorScheme.surface),
          ),
        ),
        const SizedBox(height: 12),
        Text(h.code, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: 8)),
        Text('In attesa del telefono… ${_left.clamp(0, 120)} s'),
        _action('Annulla', Icons.close, () => setState(_stopPhone)),
      ],
    ),
  );

  Widget _action(String label, IconData icon, VoidCallback action) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: TvFocusable(
      onPressed: () {
        if (!_busy) action();
      },
      child: FilledButton.icon(
        onPressed: _busy ? null : action,
        icon: Icon(icon),
        label: Text(label),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => ApplePageScaffold(
    title: 'Dati cifrati',
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Chiave di recupero',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const Text(
          'Conservala fuori dal cloud. Chi vede questa chiave può leggere i dati cifrati del tuo account. Se perdi la chiave e tutti i dispositivi autorizzati, i dati non sono recuperabili. La configurazione dei contenuti resta solo sul dispositivo.',
        ),
        const SizedBox(height: 16),
        TvTextField(
          controller: _input,
          obscureText: !_reveal,
          decoration: const InputDecoration(
            labelText: 'Chiave STV1',
            border: OutlineInputBorder(),
          ),
        ),
        _action('Invia la chiave dal telefono', Icons.smartphone, _fromPhone),
        if (_handoff != null) _phonePanel(_handoff!),
        _action('Importa e sincronizza', Icons.lock_outline, () {
          if (_generated != null && !_saved) {
            setState(
              () => _status = 'Conserva prima la chiave fuori dal cloud.',
            );
            return;
          }
          _authorize();
        }),
        _action('Crea nuova chiave', Icons.key, _create),
        if (_generated != null)
          TvFocusable(
            onPressed: () => setState(() => _saved = !_saved),
            child: CheckboxListTile(
              value: _saved,
              onChanged: (v) => setState(() => _saved = v ?? false),
              title: const Text('Ho conservato la chiave fuori dal cloud'),
            ),
          ),
        _action('Mostra chiave e QR', Icons.qr_code, _show),
        if (_reveal && _input.text.isNotEmpty) ...[
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              width: 220,
              height: 220,
              child: QrImageView(
                data: _input.text,
                size: 220,
                backgroundColor: Theme.of(context).colorScheme.onSurface,
                eyeStyle: QrEyeStyle(
                  color: Theme.of(context).colorScheme.surface,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  color: Theme.of(context).colorScheme.surface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            _input.text,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          _action(
            'Nascondi chiave',
            Icons.visibility_off,
            () => setState(() => _reveal = false),
          ),
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_status),
          ),
      ],
    ),
  );
}
