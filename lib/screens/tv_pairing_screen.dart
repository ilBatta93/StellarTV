import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/app_provider.dart';
import '../providers/history_provider.dart';
import '../providers/sync_provider.dart';
import '../services/tv_pairing_service.dart';
import '../services/key_handoff.dart';

import 'package:cryptography/cryptography.dart';

import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/phone_tap.dart';
import '../widgets/tv_focusable.dart';
import 'login_screen.dart';
import 'profile_picker_screen.dart';

/// Visual steps of the QR sign-in. The token is requested only in [signingIn].
enum PairPhase { creating, waiting, signingIn, receiving, offline, expired }

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
  /// Phone handoff window. Matches the ten-minute cloud row, not a shorter wait.
  static const _phoneWaitSeconds = 600;
  static const _noticeSeconds = 5;

  late final _service =
      widget.service ?? TvPairingService(Supabase.instance.client);
  TvPairing? _pairing;
  Timer? _poll;
  Timer? _countdown;
  int _secondsLeft = 0;
  int _generation = 0;
  int _noticeLeft = 0;
  PairPhase _phase = PairPhase.creating;
  String? _detail;
  String? _notice;
  bool _completing = false;
  bool _polling = false;
  // QR login extra: the phone can send source details/key right after approving.
  SimpleKeyPair? _pair;
  String _qrUrl = '';
  KeyHandoff? _receiver;
  int _phoneLeft = _phoneWaitSeconds;
  String _phoneStatus = '';

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _countdown?.cancel();
    _receiver?.cancel();
    super.dispose();
  }

  bool get _busyPhase =>
      _completing ||
      _phase == PairPhase.signingIn ||
      _phase == PairPhase.receiving;

  String get _statusLine {
    if (_detail != null &&
        (_phase == PairPhase.offline ||
            _phase == PairPhase.expired ||
            _phase == PairPhase.creating)) {
      return _detail!;
    }
    return switch (_phase) {
      PairPhase.creating => 'Preparazione del codice…',
      PairPhase.waiting => 'In attesa di autorizzazione',
      PairPhase.signingIn => 'Accesso in corso…',
      PairPhase.receiving => '',
      PairPhase.offline => 'Connessione assente. Il codice resta valido.',
      PairPhase.expired => 'Codice scaduto: te ne mostro uno nuovo.',
    };
  }

  Future<void> _start({bool refreshed = false}) async {
    if (_busyPhase) return;
    _poll?.cancel();
    _countdown?.cancel();
    final generation = ++_generation;
    setState(() {
      _notice = refreshed ? 'Codice aggiornato' : null;
      if (!refreshed) {
        _pairing = null;
        _detail = null;
        _phase = PairPhase.creating;
      } else if (_phase != PairPhase.expired && _phase != PairPhase.offline) {
        _detail = null;
        _phase = PairPhase.creating;
      }
    });
    try {
      final pairing = await _service.create();
      final pair = await KeyHandoff.newPair();
      final pub = await KeyHandoff.publicOf(pair);
      if (!mounted || generation != _generation || _busyPhase) return;
      setState(() {
        _pair = pair;
        _qrUrl = '${pairing.url}${pairing.url.contains('?') ? '&' : '?'}k=$pub';
        _pairing = pairing;
        _secondsLeft = pairing.expiresIn;
        _phase = PairPhase.waiting;
        _detail = null;
        _noticeLeft = _notice == null ? 0 : _noticeSeconds;
      });
      _arm(generation);
    } on PairingOffline {
      _failStart(generation);
    } catch (_) {
      _failStart(generation);
    }
  }

  void _failStart(int generation) {
    if (!mounted || generation != _generation || _busyPhase) return;
    final kept = _pairing != null;
    setState(() {
      _phase = PairPhase.offline;
      _detail = kept
          ? 'Connessione assente. Il codice resta valido.'
          : 'Connessione non riuscita. Riprova.';
      if (kept && _secondsLeft <= 1) _secondsLeft = 15;
    });
    if (kept) _arm(generation);
  }

  void _arm(int generation) {
    _countdown?.cancel();
    _poll?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || generation != _generation) {
        timer.cancel();
        return;
      }
      if (_busyPhase) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() {
          _secondsLeft = 0;
          _notice = 'Codice aggiornato';
        });
        unawaited(_start(refreshed: true));
        return;
      }
      setState(() {
        _secondsLeft--;
        if (_noticeLeft > 0) {
          _noticeLeft--;
          if (_noticeLeft == 0) _notice = null;
        }
      });
    });
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_check(generation));
    });
  }

  Future<void> _check(int generation) async {
    final pairing = _pairing;
    if (pairing == null ||
        _polling ||
        _busyPhase ||
        generation != _generation) {
      return;
    }
    _polling = true;
    try {
      final token = await _service.pollToken(pairing);
      if (!mounted || _busyPhase) return;
      if (token != null) {
        await _signIn(pairing, token);
        return;
      }
      if (generation != _generation) return;
      if (_phase == PairPhase.offline || _phase == PairPhase.expired) {
        setState(() {
          _phase = PairPhase.waiting;
          _detail = null;
        });
      }
    } on PairingExpired {
      if (!mounted || generation != _generation || _busyPhase) return;
      setState(() {
        _phase = PairPhase.expired;
        _detail = 'Codice scaduto: te ne mostro uno nuovo.';
        _notice = 'Codice aggiornato';
      });
      unawaited(_start(refreshed: true));
    } on PairingOffline {
      _showOffline(generation);
    } on _PhoneDone {
      return;
    } catch (_) {
      _showOffline(generation);
    } finally {
      _polling = false;
    }
  }

  Future<void> _signIn(TvPairing pairing, String token) async {
    if (_completing) return;
    _completing = true;
    _generation++;
    _poll?.cancel();
    _countdown?.cancel();
    setState(() {
      _phase = PairPhase.signingIn;
      _detail = null;
      _notice = null;
    });
    try {
      await _service.completeWithToken(token);
      if (!mounted) return;
      await _waitForPhone(pairing.code);
    } on _PhoneDone {
      return;
    } catch (_) {
      if (!mounted) return;
      _completing = false;
      setState(() {
        _phase = PairPhase.offline;
        _detail = 'Accesso non riuscito. Te ne mostro uno nuovo.';
        _notice = 'Codice aggiornato';
      });
      unawaited(_start(refreshed: true));
    }
  }

  void _showOffline(int generation) {
    if (!mounted || generation != _generation || _busyPhase) return;
    if (_phase == PairPhase.offline) return;
    setState(() {
      _phase = PairPhase.offline;
      _detail = 'Connessione assente. Il codice resta valido.';
    });
  }

  /// After sign-in, gives the phone ten minutes to send source details and/or
  /// the recovery key (sealed for [_pair]); "Salta" continues as before.
  Future<void> _waitForPhone(String code) async {
    final pair = _pair;
    if (pair != null) {
      final r = KeyHandoff(Supabase.instance.client);
      try {
        await r.startWith(pair, code);
        if (!mounted) return;
        _receiver = r;
        setState(() {
          _phase = PairPhase.receiving;
          _phoneLeft = _phoneWaitSeconds;
          _detail = null;
          _notice = null;
        });
        _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
          if (!mounted || _phase != PairPhase.receiving) return;
          setState(() => _phoneLeft -= 2);
          try {
            final raw = await r.poll();
            if (raw == null) {
              if (_phoneLeft <= 0) _finish(null);
              return;
            }
            _finish(BundleHandoff.parse(raw));
          } catch (_) {
            _finish(null);
          }
        });
        throw _PhoneDone();
      } on _PhoneDone {
        rethrow;
      } catch (_) {
        // Receiver unavailable: continue with the normal sign-in.
      }
    }
    await _finish(null);
    throw _PhoneDone();
  }

  bool _finished = false;
  Future<void> _finish(BundleHandoff? bundle) async {
    if (_finished) return;
    _finished = true;
    _poll?.cancel();
    _receiver?.cancel();
    _receiver?.forget();
    _pair = null;
    if (!mounted) return;
    setState(() => _phoneStatus = 'Configurazione in corso…');
    final history = context.read<HistoryProvider>();
    final sync = context.read<SyncProvider>();
    if (bundle?.key case final key?) {
      try {
        await sync.authorizeVault(key);
      } catch (_) {}
    }
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
    final x = bundle?.xtream;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => x != null
            ? LoginScreen(initial: x)
            : app.isAuthenticated
            ? const ProfilePickerScreen()
            : const LoginScreen(),
      ),
      (_) => false,
    );
  }

  Widget _phoneWait() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(
        Icons.smartphone_rounded,
        size: 56,
        color: AppColors.textPrimary,
      ),
      const SizedBox(height: 18),
      Text(
        _phoneStatus.isNotEmpty ? _phoneStatus : 'Accesso riuscito.\nOra sul telefono inserisci i dati della lista\no la chiave di recupero: la TV si configura da sola.',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 18,
          height: 1.4,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 12),
      if (_phoneStatus.isEmpty)
        Text(
          '${_phoneLeft.clamp(0, _phoneWaitSeconds)} s',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      const SizedBox(height: 20),
      if (_phoneStatus.isEmpty)
        TvFocusable(
          autofocus: true,
          onPressed: () => _finish(null),
          child: PhoneTap(
            onTap: () => _finish(null),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: Text('Salta'),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBrandCanvas,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: kBrandCanvas),
          SafeArea(
            child: _phase == PairPhase.receiving
                ? Center(child: _phoneWait())
                : LayoutBuilder(
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
                            child: PhoneTap(
                              onTap: () => Navigator.of(context).pop(),
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
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                      final code = _pairing;
                      final signingIn = _phase == PairPhase.signingIn;
                      final alert =
                          _phase == PairPhase.offline ||
                          _phase == PairPhase.expired;
                      final qr = Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (code == null && _phase == PairPhase.creating)
                            const SizedBox(
                              width: 232,
                              height: 232,
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (code != null) ...[
                            Opacity(
                              opacity: signingIn ? 0.35 : 1,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppColors.qrSurface,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: QrImageView(
                                      data: _qrUrl.isEmpty ? code.url : _qrUrl,
                                      version: QrVersions.auto,
                                      size: 200,
                                      backgroundColor: AppColors.qrSurface,
                                      eyeStyle: const QrEyeStyle(
                                        color: AppColors.qrInk,
                                      ),
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
                                ],
                              ),
                            ),
                            if (!signingIn) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Scade tra ${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                            if (_notice != null && !signingIn) ...[
                              const SizedBox(height: 12),
                              Text(
                                _notice!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Text(
                              _statusLine,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: alert
                                    ? AppColors.error
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                          if (_phase == PairPhase.offline && code == null) ...[
                            Text(
                              _detail ?? 'Connessione non riuscita. Riprova.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.error),
                            ),
                            const SizedBox(height: 16),
                            TvFocusable(
                              onPressed: () => _start(),
                              child: PhoneTap(
                                onTap: () => _start(),
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text('Riprova'),
                                ),
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
                                    children: [
                                      intro,
                                      const SizedBox(height: 32),
                                      qr,
                                    ],
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

class _PhoneDone implements Exception {}
