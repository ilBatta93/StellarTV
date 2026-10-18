import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../widgets/phone_handoff_panel.dart';
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
  bool _phone = false;
  @override
  void dispose() {
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
    } catch (e) {
      if (mounted)
        setState(
          () => _status =
              'Operazione non riuscita. Verifica la chiave e la connessione. Nessun dato precedente è stato eliminato. (dettaglio: $e)',
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
    // The key is already proven by the restore above: a failed upload is a
    // warning, not a failed import.
    final pushed = await sync.pushNow(silent: true);
    if (!pushed && !await sync.hasCloudVault())
      throw StateError(sync.lastPushError ?? 'Salvataggio non verificato');
    await history.pullFromCloud();
    if (mounted)
      setState(
        () => _status = pushed
            ? 'Salvataggio cifrato verificato. Sincronizzazione attiva; copie precedenti conservate.'
            : 'Chiave importata e dati ripristinati. Invio al cloud non riuscito, riprova più tardi'
                '${sync.lastPushError == null ? '.' : ' (dettaglio: ${sync.lastPushError}).'}',
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
  void _fromPhone() => setState(() {
    _phone = !_phone;
    _status = '';
  });

  void _received(String key) {
    if (!mounted) return;
    setState(() {
      _phone = false;
      _input.text = key;
      _reveal = false;
      _generated = null;
    });
    _authorize();
  }

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
        if (_phone)
          PhoneHandoffPanel(
            onReceived: _received,
            onClose: (m) => setState(() {
              _phone = false;
              if (m != null) _status = m;
            }),
          ),
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
