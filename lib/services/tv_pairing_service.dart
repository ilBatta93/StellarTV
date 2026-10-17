import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'sync_service.dart';

/// One-shot TV pairing: the TV shows a code/QR, the user approves it from the
/// website (stellartv.lovable.app/collega) and this device receives a
/// magic-link token that signs it in. No password ever travels to the TV.
class TvPairingService {
  TvPairingService(this._client);

  final SupabaseClient _client;

  static const _base = '${SupabaseConfig.apiBase}/pair';

  Future<TvPairing> create({String deviceName = 'TV'}) async {
    final res = await http
        .post(
          Uri.parse(_base),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'device_name': deviceName}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw StateError('Impossibile creare il codice di collegamento.');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return TvPairing(
      code: json['code'] as String,
      secret: json['secret'] as String,
      url: json['url'] as String? ?? 'https://stellartv.lovable.app/collega',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 600,
    );
  }

  /// Returns the magic-link token once the user approved the code on the
  /// website, null while still waiting. Throws when the code expired.
  Future<String?> pollToken(TvPairing pairing) async {
    final uri = Uri.parse(
      '$_base?code=${Uri.encodeComponent(pairing.code)}&secret=${pairing.secret}',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final status = json['status'];
    if (status == 'expired') throw StateError('Codice scaduto.');
    if (status != 'approved') return null;
    return json['token_hash'] as String?;
  }

  /// Exchanges the approved token for a real session on this device.
  Future<void> completeWithToken(String tokenHash) async {
    // The website hands over a token *hash*: passed as `token` (which needs
    // the e-mail too) the exchange failed and the TV stayed signed out.
    final res = await _client.auth.verifyOTP(
      type: OtpType.magiclink,
      tokenHash: tokenHash,
    );
    final id = res.session?.user.id ?? _client.auth.currentUser?.id;
    if (id == null) throw StateError('Accesso non riuscito.');
    // Same marker as a password sign-in, so the session is restored on reopen.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SyncService.codeKey, id);
  }
}

class TvPairing {
  final String code;
  final String secret;
  final String url;
  final int expiresIn;

  const TvPairing({
    required this.code,
    required this.secret,
    required this.url,
    required this.expiresIn,
  });
}
