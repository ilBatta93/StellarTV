import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/app_provider.dart';
import '../providers/history_provider.dart';
import '../providers/sync_provider.dart';
import '../services/tv_pairing_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import 'login_screen.dart';
import 'profile_picker_screen.dart';

/// Optional sign-in for TVs: shows a QR and a 6-character code. The user
/// approves them from the website (Collega TV) and this device signs in
/// automatically — no email or password typed with the remote.
class TvPairingScreen extends StatefulWidget {
  const TvPairingScreen({super.key});

  @override
  State<TvPairingScreen> createState() => _TvPairingScreenState();
}

class _TvPairingScreenState extends State<TvPairingScreen> {
  final _service = TvPairingService(Supabase.instance.client);
  TvPairing? _pairing;
  Timer? _poll;
  Timer? _countdown;
  int _secondsLeft = 0;
  String? _error;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _countdown?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _poll?.cancel();
    _countdown?.cancel();
    setState(() {
      _pairing = null;
      _error = null;
    });
    try {
      final pairing = await _service.create();
      if (!mounted) return;
      setState(() {
        _pairing = pairing;
        _secondsLeft = pairing.expiresIn;
      });
      _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        if (_secondsLeft <= 1) {
          t.cancel();
          _start(); // fresh code, keeps the screen alive
        } else {
          setState(() => _secondsLeft--);
        }
      });
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Connessione non riuscita. Riprova.');
      }
    }
  }

  Future<void> _check() async {
    final pairing = _pairing;
    if (pairing == null || _completing) return;
    try {
      final token = await _service.pollToken(pairing);
      if (token == null || !mounted) return;
      _completing = true;
      _poll?.cancel();
      _countdown?.cancel();
      await _service.completeWithToken(token);
      if (!mounted) return;
      // Same restore as a normal sign-in: cloud data, then the playlists
      // saved from the website when this device has none yet.
      final history = context.read<HistoryProvider>();
      final sync = context.read<SyncProvider>();
      try {
        await history.pullFromCloud().timeout(
          const Duration(seconds: 10),
          onTimeout: () => false,
        );
      } catch (_) {}
      try {
        await sync.restorePlaylistFromCloud();
      } catch (_) {}
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Codice scaduto: te ne mostro uno nuovo.');
      _completing = false;
      _start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairing = _pairing;
    final minutes = (_secondsLeft ~/ 60).toString();
    final seconds = (_secondsLeft % 60).toString().padLeft(2, '0');
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandLogo(size: 52)),
                  const SizedBox(height: 24),
                  const Text(
                    'Collega questa TV',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Dal telefono o dal computer vai su\nstellartv.lovable.app/collega\ne inserisci questo codice.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  if (pairing == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: QrImageView(
                          data: pairing.url,
                          version: QrVersions.auto,
                          size: 180,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          pairing.code,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Il codice scade tra $minutes:$seconds',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Torna all\'accesso con email'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
