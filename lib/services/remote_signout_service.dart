import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Honors "disconnect this device" requests made from the account website.
/// The website only leaves a one-shot request; this app signs itself out
/// locally, so other devices and Auth sessions are never touched remotely.
class RemoteSignoutService {
  final SupabaseClient client;
  final Future<void> Function() onSignOut;
  Timer? _timer;
  bool _checking = false;

  RemoteSignoutService(this.client, this.onSignOut);

  static String? sessionIdFromToken(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final id = claims is Map ? claims['session_id'] : null;
      return id is String && id.isNotEmpty ? id : null;
    } catch (_) {
      return null;
    }
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => check());
    unawaited(check());
  }

  Future<bool> check() async {
    if (_checking) return false;
    final id = sessionIdFromToken(client.auth.currentSession?.accessToken);
    if (id == null) return false;
    _checking = true;
    try {
      final rows = await client
          .from('session_signout_requests')
          .select('session_id')
          .eq('session_id', id)
          .limit(1);
      if (rows.isEmpty) return false;
      await client.from('session_signout_requests').delete().eq('session_id', id);
      await onSignOut();
      return true;
    } catch (_) {
      return false; // Offline: retried on the next tick.
    } finally {
      _checking = false;
    }
  }

  void dispose() => _timer?.cancel();
}
