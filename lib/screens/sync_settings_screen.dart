import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/history_provider.dart';
import '../providers/sync_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_tiles.dart';
import 'account_screen.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  String _fmtDate(DateTime? at) {
    if (at == null) return 'Mai';
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    final history = context.watch<HistoryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Account e sincronizzazione')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsSection(
            title: 'Come funziona',
            description:
                'Tutto è legato al tuo account StellarTV: playlist, profili, '
                'cronologia di ogni profilo, preferiti e impostazioni. Accedi '
                'con la stessa email e password su ogni dispositivo (telefono, '
                'tablet, Fire TV, Google TV) e i dati si aggiornano da soli.',
            children: const [],
          ),
          SettingsSection(
            title: 'Il tuo account',
            children: [
              SettingsValueTile(
                icon: Icons.account_circle_outlined,
                title: 'Email',
                value: sync.email ?? '-',
              ),
              SettingsValueTile(
                icon: Icons.upload_rounded,
                title: 'Invia al cloud',
                subtitle: 'Ultimo invio: ${_fmtDate(sync.lastPush)} · automatico ad ogni modifica',
                onTap: sync.isBusy ? null : () => _pushAll(context),
              ),
              SettingsValueTile(
                icon: Icons.download_rounded,
                title: 'Scarica dal cloud',
                subtitle:
                    'Unisce i dati remoti con quelli locali · ultimo scaricamento: ${_fmtDate(sync.lastPull)}',
                onTap: sync.isBusy ? null : () => _pull(context),
              ),
              SettingsValueTile(
                icon: Icons.password_rounded,
                title: 'Cambia password',
                subtitle: 'Ricevi un\'email per sceglierne una nuova',
                onTap: () => _resetPassword(context),
              ),
              SettingsValueTile(
                icon: Icons.logout_rounded,
                title: 'Esci dall\'account',
                color: AppColors.error,
                onTap: () => _confirmDisable(context),
              ),
            ],
          ),
          if (sync.message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                children: [
                  Icon(
                    sync.success
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    size: 16,
                    color: sync.success ? AppColors.success : AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sync.message!,
                      style: TextStyle(
                        color: sync.success ? AppColors.success : AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Stato locale',
            children: [
              SettingsValueTile(
                icon: Icons.history_rounded,
                title: 'Contenuti in cronologia',
                value: '${history.entries.length}',
              ),
              SettingsValueTile(
                icon: Icons.smartphone_rounded,
                title: 'Salvataggio locale',
                value: 'Sempre attivo',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pushAll(BuildContext context) async {
    final history = context.read<HistoryProvider>();
    final ok = await history.pushAllNow();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(ok
          ? 'Dati inviati al cloud'
          : 'Invio non riuscito. Controlla la connessione.'),
    ));
  }

  Future<void> _pull(BuildContext context) async {
    final sync = context.read<SyncProvider>();
    final history = context.read<HistoryProvider>();
    await sync.pullNow();
    await history.pullFromCloud();
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (history.error != null) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(history.error!),
      ));
    } else {
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
            'Dati scaricati e uniti. Se è arrivata la playlist da un altro '
            'dispositivo, riavvia l\'app per caricarla.'),
      ));
    }
  }

  Future<void> _resetPassword(BuildContext context) async {
    final sync = context.read<SyncProvider>();
    final email = sync.email;
    if (email == null) return;
    final error = await sync.resetPassword(email);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(error ?? 'Email inviata a $email.'),
    ));
  }

  Future<void> _confirmDisable(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Uscire dall\'account?'),
        content: const Text(
            'I tuoi dati restano salvati nel cloud. Da questo dispositivo verranno tolti playlist, profili e cronologia finché non accedi di nuovo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Esci', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    await context.read<SyncProvider>().signOut();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AccountScreen()),
      (_) => false,
    );
  }
}
