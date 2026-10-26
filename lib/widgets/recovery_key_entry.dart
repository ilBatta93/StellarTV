import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/history_provider.dart';
import '../providers/sync_provider.dart';
import '../theme/app_theme.dart';
import 'auth_scaffold.dart';
import 'tv_focusable.dart';
import 'tv_text_field.dart';

/// Shown wherever the recovery key can be typed or is already on device.
const recoveryKeyExplanation =
    'La chiave di recupero sblocca cronologia e preferiti cifrati del tuo account. '
    'È la stessa su tutti i dispositivi e resta solo su questo: non viene inviata al cloud. '
    'Senza la chiave, e senza un altro dispositivo già sbloccato, quei dati non si possono recuperare.';

const recoveryKeySavedNotice =
    'Chiave già salvata su questo dispositivo per questo account. Non serve inserirla di nuovo.';

enum RecoveryKeyPresence { hidden, checking, missing, saved }

/// Visual states only. The caller decides which one applies.
class RecoveryKeyEntry extends StatelessWidget {
  const RecoveryKeyEntry({
    super.key,
    required this.presence,
    this.controller,
    this.focusNode,
    this.obscure = true,
    this.onToggleObscure,
    this.onSubmitted,
  });

  final RecoveryKeyPresence presence;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    if (presence == RecoveryKeyPresence.hidden) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Chiave di recupero',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          recoveryKeyExplanation,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        if (presence == RecoveryKeyPresence.checking)
          const LinearProgressIndicator()
        else if (presence == RecoveryKeyPresence.saved)
          const Text(
            recoveryKeySavedNotice,
            style: TextStyle(fontSize: 14, height: 1.4),
          )
        else if (controller != null) ...[
          TvTextField(
            controller: controller!,
            focusNode: focusNode,
            obscureText: obscure,
            textInputAction: TextInputAction.done,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: 'Incolla la chiave STV1-…',
              prefixIcon: const Icon(Icons.key_outlined, size: 20),
              suffixIcon: AuthAction(
                onPressed: onToggleObscure,
                child: IconButton(
                  tooltip: obscure ? 'Mostra chiave' : 'Nascondi chiave',
                  icon: Icon(
                    obscure ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: onToggleObscure,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Reads the account key already stored on this device and shows [RecoveryKeyEntry].
class RecoveryKeyPanel extends StatefulWidget {
  const RecoveryKeyPanel({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onSubmitted,
    this.onVisibility,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<bool>? onVisibility;

  @override
  State<RecoveryKeyPanel> createState() => RecoveryKeyPanelState();
}

class RecoveryKeyPanelState extends State<RecoveryKeyPanel> {
  RecoveryKeyPresence _presence = RecoveryKeyPresence.checking;
  bool _obscure = true;
  late final Future<void> ready;

  /// True only when the user may type a key that is not on this device yet.
  bool get askForKey => _presence == RecoveryKeyPresence.missing;

  @override
  void initState() {
    super.initState();
    SyncProvider? sync;
    try {
      sync = context.read<SyncProvider>();
    } on ProviderNotFoundException {
      sync = null;
    }
    if (sync == null || !sync.isSignedIn) {
      _presence = RecoveryKeyPresence.hidden;
      ready = Future.value();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onVisibility?.call(false);
      });
      return;
    }
    ready = _load(sync);
  }

  Future<void> _load(SyncProvider sync) async {
    String? stored;
    try {
      stored = await sync.recoveryKey();
    } catch (_) {
      stored = null;
    }
    if (!mounted) return;
    _apply(
      stored == null || stored.trim().isEmpty
          ? RecoveryKeyPresence.missing
          : RecoveryKeyPresence.saved,
    );
  }

  void _apply(RecoveryKeyPresence next) {
    if (!mounted) return;
    setState(() => _presence = next);
    widget.onVisibility?.call(next == RecoveryKeyPresence.missing);
  }

  @override
  Widget build(BuildContext context) {
    return RecoveryKeyEntry(
      presence: _presence,
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscure: _obscure,
      onToggleObscure: () => setState(() => _obscure = !_obscure),
      onSubmitted: widget.onSubmitted,
    );
  }
}

/// Imports [typed] when it opens the vault. A wrong key leaves every field
/// as the user typed it and asks whether to continue without storing it.
///
/// Returns true when the source login may continue.
Future<bool> acceptTypedRecoveryKey({
  required BuildContext context,
  required SyncProvider sync,
  required HistoryProvider history,
  required String typed,
  required bool askForKey,
  required FocusNode keyFocus,
}) async {
  if (!askForKey || !sync.isSignedIn) return true;
  final key = typed.trim();
  if (key.isEmpty) return true;
  try {
    await sync.authorizeVault(key);
  } catch (_) {
    if (!context.mounted) return false;
    final skip = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const InvalidRecoveryKeyDialog(),
    );
    if (skip == true) return true;
    if (context.mounted) keyFocus.requestFocus();
    return false;
  }
  try {
    await history.pullFromCloud();
  } catch (_) {}
  return true;
}

class InvalidRecoveryKeyDialog extends StatelessWidget {
  const InvalidRecoveryKeyDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Chiave non valida'),
      content: const Text(
        'La chiave di recupero non è valida. I dati della sorgente sono corretti e restano compilati. '
        'Puoi correggerla oppure continuare senza sbloccare cronologia e preferiti su questo dispositivo.',
      ),
      actions: [
        _choice(context, 'Correggi la chiave', false, autofocus: true),
        _choice(context, 'Continua senza chiave', true),
      ],
    );
  }

  Widget _choice(
    BuildContext context,
    String label,
    bool value, {
    bool autofocus = false,
  }) {
    void go() => Navigator.of(context).pop(value);
    return TvFocusable(
      autofocus: autofocus,
      focusedScale: 1.05,
      onPressed: go,
      child: TextButton(onPressed: go, child: Text(label)),
    );
  }
}
