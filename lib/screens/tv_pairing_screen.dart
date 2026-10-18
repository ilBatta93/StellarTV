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
import '../widgets/tv_focusable.dart';
import 'login_screen.dart';
import 'profile_picker_screen.dart';

/// Optional sign-in for TVs: shows a QR and a 6-character code. The user
/// approves them from the website (Collega TV) and this device signs in
/// automatically — no email or password typed with the remote.
class TvPairingScreen extends StatefulWidget {
  const TvPairingScreen({super.key, this.service});
  final TvPairingService? service;

  @override
  State<TvPairingScreen> createState() => _TvPairingScreenState();
}

class _TvPairingScreenState extends State<TvPairingScreen> {
  late final _service =
      widget.service ?? TvPairingService(Supabase.instance.client);
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/branding/stellar_space.jpg',
            fit: BoxFit.cover,
            cacheWidth: 1920,
            excludeFromSemantics: true,
          ),
          ColoredBox(color: AppColors.background.withValues(alpha: .45)),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, bounds) {
                final wide = bounds.maxWidth >= 760;
                final intro = Column(
                  crossAxisAlignment: wide
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandLogo(size: 46),
                    const SizedBox(height: 30),
                    Text(
                      'La tua TV.\nIl tuo StellarTV.',
                      textAlign: wide ? TextAlign.left : TextAlign.center,
                      style: const TextStyle(
                        fontSize: 34,
                        height: 1.12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Inquadra il QR con il telefono\ne autorizza l’accesso al tuo account.',
                      textAlign: wide ? TextAlign.left : TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'stellartv.lovable.app/collega',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TvFocusable(
                      autofocus: true,
                      focusedScale: 1,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_back_rounded,
                              size: 20,
                              color: AppColors.textSecondary,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Accedi con email',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
                final code = _pairing;
                final qr = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error case final error?) ...[
                      Text(
                        error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error),
                      ),
                      const SizedBox(height: 16),
                      TvFocusable(
                        onPressed: _start,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Riprova'),
                        ),
                      ),
                    ],
                    if (code == null && _error == null)
                      const SizedBox(
                        width: 232,
                        height: 232,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (code != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.qrSurface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: QrImageView(
                          data: code.url,
                          version: QrVersions.auto,
                          size: 200,
                          backgroundColor: AppColors.qrSurface,
                          eyeStyle: const QrEyeStyle(color: AppColors.qrInk),
                          dataModuleStyle: const QrDataModuleStyle(
                            color: AppColors.qrInk,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        code.code,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Scade tra ${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _completing
                            ? 'Accesso in corso…'
                            : 'In attesa di autorizzazione',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                );
                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 48 : 24,
                      vertical: 28,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1040),
                      child: wide
                          ? Row(
                              children: [
                                Expanded(child: intro),
                                const SizedBox(width: 64),
                                SizedBox(width: 300, child: qr),
                              ],
                            )
                          : Column(
                              children: [intro, const SizedBox(height: 32), qr],
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
