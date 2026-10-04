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
      body: SafeArea(
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
                const SizedBox(height: 32),
                _buildLogo(),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildCard(),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        const BrandMark(size: 72),
        const SizedBox(height: 16),
        const BrandWordmark(fontSize: 28),
        const SizedBox(height: 8),
        const Text(
          'Collega il tuo account Xtream per iniziare a guardare',
          style: TextStyle(color: Color(0xFFA1A1AE), fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF13131A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _buildXtreamForm(),
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
                color: const Color(0xFFA1A1AE),
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
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.cloud_sync_outlined, size: 18),
            label: const Text('Ho un codice di sincronizzazione'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              textStyle: const TextStyle(fontSize: 13),
            ),
            onPressed: _isLoading ? null : _showSyncCodeDialog,
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
        color: Color(0xFFA1A1AE),
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
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
