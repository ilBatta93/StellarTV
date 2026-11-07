import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../config/trakt_config.dart';
import '../models/trakt_policy.dart';
import 'service_keys.dart';

class TraktException implements Exception {
  const TraktException(this.message, {this.status});
  final String message;
  final int? status;

  /// The sign-in is no longer valid: the profile must connect again.
  bool get signedOut => status == 401 || status == 403;
  @override
  String toString() => message;
}

/// Code shown on the TV while the user approves on trakt.tv.
class TraktDeviceCode {
  const TraktDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.expiresIn,
    required this.interval,
    required this.clientId,
    required this.own,
    required this.verifier,
  });
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final Duration expiresIn;
  final Duration interval;
  final String clientId;
  final bool own;

  /// PKCE verifier: proves the approval is collected by this device.
  final String verifier;
}

enum TraktPollState { pending, ok, expired, denied, slowDown, invalid, error }

/// Trakt sign-in and API calls, straight from the device. Sign-in is the
/// device flow with PKCE: Trakt needs only the Client ID (StellarTV's, or
/// the user's own), no secret. The user's sign-in stays on this device.
class TraktClient {
  TraktClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static const apiBase = 'https://api.trakt.tv';

  /// Login host. Trakt moves sign-in to auth.trakt.tv (enforced
  /// 2027-02-01).
  static const authBase = 'https://api.trakt.tv';

  /// Redirect address registered on the Trakt app. The device sign-in never
  /// opens it, but renewals repeat it.
  static const redirect = 'http://localhost';
  static const _timeout = Duration(seconds: 20);

  /// True when some Trakt app is available: StellarTV's or the user's.
  static bool get available =>
      TraktConfig.clientId.isNotEmpty || ServiceKeys.instance.traktOwn;

  Map<String, String> _headers(String clientId, [String? access]) => {
    'Content-Type': 'application/json',
    'trakt-api-version': '2',
    'trakt-api-key': clientId,
    'User-Agent': 'StellarTV',
    if (access != null) 'Authorization': 'Bearer $access',
  };

