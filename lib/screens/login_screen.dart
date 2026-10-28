import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../providers/history_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import '../services/device_type_service.dart';
import '../services/xtream_service.dart';
import '../widgets/tv_text_field.dart';
import '../providers/sync_provider.dart';
import '../services/key_handoff.dart';
import '../widgets/phone_handoff_panel.dart';
import '../widgets/recovery_key_entry.dart';
import 'profile_picker_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initial});

  /// List details already received from the phone (QR login): filled in and
  /// submitted automatically.
  final XtreamHandoff? initial;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _xtreamServerController = TextEditingController();
  final _xtreamUserController = TextEditingController();
  final _xtreamPassController = TextEditingController();
  final _keyController = TextEditingController();
  final _xtreamUserFocus = FocusNode();
  final _xtreamPassFocus = FocusNode();
  final _keyFocus = FocusNode();
  final _keyPanel = GlobalKey<RecoveryKeyPanelState>();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _phone = false;
  bool _askForKey = false;

  @override
  void initState() {
    super.initState();
    final x = widget.initial;
    if (x != null) {
      _xtreamServerController.text = x.server;
      _xtreamUserController.text = x.username;
      _xtreamPassController.text = x.password;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleXtreamLogin();
      });
    }
  }

  @override
  void dispose() {
    _xtreamServerController.dispose();
    _xtreamUserController.dispose();
    _xtreamPassController.dispose();
    _keyController.dispose();
    _xtreamUserFocus.dispose();
    _xtreamPassFocus.dispose();
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
        _buildFieldLabel('Server URL'),
        const SizedBox(height: 6),
        TvTextField(
          autofocus: DeviceTypeService.isTv,
          controller: _xtreamServerController,
          nextFocus: _xtreamUserFocus,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'http://tuo-server.com:8080',
            prefixIcon: Icon(Icons.dns, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        _buildFieldLabel('Nome utente'),
        const SizedBox(height: 6),
        TvTextField(
          controller: _xtreamUserController,
          focusNode: _xtreamUserFocus,
          nextFocus: _xtreamPassFocus,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'Inserisci il nome utente',
            prefixIcon: Icon(Icons.person, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        _buildFieldLabel('Password'),
        const SizedBox(height: 6),
        TvTextField(
          controller: _xtreamPassController,
          focusNode: _xtreamPassFocus,
          nextFocus: _askForKey ? _keyFocus : null,
          textInputAction: _askForKey
              ? TextInputAction.next
              : TextInputAction.done,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: 'Inserisci la password',
            prefixIcon: const Icon(Icons.lock, size: 20),
            suffixIcon: AuthAction(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              child: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
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
                final x = XtreamHandoff.parse(raw);
                setState(() => _phone = false);
                if (x == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dati ricevuti non validi. Riprova.'),
                    ),
                  );
                  return;
                }
                _xtreamServerController.text = x.server;
                _xtreamUserController.text = x.username;
                _xtreamPassController.text = x.password;
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

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Future<void> _handleXtreamLogin() async {
    final server = _xtreamServerController.text.trim();
    final username = _xtreamUserController.text.trim();
    final password = _xtreamPassController.text.trim();

    if (server.isEmpty || username.isEmpty || password.isEmpty) {
      _showError('Compila tutti i campi');
      return;
    }

    setState(() => _isLoading = true);
    await _keyPanel.currentState?.ready;
    if (!mounted) return;

    final auth = await XtreamService().authenticate(
      server: server,
      username: username,
      password: password,
    );
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
    final success = await provider.loginWithXtream(
      server: server,
      username: username,
      password: password,
      verified: auth,
    );

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
