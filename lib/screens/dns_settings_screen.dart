import 'package:flutter/material.dart';

import '../models/dns_resolver_policy.dart';
import '../services/dns_service.dart';
import '../theme/app_theme.dart';
import '../widgets/apple_page_scaffold.dart';
import '../widgets/settings_tiles.dart';

/// DNS used by the app: which resolver translates server names, plus a quick
/// check that it answers.
class DnsSettingsScreen extends StatefulWidget {
  const DnsSettingsScreen({super.key});

  @override
  State<DnsSettingsScreen> createState() => _DnsSettingsScreenState();
}

class _DnsSettingsScreenState extends State<DnsSettingsScreen> {
  final _dns = DnsService.instance;
  bool _probing = false;
  String? _probeResult;

  static final _options = [
    DnsResolverPolicy.systemId,
    for (final preset in DnsResolverPolicy.presets) preset.id,
    DnsResolverPolicy.customId,
  ];

  String _label(String id) {
    if (id == DnsResolverPolicy.systemId) return 'DNS del dispositivo';
    if (id == DnsResolverPolicy.customId) return 'Personalizzato';
    final preset = DnsResolverPolicy.presetById(id);
    if (preset == null) return id;
    return id == DnsResolverPolicy.defaultId
        ? '${preset.label} (consigliato)'
        : preset.label;
  }

  String? _detail(String id) {
    if (id == DnsResolverPolicy.systemId) {
      return 'Quello della rete o del fornitore di connessione';
    }
    if (id == DnsResolverPolicy.customId) {
      final custom = DnsResolverPolicy.parseCustomUrl(_dns.customUrl);
      return custom == null
          ? 'Un tuo indirizzo DNS-over-HTTPS'
          : custom.endpoint.toString();
    }
    return DnsResolverPolicy.presetById(id)?.description;
  }

  Future<void> _choose() async {
    final current = _options.contains(_dns.choice)
        ? _dns.choice
        : DnsResolverPolicy.defaultId;
    final chosen = await pickOption<String>(
      context,
      title: 'DNS da usare',
      options: _options,
      current: current,
      label: _label,
      detail: _detail,
    );
    if (chosen == null || !mounted) return;
    if (chosen == DnsResolverPolicy.customId) {
      await _editCustom();
      return;
    }
    await _dns.setChoice(chosen);
    setState(() => _probeResult = null);
  }

  Future<void> _editCustom() async {
    final controller = TextEditingController(text: _dns.customUrl ?? '');
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('DNS personalizzato'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://dns.esempio.com/dns-query',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Usa'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || !mounted) return;
    if (DnsResolverPolicy.parseCustomUrl(url) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci un indirizzo DNS-over-HTTPS (https://...)'),
        ),
      );
      return;
    }
    await _dns.setChoice(DnsResolverPolicy.customId, customUrl: url);
    setState(() => _probeResult = null);
  }

  Future<void> _probe() async {
    setState(() {
      _probing = true;
      _probeResult = null;
    });
    final took = await _dns.probe();
    if (!mounted) return;
    setState(() {
      _probing = false;
      _probeResult = took == null
          ? 'Nessuna risposta: l\'app usa il DNS del dispositivo'
          : 'Risponde in ${took.inMilliseconds} ms';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _dns,
      builder: (context, _) {
        final active = _dns.active;
        // An unusable stored choice is shown as what the policy really uses.
        final choice = active?.id ?? DnsResolverPolicy.systemId;
        return ApplePageScaffold(
          title: 'DNS',
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              SettingsSection(
                title: 'Server DNS',
                description:
                    'Il DNS trova l\'indirizzo dei server a cui l\'app si '
                    'collega. Quello scelto qui vale solo per StellarTV, '
                    'viaggia cifrato e non applica filtri. Se non risponde, '
                    'l\'app usa da sola il DNS del dispositivo.',
                children: [
                  SettingsValueTile(
                    icon: Icons.dns_outlined,
                    title: 'DNS in uso',
                    subtitle: _detail(choice),
                    value: _label(choice).replaceAll(' (consigliato)', ''),
                    onTap: _choose,
                  ),
                  if (choice == DnsResolverPolicy.customId)
                    SettingsValueTile(
                      icon: Icons.edit_outlined,
                      title: 'Modifica indirizzo',
                      onTap: _editCustom,
                    ),
                  if (active != null)
                    SettingsValueTile(
                      icon: Icons.network_check_rounded,
                      title: _probing ? 'Prova in corso...' : 'Prova il DNS',
                      subtitle: _probeResult,
                      onTap: _probing ? null : _probe,
                    ),
                ],
              ),
              const SettingsSection(
                title: 'Dove vale',
                children: [
                  SettingsValueTile(
                    icon: Icons.info_outline_rounded,
                    title: 'Accesso, cataloghi, guida TV e riproduzione',
                    subtitle:
                        'Su iPhone e iPad il player di sistema usa sempre il '
                        'DNS del dispositivo; lo stesso vale per i flussi '
                        'https aperti con il motore alternativo.',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
