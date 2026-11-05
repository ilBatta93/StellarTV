import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../models/content_type.dart';
import '../models/catalog_load_state.dart';
import '../models/source_access.dart';
import '../providers/history_provider.dart';
import '../providers/sync_provider.dart';
import '../services/portal_source.dart';
import '../services/settings_service.dart';
import '../services/xtream_edit.dart';
import '../widgets/apple_page_scaffold.dart';
import '../widgets/auth_scaffold.dart';
import '../services/key_handoff.dart';
import '../widgets/phone_handoff_panel.dart';
import '../widgets/recovery_key_entry.dart';
import '../widgets/source_access_form.dart';

class XtreamEditScreen extends StatefulWidget {
  const XtreamEditScreen({super.key});
  @override
  State<XtreamEditScreen> createState() => _XtreamEditScreenState();
}

class _XtreamEditScreenState extends State<XtreamEditScreen> {
  late final SourceAccessController _access;
  final _key = TextEditingController();
  final _keyFocus = FocusNode();
  final _keyPanel = GlobalKey<RecoveryKeyPanelState>();
  bool _busy = false;
  bool _phone = false;
  bool _askForKey = false;
  @override
  void initState() {
    super.initState();
    _access = SourceAccessController(
      SourceAccess.fromCredentials(
        context.read<AppProvider>().xtreamCredentials,
      ),
    );
  }

  @override
  void dispose() {
    _access.dispose();
    _key.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    if (_busy) return;
    final access = _access.access;
    final problem = access.problem;
    if (problem != null) {
      _notice(problem);
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
      final auth = await AppProvider.checkSource(access);
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
        persist: () async {
          await SettingsService().setXtreamCredentials(
            server: access.server,
            username: access.username,
            password: access.password,
            kind: access.kind.name,
          );
          PortalSession.reset();
        },
        sync: () => sync.pushNow(silent: true),
        reload: () => app.loadFromXtream(
          server: access.server,
          username: access.username,
          password: access.password,
          kind: access.kind,
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
                SourceAccessFields(
                  controller: _access,
                  nextFocus: _askForKey ? _keyFocus : null,
                  onSubmitted: _save,
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
                    // Edit mode: the phone sends only the fields to change.
                    PhoneHandoffPanel(
                      mode: 'e',
                      onReceived: (raw) {
                        final patch = SourceHandoff.parse(raw);
                        setState(() => _phone = false);
                        if (patch == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Dati ricevuti non validi. Riprova.',
                              ),
                            ),
                          );
                          return;
                        }
                        _access.apply(patch);
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
                        label: const Text('Modifica dal telefono'),
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
