import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../providers/history_provider.dart';
import '../providers/sync_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import 'login_screen.dart';
import 'profile_picker_screen.dart';

/// First screen for a signed-out device: sign in or create an ilBattaTV
/// account (email + password). The account carries playlist, profiles,
/// histories, favorites and settings across every device.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _register = false;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
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
    if (error != null) {
      setState(() => _loading = false);
      _show(error);
      return;
    }
    // Restore whatever this account already saved (playlist, profiles…).
    try {
      await history
          .pullFromCloud()
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
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

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      _show('Scrivi prima la tua email nel campo qui sopra.');
      return;
    }
    final error = await context.read<SyncProvider>().resetPassword(email);
    if (!mounted) return;
    _show(error ??
        'Ti abbiamo inviato un\'email per reimpostare la password.',
        ok: error == null);
  }

  void _show(String text, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: ok ? AppColors.surface : AppColors.error,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.7),
            radius: 1.1,
            colors: [
              AppColors.primary.withValues(alpha: 0.16),
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: BrandMark(size: 76)),
                      const SizedBox(height: 16),
                      const Center(child: BrandWordmark(fontSize: 28)),
                      const SizedBox(height: 28),
                      Text(
                        _register ? 'Crea il tuo account' : 'Accedi',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _register
                            ? 'Con un solo account ritrovi playlist, profili, '
                                'cronologia e preferiti su tutti i dispositivi.'
                            : 'Usa la stessa email e password su ogni dispositivo.',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: [
                          _register
                              ? AutofillHints.newPassword
                              : AutofillHints.password
                        ],
                        textInputAction: _register
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onSubmitted: (_) => _register ? null : _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      if (_register) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirm,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Ripeti password',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                        ),
                      ],
                      if (!_register)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _loading ? null : _forgot,
                            child: const Text('Password dimenticata?'),
                          ),
                        )
                      else
                        const SizedBox(height: 16),
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.4),
                                )
                              : Text(_register ? 'Crea account' : 'Accedi'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => setState(() => _register = !_register),
                        child: Text(_register
                            ? 'Hai già un account? Accedi'
                            : 'Non hai un account? Creane uno'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
