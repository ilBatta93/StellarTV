import 'foreground_http_client.dart';
import 'foreground_policy.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'sync_service.dart';

final _foregroundHttp = ForegroundHttpClient();

/// The code is no longer valid. Callers must not exchange a token.
class PairingExpired implements Exception {
  const PairingExpired();
}

/// The network or the service could not be reached. Callers must not
/// exchange a token and must not treat this as an expired code.
class PairingOffline implements Exception {
  const PairingOffline();
}

/// One-shot TV pairing: the TV shows a code/QR, the user approves it from the
/// website (stellartv.lovable.app/collega) and this device receives a
/// magic-link token that signs it in. No password ever travels to the TV.
class TvPairingService {
  TvPairingService(this._client);

  final SupabaseClient _client;

  static const _base = '${SupabaseConfig.apiBase}/pair';

  Future<TvPairing> create({String deviceName = 'TV'}) async {
    final http.Response res;
    try {
      res = await _foregroundHttp
          .post(
            Uri.parse(_base),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'device_name': deviceName}),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const PairingOffline();
    } on SocketException {
      throw const PairingOffline();
    } on HandshakeException {
      throw const PairingOffline();
    } on http.ClientException {
      throw const PairingOffline();
    }
    if (res.statusCode != 200) throw const PairingOffline();
    final json = _jsonMap(res.body);
    final code = json['code'];
    final secret = json['secret'];
    if (code is! String ||
        code.isEmpty ||
        secret is! String ||
        secret.isEmpty) {
      throw const PairingOffline();
    }
    return TvPairing(
      code: code,
      secret: secret,
      url: json['url'] as String? ?? 'https://stellartv.lovable.app/collega',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 600,
    );
  }

  /// Magic-link token only after the website approved the code.
  ///
  /// Null means the code is still waiting: do not call verifyOTP.
  /// [PairingExpired] means the code is gone. [PairingOffline] means this
  /// poll could not tell, so the same code stays on screen.
  Future<String?> pollToken(TvPairing pairing) async {
    if (!ForegroundPolicy.instance.active) return null;
    final uri = Uri.parse(
      '$_base?code=${Uri.encodeComponent(pairing.code)}&secret=${pairing.secret}',
    );
    final http.Response res;
    try {
      res = await _foregroundHttp.get(uri).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const PairingOffline();
    } on SocketException {
      throw const PairingOffline();
    } on HandshakeException {
      throw const PairingOffline();
    } on http.ClientException catch (error) {
      if (error.message.contains('sospesa')) return null;
      throw const PairingOffline();
    }
    return _tokenFromPoll(res.statusCode, res.body);
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

String? _tokenFromPoll(int statusCode, String body) {
  if (statusCode == 400 || statusCode == 404 || statusCode == 410) {
    throw const PairingExpired();
  }
  if (statusCode != 200) throw const PairingOffline();
  final json = _jsonMap(body);
  final status = json['status'];
  if (status == 'expired' || status == 'not_found')
    throw const PairingExpired();
  if (status != 'approved') return null;
  final token = json['token_hash'];
  if (token is! String || token.isEmpty) return null;
  return token;
}

Map<String, dynamic> _jsonMap(String body) {
  try {
    final json = jsonDecode(body);
    if (json is Map<String, dynamic>) return json;
    if (json is Map) return Map<String, dynamic>.from(json);
  } on FormatException {
    throw const PairingOffline();
  }
  throw const PairingOffline();
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
