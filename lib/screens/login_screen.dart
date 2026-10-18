import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import '../services/device_type_service.dart';
import '../widgets/tv_text_field.dart';
import 'profile_picker_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _xtreamServerController = TextEditingController();
  final _xtreamUserController = TextEditingController();
  final _xtreamPassController = TextEditingController();
  final _xtreamUserFocus = FocusNode();
  final _xtreamPassFocus = FocusNode();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _xtreamServerController.dispose();
    _xtreamUserController.dispose();
    _xtreamPassController.dispose();
    _xtreamUserFocus.dispose();
    _xtreamPassFocus.dispose();
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
          textInputAction: TextInputAction.done,
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

    final provider = context.read<AppProvider>();
    final success = await provider.loginWithXtream(
      server: server,
      username: username,
      password: password,
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
