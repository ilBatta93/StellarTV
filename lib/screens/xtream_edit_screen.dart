import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../models/content_type.dart';
import '../models/catalog_load_state.dart';
import '../providers/history_provider.dart';
import '../providers/sync_provider.dart';
import '../services/device_type_service.dart';
import '../services/settings_service.dart';
import '../services/xtream_service.dart';
import '../services/xtream_edit.dart';
import '../widgets/apple_page_scaffold.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/tv_text_field.dart';
import '../services/key_handoff.dart';
import '../widgets/phone_handoff_panel.dart';
import '../widgets/recovery_key_entry.dart';

class XtreamEditScreen extends StatefulWidget {
  const XtreamEditScreen({super.key});
  @override
  State<XtreamEditScreen> createState() => _XtreamEditScreenState();
}

class _XtreamEditScreenState extends State<XtreamEditScreen> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _key = TextEditingController();
  final _userFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _keyFocus = FocusNode();
  final _keyPanel = GlobalKey<RecoveryKeyPanelState>();
  bool _busy = false;
  bool _obscure = true;
  bool _phone = false;
  bool _askForKey = false;
  @override
  void initState() {
    super.initState();
    final credentials = context.read<AppProvider>().xtreamCredentials;
    _server.text = credentials?['server'] ?? '';
    _user.text = credentials?['username'] ?? '';
    _password.text = credentials?['password'] ?? '';
  }

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _password.dispose();
    _key.dispose();
    _userFocus.dispose();
    _passwordFocus.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    if (_busy) return;
    final server = _server.text.trim();
    final username = _user.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      _notice('Inserisci nome utente e password.');
      return;
    }
    final app = context.read<AppProvider>();
    final sync = context.read<SyncProvider>();
    if (app.isRefreshingAny) {
      _notice('Attendi il completamento dell’aggiornamento della lista.');
      return;
    }
    setState(() => _busy = true);
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await _keyPanel.currentState?.ready;
      if (!mounted) return;
      final auth = await XtreamService().authenticate(
        server: server,
        username: username,
        password: password,
      );
      if (!mounted) return;
      if (!auth.ok) {
        _notice(auth.message);
        return;
      }
      if (app.isRefreshingAny) {
        _notice('Attendi il completamento dell’aggiornamento della lista.');
        return;
      }
      final askForKey = _keyPanel.currentState?.askForKey ?? _askForKey;
      final proceed = !askForKey
          ? true
          : await acceptTypedRecoveryKey(
              context: context,
              sync: sync,
              history: context.read<HistoryProvider>(),
              typed: _key.text,
              askForKey: true,
              keyFocus: _keyFocus,
            );
      if (!proceed || !mounted) return;
      if (app.isRefreshingAny) {
        _notice('Attendi il completamento dell’aggiornamento della lista.');
        return;
      }
      final result = await saveXtreamEdit(
        authenticate: () async => true,
        persist: () => SettingsService().setXtreamCredentials(
          server: server,
          username: username,
          password: password,
        ),
        sync: () => sync.pushNow(silent: true),
        reload: () => app.loadFromXtream(
          server: server,
          username: username,
          password: password,
        ),
      );
      if (!mounted) return;
      if (!result.saved) {
        _notice('La lista precedente non è stata modificata.');
      } else {
        if (sync.isSignedIn && !result.synced) sync.schedulePush();
        final incomplete = [
          ContentType.live,
          ContentType.movie,
          ContentType.series,
        ].any((type) => app.catalogState(type).phase != CatalogLoadPhase.ready);
        _notice(
          incomplete
              ? 'Credenziali salvate. Alcune sezioni non sono disponibili: riprova il caricamento dalla lista.'
              : result.synced
              ? 'Lista aggiornata e salvata nel cloud.'
              : sync.isSignedIn
              ? 'Lista aggiornata sul dispositivo. Sincronizzazione cloud non riuscita: riprova da Backup e sincronizzazione.'
              : 'Lista aggiornata sul dispositivo. Accedi a un account per sincronizzarla nel cloud.',
        );
        Navigator.of(context).pop();
      }
    } catch (_) {
      _notice(
        'Aggiornamento non completato. Controlla la connessione e riprova.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final save = _busy ? null : _save;
    return PopScope(
      canPop: !_busy,
      child: ApplePageScaffold(
        title: 'Modifica connessione locale',
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: AbsorbPointer(
            absorbing: _busy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TvTextField(
                  autofocus: DeviceTypeService.isTv,
                  controller: _server,
                  nextFocus: _userFocus,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TvTextField(
                  controller: _user,
                  focusNode: _userFocus,
                  nextFocus: _passwordFocus,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nome utente',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                TvTextField(
                  controller: _password,
                  focusNode: _passwordFocus,
                  nextFocus: _askForKey ? _keyFocus : null,
                  obscureText: _obscure,
                  textInputAction: _askForKey
                      ? TextInputAction.next
                      : TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: AuthAction(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      child: IconButton(
                        tooltip: _obscure
                            ? 'Mostra password'
                            : 'Nascondi password',
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                RecoveryKeyPanel(
                  key: _keyPanel,
                  controller: _key,
                  focusNode: _keyFocus,
                  onSubmitted: (_) => _save(),
                  onVisibility: (visible) {
                    if (_askForKey == visible || !mounted) return;
                    setState(() => _askForKey = visible);
                  },
                ),
                if (context.watch<SyncProvider>().isSignedIn) ...[
                  const SizedBox(height: 16),
                  if (_phone)
                    PhoneHandoffPanel(
                      mode: 'x',
                      onReceived: (raw) {
                        final x = XtreamHandoff.parse(raw);
                        setState(() => _phone = false);
                        if (x == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Dati ricevuti non validi. Riprova.',
                              ),
                            ),
                          );
                          return;
                        }
                        _server.text = x.server;
                        _user.text = x.username;
                        _password.text = x.password;
                        _save();
                      },
                      onClose: (m) {
                        setState(() => _phone = false);
                        if (m != null) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(m)));
                        }
                      },
                    )
                  else
                    AuthAction(
                      onPressed: () => setState(() => _phone = true),
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _phone = true),
                        icon: const Icon(Icons.smartphone),
                        label: const Text('Inserisci dal telefono'),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                AuthAction(
                  onPressed: save,
                  child: FilledButton.icon(
                    onPressed: save,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_busy ? 'Aggiornamento...' : 'Salva modifiche'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
