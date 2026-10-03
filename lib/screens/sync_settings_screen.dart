import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/history_provider.dart';
import '../providers/sync_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_tiles.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

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
      appBar: AppBar(title: const Text('Sincronizzazione')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsSection(
            title: 'Come funziona',
            description:
                'Tutti i tuoi dati (credenziali della playlist, cronologia, '
                'preferiti, impostazioni del player e aspetto dell\'app) sono '
                'salvati su questo dispositivo. Attiva la sincronizzazione per '
                'ritrovarli anche sugli altri dispositivi (Fire TV, iPhone, '
                'iPad, Android TV): ti basta usare lo stesso codice a 8 '
                'caratteri ovunque. Le modifiche vengono inviate '
                'automaticamente.',
            children: const [],
          ),
          if (sync.code == null) ...[
            SettingsSection(
              title: 'Attiva',
              children: [
                SettingsValueTile(
                  icon: Icons.cloud_sync_outlined,
                  title: 'Attiva la sincronizzazione',
                  subtitle: 'Genera un codice da usare sugli altri dispositivi',
                  onTap: sync.isBusy ? null : () => context.read<SyncProvider>().enable(),
                ),
                SettingsValueTile(
                  icon: Icons.input_rounded,
                  title: 'Ho già un codice',
                  subtitle: 'Inserisci il codice di un altro dispositivo',
                  onTap: () => _showCodeInputDialog(context),
                ),
              ],
            ),
          ] else ...[
            SettingsSection(
              title: 'Il tuo codice',
              description:
                  'Inserisci questo codice nell\'app su un altro dispositivo per '
                  'sincronizzare cronologia, preferiti e impostazioni.',
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Center(
                          child: GestureDetector(
                            onTap: () => _copyCode(context, sync.code!),
                            child: Text(
                              sync.code!,
                              style: const TextStyle(
                                fontSize: 28,
                                letterSpacing: 6,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copia codice'),
                        onPressed: () => _copyCode(context, sync.code!),
                      ),
                    ],
                  ),
                ),
                SettingsValueTile(
                  icon: Icons.upload_rounded,
                  title: 'Invia al cloud',
                  subtitle: 'Ultimo invio: ${_fmtDate(sync.lastPush)} · automatico ad ogni modifica',
                  onTap: sync.isBusy
                      ? null
                      : () => _pushAll(context),
                ),
                SettingsValueTile(
                  icon: Icons.download_rounded,
                  title: 'Scarica dal cloud',
                  subtitle:
                      'Unisce i dati remoti con quelli locali · ultimo scaricamento: ${_fmtDate(sync.lastPull)}',
                  onTap: sync.isBusy ? null : () => _pull(context),
                ),
                SettingsValueTile(
                  icon: Icons.cloud_off_rounded,
                  title: 'Disattiva sincronizzazione',
                  color: AppColors.error,
                  onTap: () => _confirmDisable(context),
                ),
              ],
            ),
          ],
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

  void _copyCode(BuildContext context, String code) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Codice $code pronto da incollare'),
      ),
    );
  }

  void _showCodeInputDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Inserisci codice',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Digita il codice a 8 caratteri mostrato sull\'altro dispositivo.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              decoration: const InputDecoration(
                hintText: 'ABCD2345',
                counterText: '',
              ),
              style: const TextStyle(
                  fontSize: 22, letterSpacing: 4, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_rounded),
              label: const Text('Usa questo codice'),
              onPressed: () {
                final syncProvider = context.read<SyncProvider>();
                Navigator.pop(ctx);
                syncProvider.useExistingCode(_codeController.text);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDisable(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Disattivare la sincronizzazione?'),
        content: const Text(
            'I dati restano su questo dispositivo, ma non verranno più inviati al cloud.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Disattiva', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<SyncProvider>().disable();
  }
}
