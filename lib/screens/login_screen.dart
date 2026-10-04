import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../providers/history_provider.dart';
import '../providers/sync_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
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
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _xtreamServerController.dispose();
    _xtreamUserController.dispose();
    _xtreamPassController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Soft brand glow behind the header.
          Positioned(
            top: -120,
            left: -80,
            right: -80,
            child: Container(
              height: 320,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.28),
                    Colors.transparent,
                  ],
                  radius: 0.9,
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    _buildLogo(),
                    const SizedBox(height: 36),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _buildCard(),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _buildRestoreCard(),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 32,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const BrandMark(size: 56),
        ),
        const SizedBox(height: 20),
        const BrandWordmark(fontSize: 30),
        const SizedBox(height: 8),
        const Text(
          'Collega il tuo account Xtream per iniziare a guardare',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: _buildXtreamForm(),
      ),
    );
  }

  Widget _buildRestoreCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.14),
            AppColors.secondary.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _isLoading ? null : _showSyncCodeDialog,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.18),
                  ),
                  child: Icon(Icons.cloud_sync_outlined,
                      size: 22, color: AppColors.primary),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hai già usato ilBattaTV?',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Ripristina dal cloud con il tuo codice a 8 caratteri',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    size: 14, color: AppColors.primary.withValues(alpha: 0.8)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildXtreamForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('Server URL'),
        const SizedBox(height: 6),
        TextField(
          controller: _xtreamServerController,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'http://tuo-server.com:8080',
            prefixIcon: Icon(Icons.dns, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        _buildFieldLabel('Nome utente'),
        const SizedBox(height: 6),
        TextField(
          controller: _xtreamUserController,
          decoration: const InputDecoration(
            hintText: 'Inserisci il nome utente',
            prefixIcon: Icon(Icons.person, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        _buildFieldLabel('Password'),
        const SizedBox(height: 6),
        TextField(
          controller: _xtreamPassController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: 'Inserisci la password',
            prefixIcon: const Icon(Icons.lock, size: 20),
            suffixIcon: IconButton(
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
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.login),
            label: Text(_isLoading ? 'Connessione...' : 'Connetti'),
            onPressed: _isLoading ? null : _handleXtreamLogin,
          ),
        ),
      ],
    );
  }

  /// First-run cloud restore: pairs this device to an existing sync code and
  /// pulls history, favorites and playlist credentials before connecting.
  Future<void> _showSyncCodeDialog() async {
    final codeController = TextEditingController();
    final sync = context.read<SyncProvider>();
    final history = context.read<HistoryProvider>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Ripristina dal cloud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Inserisci il codice a 8 caratteri che usi sugli altri dispositivi: '
              'verranno recuperati cronologia, preferiti e dati di accesso.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              autofocus: true,
              maxLength: 8,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'Es. AB12CD34',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ripristina')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _isLoading = true);
    await sync.useExistingCode(codeController.text.toUpperCase().trim());
    final restored = await history.pullFromCloud();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (restored) {
      _navigateHome();
    } else {
      _showError(
          'Ripristino non riuscito: codice non valido o nessun dato nel cloud. '
          'Puoi comunque connettere il tuo account.');
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
