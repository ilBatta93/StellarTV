import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vpn_config_policy.dart';
import '../providers/sync_provider.dart';
import '../services/vpn_service.dart';
import '../theme/app_theme.dart';
import '../widgets/apple_page_scaffold.dart';
import '../widgets/phone_handoff_panel.dart';
import '../widgets/settings_tiles.dart';

/// Optional personal VPN (WireGuard): NordVPN with an access key, or any
/// WireGuard configuration. Reachable from settings and from both logins.
class VpnSettingsScreen extends StatefulWidget {
  const VpnSettingsScreen({super.key});

  @override
  State<VpnSettingsScreen> createState() => _VpnSettingsScreenState();
}

class _VpnSettingsScreenState extends State<VpnSettingsScreen> {
  final _vpn = VpnService.instance;
  bool _busy = false;
  bool _checking = false;
  bool _phone = false;
  String? _checkResult;
  Map<String, int>? _stats;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_vpn.state != VpnState.connected) {
      if (_stats != null && mounted) setState(() => _stats = null);
      return;
    }
    final s = await _vpn.stats();
    if (mounted) setState(() => _stats = s);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on VpnSetupException catch (e) {
      _show(e.message, error: true);
    } on FormatException catch (e) {
      _show(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.error : AppColors.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<String?> _askText({
    required String title,
    required String hint,
    String? help,
    bool multiline = false,
  }) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (help != null) ...[
                Text(
                  help,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                minLines: multiline ? 6 : 1,
                maxLines: multiline ? 12 : 1,
                keyboardType: multiline
                    ? TextInputType.multiline
                    : TextInputType.visiblePassword,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(hintText: hint),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Continua'),
          ),
        ],
      ),
    );
    controller.dispose();
    final value = text?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// `0` means "best server anywhere"; `null` the user went back.
  Future<int?> _pickCountry() async {
    List<NordCountry> countries;
    try {
      countries = await _vpn.nordCountries();
    } on VpnSetupException catch (e) {
      _show(e.message, error: true);
      return null;
    }
    if (!mounted) return null;
    final byId = {for (final c in countries) c.id: c};
    // Italy first: the most likely choice for the user's own country.
    final italy = countries.where((c) => c.code == 'IT').map((c) => c.id);
    final options = [
      0,
      ...italy,
      for (final c in countries)
        if (c.code != 'IT') c.id,
    ];
    return pickOption<int>(
      context,
      title: 'Paese del server VPN',
      options: options,
      current: _vpn.countryId ?? 0,
      label: (id) =>
          id == 0 ? 'Automatico (il più veloce)' : byId[id]?.name ?? '$id',
    );
  }

  Future<void> _setupNord() async {
    final key = await _askText(
      title: 'Accesso NordVPN',
      hint: 'Token di accesso (64 caratteri)',
      help:
          'Su my.nordaccount.com apri NordVPN › Configura NordVPN '
          'manualmente › Genera nuovo token, poi incollalo qui. Serve '
          'solo ora per leggere la chiave WireGuard: non viene salvato.',
    );
    if (key == null || !mounted) return;
    final country = await _pickCountry();
    if (country == null || !mounted) return;
    await _run(() async {
      await _vpn.setupNord(key, countryId: country == 0 ? null : country);
      if (!_vpn.enabled) await _vpn.setEnabled(true);
      _afterConnect();
    });
  }

  Future<void> _changeCountry() async {
    final country = await _pickCountry();
    if (country == null || !mounted) return;
    await _run(() async {
      await _vpn.changeNordCountry(country == 0 ? null : country);
      _afterConnect();
    });
  }

  /// The phone channel needs a StellarTV account on this device: the
  /// one-time code row belongs to it.
  bool _signedIn(BuildContext context) {
    try {
      return context.watch<SyncProvider>().isSignedIn;
    } on ProviderNotFoundException {
      return false;
    }
  }

  Future<void> _fromPhone(String raw) async {
    setState(() => _phone = false);
    VpnHandoff? data;
    try {
      data = VpnConfigPolicy.handoff(jsonDecode(raw));
    } catch (_) {}
    if (data == null) {
      _show('Dati ricevuti non validi. Riprova.', error: true);
      return;
    }
    final nordKey = data.nordKey;
    final config = data.config;
    if (nordKey != null) {
      final country = await _pickCountry();
      if (country == null || !mounted) return;
      await _run(() async {
        await _vpn.setupNord(nordKey, countryId: country == 0 ? null : country);
        if (!_vpn.enabled) await _vpn.setEnabled(true);
        _afterConnect();
      });
    } else if (config != null) {
      await _run(() async {
        await _vpn.saveFile(config);
        if (!_vpn.enabled) await _vpn.setEnabled(true);
        _afterConnect();
      });
    }
  }

  Future<void> _importFile() async {
    final text = await _askText(
      title: 'Configurazione WireGuard',
      hint: '[Interface]\nPrivateKey = ...\nAddress = ...\n\n[Peer]\n...',
      help:
          'Incolla il contenuto del file .conf fornito dal tuo servizio '
          'VPN (sezioni [Interface] e [Peer]).',
      multiline: true,
    );
    if (text == null || !mounted) return;
    await _run(() async {
      await _vpn.saveFile(text);
      if (!_vpn.enabled) await _vpn.setEnabled(true);
      _afterConnect();
    });
  }

  void _afterConnect() {
    if (_vpn.state == VpnState.connected) {
      _show('VPN attiva: ${_vpn.label ?? ''}');
    } else if (_vpn.problem != null) {
      _show(_vpn.problem!, error: true);
    }
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _checkResult = null;
    });
    final r = await _vpn.checkAddress();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checkResult = r == null
          ? 'Verifica non riuscita'
          : '${r.ip} · ${r.place}'
                '${r.protected ? ' · protetto da NordVPN' : ''}';
    });
  }

  Future<void> _forget() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Rimuovere la VPN?'),
        content: const Text(
          'La connessione si chiude e la configurazione viene cancellata '
          'da questo dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(_vpn.forget);
  }

  String _stateText() => switch (_vpn.state) {
    VpnState.connected => 'Connessa',
    VpnState.connecting => 'Connessione...',
    VpnState.error => 'Non connessa',
    VpnState.off => 'Spenta',
  };

  static String _bytes(int b) {
    if (b < 1 << 20) return '${(b / 1024).toStringAsFixed(0)} KB';
    if (b < 1 << 30) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vpn,
      builder: (context, _) {
        final stats = _stats;
        final nord = _vpn.source == VpnService.sourceNord;
        return ApplePageScaffold(
          title: 'VPN',
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (!VpnService.supported)
                const SettingsSection(
                  title: 'VPN personale',
                  children: [
                    SettingsValueTile(
                      icon: Icons.info_outline_rounded,
                      title: 'Disponibile su Android e Android TV',
                      subtitle:
                          'Su questo dispositivo usa l\'app del tuo servizio '
                          'VPN.',
                    ),
                  ],
                )
              else ...[
                SettingsSection(
                  title: 'VPN personale',
                  description:
                      'Facoltativa. Usa il tuo servizio VPN (NordVPN o '
                      'qualsiasi servizio WireGuard). Se è attiva, StellarTV '
                      'si connette alla VPN all\'avvio, prima dell\'accesso. '
                      'La configurazione resta solo su questo dispositivo.',
                  children: [
                    if (_vpn.configured) ...[
                      SettingsSwitchTile(
                        icon: Icons.vpn_lock_rounded,
                        title: 'Usa la VPN',
                        subtitle: _vpn.label,
                        value: _vpn.enabled,
                        onChanged: (v) => _run(() async {
                          await _vpn.setEnabled(v);
                          if (v) _afterConnect();
                        }),
                      ),
                      SettingsValueTile(
                        icon: _vpn.state == VpnState.connected
                            ? Icons.verified_user_outlined
                            : Icons.shield_outlined,
                        title: 'Stato',
                        value: _busy ? 'Attendi...' : _stateText(),
                        subtitle:
                            _vpn.problem ??
                            (stats == null
                                ? null
                                : 'Ricevuti ${_bytes(stats['rx'] ?? 0)} · '
                                      'inviati ${_bytes(stats['tx'] ?? 0)}'),
                        onTap: _busy || !_vpn.enabled
                            ? null
                            : () => _run(() async {
                                await _vpn.connect();
                                _afterConnect();
                              }),
                      ),
                      SettingsValueTile(
                        icon: Icons.travel_explore_rounded,
                        title: _checking
                            ? 'Verifica in corso...'
                            : 'Verifica indirizzo',
                        subtitle:
                            _checkResult ?? 'Mostra da dove ti vedono i server',
                        onTap: _checking ? null : _check,
                      ),
                    ] else
                      const SettingsValueTile(
                        icon: Icons.vpn_lock_outlined,
                        title: 'Nessuna VPN configurata',
                        subtitle: 'Scegli sotto come configurarla',
                      ),
                  ],
                ),
                SettingsSection(
                  title: 'Configurazione',
                  children: [
                    if (_phone)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: PhoneHandoffPanel(
                          mode: 'v',
                          onReceived: _fromPhone,
                          onClose: (m) {
                            setState(() => _phone = false);
                            if (m != null) _show(m, error: true);
                          },
                        ),
                      )
                    else if (_signedIn(context))
                      SettingsValueTile(
                        icon: Icons.smartphone_rounded,
                        title: 'Inserisci dal telefono',
                        subtitle:
                            'Token NordVPN o configurazione WireGuard, '
                            'inviati cifrati dal telefono',
                        onTap: _busy
                            ? null
                            : () => setState(() => _phone = true),
                      )
                    else
                      const SettingsValueTile(
                        icon: Icons.smartphone_rounded,
                        title: 'Inserisci dal telefono',
                        subtitle:
                            'Disponibile dopo l\'accesso all\'account '
                            'StellarTV su questo dispositivo',
                      ),
                    SettingsValueTile(
                      icon: Icons.key_rounded,
                      title: nord
                          ? 'Nuovo token NordVPN'
                          : 'Configura con NordVPN',
                      subtitle: 'Con il token di accesso del tuo account',
                      onTap: _busy ? null : _setupNord,
                    ),
                    if (nord)
                      SettingsValueTile(
                        icon: Icons.public_rounded,
                        title: 'Cambia paese o server',
                        subtitle: _vpn.label,
                        onTap: _busy ? null : _changeCountry,
                      ),
                    SettingsValueTile(
                      icon: Icons.description_outlined,
                      title: 'Incolla configurazione WireGuard',
                      subtitle: 'Per altri servizi VPN (file .conf)',
                      onTap: _busy ? null : _importFile,
                    ),
                    if (_vpn.configured)
                      SettingsValueTile(
                        icon: Icons.delete_outline_rounded,
                        title: 'Rimuovi VPN',
                        color: AppColors.error,
                        onTap: _busy ? null : _forget,
                      ),
                  ],
                ),
                SettingsSection(
                  title: 'Traffico',
                  children: [
                    SettingsSwitchTile(
                      icon: Icons.apps_rounded,
                      title: 'Solo StellarTV',
                      subtitle: _vpn.appOnly
                          ? 'Le altre app del dispositivo restano fuori '
                                'dalla VPN'
                          : 'Tutto il dispositivo passa dalla VPN finché '
                                'StellarTV è aperta',
                      value: _vpn.appOnly,
                      onChanged: (v) => _run(() => _vpn.setAppOnly(v)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
