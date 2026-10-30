import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/key_handoff.dart';
import 'tv_focusable.dart';

/// Compact phone-to-TV panel: QR on the left, code, timer and Annulla on the
/// right, so it fits a 540p TV screen without scrolling.
class PhoneHandoffPanel extends StatefulWidget {
  const PhoneHandoffPanel({
    super.key,
    required this.onReceived,
    required this.onClose,
    this.mode = '',
  });
  final String mode;
  final ValueChanged<String> onReceived;
  final ValueChanged<String?> onClose;
  @override
  State<PhoneHandoffPanel> createState() => _PhoneHandoffPanelState();
}

class _PhoneHandoffPanelState extends State<PhoneHandoffPanel> {
  KeyHandoff? _h;
  Timer? _poll;
  int _left = 600;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final h = KeyHandoff(Supabase.instance.client, mode: widget.mode);
    try {
      await h.start();
    } catch (_) {
      _finish('Codice non creato. Verifica la connessione e riprova.');
      return;
    }
    if (!mounted) {
      h.cancel();
      return;
    }
    setState(() => _h = h);
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _done) return;
      setState(() => _left -= 2);
      try {
        final secret = await h.poll();
        if (secret == null) {
          if (_left <= 0) throw TimeoutException('scaduto');
          return;
        }
        _stop();
        widget.onReceived(secret);
      } catch (_) {
        _finish('Codice scaduto o non valido. Generane uno nuovo.');
      }
    });
  }

  void _stop() {
    _done = true;
    _poll?.cancel();
    _h?.cancel();
    _h?.forget();
  }

  void _finish(String? message) {
    if (_done) return;
    _stop();
    widget.onClose(message);
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _h;
    final scheme = Theme.of(context).colorScheme;
    if (h == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            color: scheme.onSurface,
            padding: const EdgeInsets.all(6),
            child: QrImageView(
              data: h.link,
              size: 150,
              padding: EdgeInsets.zero,
              backgroundColor: scheme.onSurface,
              eyeStyle: QrEyeStyle(color: scheme.surface),
              dataModuleStyle: QrDataModuleStyle(color: scheme.surface),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Inquadra il QR o apri stellartv.vercel.app/chiave',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  h.code,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                  ),
                ),
                Text(
                  'In attesa del telefono… ${_left.clamp(0, 600)} s',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 6),
                TvFocusable(
                  autofocus: true,
                  onPressed: () => _finish(null),
                  child: OutlinedButton.icon(
                    onPressed: () => _finish(null),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Annulla'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
