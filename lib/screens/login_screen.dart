import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../providers/history_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import '../models/source_access.dart';
import '../widgets/source_access_form.dart';
import '../providers/sync_provider.dart';
import '../services/key_handoff.dart';
import '../widgets/phone_handoff_panel.dart';
import '../widgets/recovery_key_entry.dart';
import 'profile_picker_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initial});

  /// Access details already received from the phone (QR login): filled in
  /// and submitted automatically.
  final SourcePatch? initial;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _access = SourceAccessController();
  final _keyController = TextEditingController();
  final _keyFocus = FocusNode();
  final _keyPanel = GlobalKey<RecoveryKeyPanelState>();
  bool _isLoading = false;
  bool _phone = false;
  bool _askForKey = false;

  @override
  void initState() {
    super.initState();
    final x = widget.initial;
    if (x != null) {
      _access.apply(x);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleXtreamLogin();
      });
    }
  }

  @override
  void dispose() {
    _access.dispose();
    _keyController.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Configura i contenuti',
      subtitle: 'Connessione locale',
      form: _buildXtreamForm(),
    );
  }

  Widget _buildXtreamForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SourceAccessFields(
          controller: _access,
          labelsAbove: true,
          nextFocus: _askForKey ? _keyFocus : null,
          onSubmitted: _handleXtreamLogin,
        ),
        const SizedBox(height: 16),
        RecoveryKeyPanel(
          key: _keyPanel,
          controller: _keyController,
          focusNode: _keyFocus,
          onSubmitted: (_) => _handleXtreamLogin(),
          onVisibility: (visible) {
            if (_askForKey == visible || !mounted) return;
            setState(() => _askForKey = visible);
          },
        ),
        if (_signedIn(context)) ...[
          const SizedBox(height: 16),
          if (_phone)
            PhoneHandoffPanel(
              mode: 'x',
              onReceived: (raw) {
                final patch = SourceHandoff.parse(raw);
                setState(() => _phone = false);
                if (patch == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dati ricevuti non validi. Riprova.'),
                    ),
                  );
                  return;
                }
                _access.apply(patch);
                _handleXtreamLogin();
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
        SizedBox(
          width: double.infinity,
          child: AuthAction(
            onPressed: _isLoading ? null : _handleXtreamLogin,
            child: ElevatedButton.icon(
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textPrimary,
                      ),
                    )
                  : const Icon(Icons.login),
              label: Text(_isLoading ? 'Connessione...' : 'Connetti'),
              onPressed: _isLoading ? null : _handleXtreamLogin,
            ),
          ),
        ),
      ],
    );
  }

  /// Senza sessione in albero il passaggio dal telefono resta nascosto.
  bool _signedIn(BuildContext context) {
    try {
      return context.watch<SyncProvider>().isSignedIn;
    } on ProviderNotFoundException {
      return false;
    }
  }

  Future<void> _handleXtreamLogin() async {
    if (_isLoading) return;
    final access = _access.access;
    final problem = access.problem;
    if (problem != null) {
      _showError(problem);
      return;
    }

    setState(() => _isLoading = true);
    await _keyPanel.currentState?.ready;
    if (!mounted) return;

    final auth = await AppProvider.checkSource(access);
    if (!mounted) return;
    if (!auth.ok) {
      setState(() => _isLoading = false);
      _showError(auth.message);
      return;
    }

    final askForKey = _keyPanel.currentState?.askForKey ?? _askForKey;
    final proceed = !askForKey
        ? true
        : await acceptTypedRecoveryKey(
            context: context,
            sync: context.read<SyncProvider>(),
            history: context.read<HistoryProvider>(),
            typed: _keyController.text,
            askForKey: true,
            keyFocus: _keyFocus,
          );
    if (!proceed || !mounted) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final provider = context.read<AppProvider>();
    final success = await provider.loginWithSource(access, verified: auth);

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        _navigateHome();
      } else {
        _showError(provider.error ?? 'Connessione non riuscita');
      }
    }
  }

  void _navigateHome() {
    // After the first login (or cloud restore) always pass through the
    // profile picker: if no profile exists yet the user creates one there.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ProfilePickerScreen()),
      (_) => false,
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
