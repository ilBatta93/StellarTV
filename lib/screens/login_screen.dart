import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/brand_logo.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _xtreamServerController = TextEditingController();
  final _xtreamUserController = TextEditingController();
  final _xtreamPassController = TextEditingController();
  final _m3uUrlController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _xtreamServerController.dispose();
    _xtreamUserController.dispose();
    _xtreamPassController.dispose();
    _m3uUrlController.dispose();
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
          'Collega il tuo provider per iniziare a guardare',
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
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFFF5A1F),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: const Color(0xFFFF5A1F),
            unselectedLabelColor: const Color(0xFFA1A1AE),
            labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Xtream Codes'),
              Tab(text: 'M3U / M3U8'),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              height: 320,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildXtreamForm(),
                  _buildM3uForm(),
                ],
              ),
            ),
          ),
        ],
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
        const Spacer(),
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

  Widget _buildM3uForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('URL playlist M3U / M3U8'),
        const SizedBox(height: 6),
        TextField(
          controller: _m3uUrlController,
          maxLines: 3,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://esempio.com/playlist.m3u8',
            prefixIcon: Padding(
              padding: EdgeInsets.only(bottom: 48),
              child: Icon(Icons.link, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF09090D),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: Color(0xFFFF5A1F), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Incolla il link M3U o M3U8 fornito dal tuo provider IPTV',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
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
                : const Icon(Icons.download_for_offline),
            label: Text(_isLoading ? 'Caricamento...' : 'Carica playlist'),
            onPressed: _isLoading ? null : _handleM3uLogin,
          ),
        ),
      ],
    );
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

  Future<void> _handleM3uLogin() async {
    final url = _m3uUrlController.text.trim();
    if (url.isEmpty) {
      _showError('Inserisci l\'URL della playlist');
      return;
    }

    setState(() => _isLoading = true);

    final provider = context.read<AppProvider>();
    final success = await provider.loginWithM3u(url);

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        _navigateHome();
      } else {
        _showError(provider.error ?? 'Impossibile caricare la playlist');
      }
    }
  }

  void _navigateHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const HomeScreen(),
        transitionsBuilder: (_, anim, _, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFEF4444),
      ),
    );
  }
}