  Future<http.Response> _postAuth(
    String path,
    String clientId,
    Map<String, String> body,
  ) async {
    try {
      return await _http
          .post(
            Uri.parse('$authBase$path'),
            headers: _headers(clientId),
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } catch (_) {
      throw const TraktException('Connessione non disponibile');
    }
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// Client secret only for the user's own Trakt apps created before Trakt
  /// stopped issuing them; never for StellarTV's.
  static Map<String, String> _secret(bool own) {
    final secret = ServiceKeys.instance.traktClientSecret;
    return own && secret.isNotEmpty ? {'client_secret': secret} : const {};
  }

  static String _newVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(48, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String challengeOf(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  /// Starts a device sign-in with the user's keys when set, else StellarTV's.
  Future<TraktDeviceCode> startDevice() async {
    final keys = ServiceKeys.instance;
    await keys.load();
    final own = keys.traktOwn;
    final clientId = own ? keys.traktClientId : TraktConfig.clientId;
    if (clientId.isEmpty) {
      throw const TraktException(
        'Trakt non è disponibile: inserisci il Client ID della tua app Trakt',
      );
    }
    final verifier = _newVerifier();
    final res = await _postAuth('/oauth/device/code', clientId, {
      'client_id': clientId,
      'code_challenge': challengeOf(verifier),
      'code_challenge_method': 'S256',
    });
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw TraktException(
        own
            ? 'Il Client ID inserito non è valido'
            : 'Trakt non accetta l\'app in questo momento',
      );
    }
    if (res.statusCode == 429) {
      throw const TraktException('Trakt è occupato, riprova fra poco');
    }
    final body = _decode(res.body);
    if (res.statusCode != 200 || body is! Map) {
      throw const TraktException('Codice non creato, riprova');
    }
    final device = body['device_code'], user = body['user_code'];
    if (device is! String || user is! String) {
      throw const TraktException('Codice non creato, riprova');
    }
    final url = body['verification_url'];
    return TraktDeviceCode(
      deviceCode: device,
      userCode: user,
      verificationUrl: url is String && url.startsWith('https://')
          ? url
          : 'https://trakt.tv/activate',
      expiresIn: Duration(
        seconds: (body['expires_in'] as num?)?.toInt() ?? 600,
      ),
      interval: Duration(seconds: (body['interval'] as num?)?.toInt() ?? 5),
      clientId: clientId,
      own: own,
      verifier: verifier,
    );
  }

  /// One poll of a device sign-in; the session once approved.
  Future<(TraktPollState, TraktSession?)> pollDevice(
    TraktDeviceCode code,
  ) async {
    final res = await _postAuth('/oauth/device/token', code.clientId, {
      'code': code.deviceCode,
      'client_id': code.clientId,
      'code_verifier': code.verifier,
      ..._secret(code.own),
    });
    final state = switch (res.statusCode) {
      200 => TraktPollState.ok,
      400 => TraktPollState.pending,
      404 || 409 => TraktPollState.invalid,
      410 => TraktPollState.expired,
      418 => TraktPollState.denied,
      429 => TraktPollState.slowDown,
      _ => TraktPollState.error,
    };
    if (state != TraktPollState.ok) return (state, null);
    final session = TraktSession.fromTokens(
      _decode(res.body),
      clientId: code.clientId,
      own: code.own,
    );
    return session == null
        ? (TraktPollState.error, null)
        : (TraktPollState.ok, session);
  }

  /// New sign-in from the refresh value (Trakt rotates both).
  Future<TraktSession> refresh(TraktSession session) async {
    await ServiceKeys.instance.load();
    if (session.own && ServiceKeys.instance.traktClientId != session.clientId) {
      throw const TraktException('Chiavi Trakt cambiate', status: 401);
    }
    final res = await _postAuth('/oauth/token', session.clientId, {
      'refresh_token': session.refreshToken,
      'client_id': session.clientId,
      'redirect_uri': redirect,
      'grant_type': 'refresh_token',
      ..._secret(session.own),
    });
    if (res.statusCode == 400 || res.statusCode == 401) {
      throw const TraktException('Accesso a Trakt scaduto', status: 401);
    }
    final next = res.statusCode == 200
        ? TraktSession.fromTokens(
            _decode(res.body),
            clientId: session.clientId,
            own: session.own,
            user: session.user,
          )
        : null;
    if (next == null) throw const TraktException('Rinnovo non riuscito');
    return next;
  }

  /// Best effort: the sign-in is forgotten here either way.
  Future<void> revoke(TraktSession session) async {
    try {
      await _postAuth('/oauth/revoke', session.clientId, {
        'token': session.accessToken,
        'client_id': session.clientId,
        ..._secret(session.own),
      });
    } catch (_) {}
  }

  /// Authenticated API call. Returns the decoded body (null when empty), or
  /// the text with [raw] (large lists are decoded off the UI isolate).
  /// 401/403 mean the sign-in is gone; 409 on a scrobble means "already
  /// counted" and is returned as null.
  Future<Object?> call(
    TraktSession session,
    String method,
    String path, {
    Object? body,
    bool raw = false,
  }) async {
    final uri = Uri.parse('$apiBase$path');
    final headers = _headers(session.clientId, session.accessToken);
    final http.Response res;
    try {
      res =
          await (method == 'GET'
                  ? _http.get(uri, headers: headers)
                  : _http.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(_timeout);
    } catch (_) {
      throw const TraktException('Connessione non disponibile');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw TraktException('Accesso a Trakt scaduto', status: res.statusCode);
    }
    if (res.statusCode == 409) return null;
    if (res.statusCode == 429) {
      throw const TraktException('Trakt è occupato, riprova fra poco');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw TraktException('Trakt non risponde', status: res.statusCode);
    }
    if (raw) return res.body;
    return res.body.isEmpty ? null : _decode(res.body);
  }
}
