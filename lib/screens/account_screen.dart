import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_provider.dart';
import '../providers/history_provider.dart';
import '../providers/sync_provider.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import '../services/device_type_service.dart';
import '../widgets/tv_text_field.dart';
import 'login_screen.dart';
import 'profile_picker_screen.dart';
import 'tv_pairing_screen.dart';

/// First screen for a signed-out device: sign in or create a StellarTV
/// account (email + password). The account carries playlist, profiles,
/// histories, favorites and settings across every device.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();

  static const _guestKey = 'stellar_guest_mode';

  /// True when this device chose to use the app without an account.
  static Future<bool> isGuest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_guestKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setGuest(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_guestKey, value);
    } catch (_) {}
  }
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  bool _register = false;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || !email.contains('.')) {
      _show('Inserisci un\'email valida.');
      return;
    }
    if (password.length < 6) {
      _show('La password deve avere almeno 6 caratteri.');
      return;
    }
    if (_register && password != _confirm.text) {
      _show('Le due password non coincidono.');
      return;
    }
    setState(() => _loading = true);
    final sync = context.read<SyncProvider>();
    final history = context.read<HistoryProvider>();
    final app = context.read<AppProvider>();
    final error = _register
        ? await sync.signUp(email, password)
        : await sync.signIn(email, password);
    if (!mounted) return;
    if (error == SyncService.confirmPending ||
        error == SyncService.notConfirmed) {
      setState(() {
        _loading = false;
        _register = false;
      });
      await _showConfirmDialog(
        email,
        justCreated: error == SyncService.confirmPending,
      );
      return;
    }
    if (error != null) {
      setState(() => _loading = false);
      _show(error);
      return;
    }
    await AccountScreen.setGuest(false);
    // Restore whatever this account already saved (playlist, profiles…).
    try {
      await history.pullFromCloud().timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
    } catch (_) {}
    // Playlists saved from the website arrive too, but only when this
    // device has no list configured yet (never overwrites).
    try {
      await sync.restorePlaylistFromCloud();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => app.isAuthenticated
            ? const ProfilePickerScreen()
            : const LoginScreen(),
      ),
      (_) => false,
    );
  }

  /// TV-friendly dialog: the user confirms the email from a phone or PC,
  /// then comes back and presses Accedi. OK button focused for the remote.
  Future<void> _showConfirmDialog(
    String email, {
    required bool justCreated,
  }) async {
    final sync = context.read<SyncProvider>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(justCreated ? 'Account creato!' : 'Conferma la tua email'),
        content: Text(
          'Ti abbiamo inviato un\'email di conferma a $email.\n\n'
          'Apri il link dal telefono o dal computer (controlla anche lo spam), '
          'poi torna qui e premi Accedi.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final err = await sync.resendConfirmation(email);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              _show(
                err ?? 'Email di conferma inviata di nuovo.',
                ok: err == null,
              );
            },
            child: const Text('Invia di nuovo'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Ho capito'),
          ),
        ],
      ),
    );
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      _show('Scrivi prima la tua email nel campo qui sopra.');
      return;
    }
    final error = await context.read<SyncProvider>().resetPassword(email);
    if (!mounted) return;
    _show(
      error ?? 'Ti abbiamo inviato un\'email per reimpostare la password.',
      ok: error == null,
    );
  }

  /// Uses the app on this device only: no account, no cloud sync.
  Future<void> _continueAsGuest() async {
    await AccountScreen.setGuest(true);
    if (!mounted) return;
    final app = context.read<AppProvider>();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => app.isAuthenticated
            ? const ProfilePickerScreen()
            : const LoginScreen(),
      ),
      (_) => false,
    );
  }

  void _show(String text, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: ok ? AppColors.surface : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openPairing() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TvPairingScreen()));
  }

  Widget _action(VoidCallback? callback, Widget child) =>
      AuthAction(onPressed: callback, child: child);

  @override
  Widget build(BuildContext context) {
    final submit = _loading ? null : _submit;
    final guest = _loading ? null : _continueAsGuest;
    final pair = _loading ? null : _openPairing;
    final toggle = _loading
        ? null
        : () => setState(() => _register = !_register);
    return AuthScaffold(
      title: _register ? 'Crea il tuo account' : 'Bentornato',
      subtitle: _register
          ? 'Profili e dati personali. Il tuo account, su ogni schermo.'
          : 'Accedi a StellarTV',
      alternatives: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _action(
            pair,
            OutlinedButton.icon(
              onPressed: pair,
              icon: const Icon(Icons.qr_code_rounded),
              label: const Text('Accedi con QR o codice'),
            ),
          ),
          const SizedBox(height: 12),
          _action(
            guest,
            TextButton.icon(
              onPressed: guest,
              icon: const Icon(Icons.person_outline_rounded),
              label: const Text('Continua come ospite'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Senza account i dati restano solo su questo dispositivo.\n'
            'Account e guida: stellartv.vercel.app',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
      form: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TvTextField(
            autofocus: DeviceTypeService.isTv,
            controller: _email,
            nextFocus: _passwordFocus,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
          ),
          const SizedBox(height: 16),
          TvTextField(
            controller: _password,
            focusNode: _passwordFocus,
            nextFocus: _register ? _confirmFocus : null,
            obscureText: _obscure,
            autofillHints: [
              _register ? AutofillHints.newPassword : AutofillHints.password,
            ],
            textInputAction: _register
                ? TextInputAction.next
                : TextInputAction.done,
            onSubmitted: (_) {
              if (!_register && !_loading) _submit();
            },
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: _action(
                () => setState(() => _obscure = !_obscure),
                IconButton(
                  tooltip: _obscure ? 'Mostra password' : 'Nascondi password',
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
          if (_register) ...[
            const SizedBox(height: 16),
            TvTextField(
              controller: _confirm,
              focusNode: _confirmFocus,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_loading) _submit();
              },
              decoration: const InputDecoration(
                labelText: 'Ripeti password',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (!_register)
            Align(
              alignment: Alignment.centerRight,
              child: _action(
                _loading ? null : _forgot,
                TextButton(
                  onPressed: _loading ? null : _forgot,
                  child: const Text('Password dimenticata?'),
                ),
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: _action(
              submit,
              FilledButton.icon(
                onPressed: submit,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward_rounded),
                label: Text(
                  _loading
                      ? 'Connessione...'
                      : (_register ? 'Crea account' : 'Accedi'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _action(
            toggle,
            TextButton(
              onPressed: toggle,
              child: Text(
                _register ? 'Hai già un account? Accedi' : 'Crea un account',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
