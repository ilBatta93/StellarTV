import 'dart:async';

import 'foreground_policy.dart';

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Receives the recovery key typed on a phone. The X25519 private key lives
/// only in memory; the cloud row holds public keys and AES-GCM ciphertext and
/// is deleted as soon as it is read (or after ten minutes).
class KeyHandoff {
  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const siteUrl = 'https://stellartv.lovable.app/chiave';
  static final _x = X25519();
  static final _aes = AesGcm.with256bits();

  static String b64u(List<int> b) => base64Url.encode(b).replaceAll('=', '');
  static List<int> fromB64u(String s) =>
      base64Url.decode(s + '=' * ((4 - s.length % 4) % 4));

  static String newCode([Random? rnd]) {
    final r = rnd ?? Random.secure();
    return List.generate(6, (_) => alphabet[r.nextInt(alphabet.length)]).join();
  }

  static Future<SecretKey> _key(List<int> shared, String code) =>
      Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(shared),
        nonce: const [],
        info: utf8.encode('STV-HANDOFF-1|$code'),
      );

  /// Opens the phone package. Throws on any tampering.
  static Future<String> open(
    SimpleKeyPair receiver,
    String code,
    String senderKey,
    String nonce,
    String ciphertext,
  ) async {
    final shared = await _x.sharedSecretKey(
      keyPair: receiver,
      remotePublicKey: SimplePublicKey(
        fromB64u(senderKey),
        type: KeyPairType.x25519,
      ),
    );
    final ct = fromB64u(ciphertext);
    final plain = await _aes.decrypt(
      SecretBox(
        ct.sublist(0, ct.length - 16),
        nonce: fromB64u(nonce),
        mac: Mac(ct.sublist(ct.length - 16)),
      ),
      secretKey: await _key(await shared.extractBytes(), code),
      aad: utf8.encode(code),
    );
    return utf8.decode(plain);
  }

  final SupabaseClient _client;
  KeyHandoff(this._client, {this.mode = ''});

  /// '' = recovery key, 'x' = Xtream list details.
  final String mode;
  SimpleKeyPair? _pair;
  String? _id;
  String code = '';
  String publicKey = '';

  String get link =>
      '$siteUrl?c=$code&k=$publicKey${mode.isEmpty ? '' : '&m=$mode'}';

  /// QR login: the TV made [pair] before pairing and put its public key in
  /// the QR; once signed in it opens the receiver under the pairing [fixed]
  /// code, so the phone can send list details without a second scan.
  Future<void> startWith(SimpleKeyPair pair, String fixed) async {
    await cancel();
    _pair = pair;
    publicKey = b64u((await pair.extractPublicKey()).bytes);
    code = fixed;
    final row = await _client
        .from('key_handoffs')
        .insert({'code': code, 'receiver_key': publicKey})
        .select('id')
        .single();
    _id = row['id'] as String;
  }

  static Future<SimpleKeyPair> newPair() => _x.newKeyPair();
  static Future<String> publicOf(SimpleKeyPair p) async =>
      b64u((await p.extractPublicKey()).bytes);

  Future<void> start() async {
    await cancel();
    _pair = await _x.newKeyPair();
    publicKey = b64u((await _pair!.extractPublicKey()).bytes);
    for (var i = 0; i < 3; i++) {
      code = newCode();
      try {
        final row = await _client
            .from('key_handoffs')
            .insert({'code': code, 'receiver_key': publicKey})
            .select('id')
            .single();
        _id = row['id'] as String;
        return;
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow; // retry only on duplicate code
      }
    }
    throw StateError('Codice non disponibile');
  }

  /// Returns the key once the phone has sent it, null while waiting.
  Future<String?> poll() async {
    final id = _id, pair = _pair;
    if (!ForegroundPolicy.instance.active || id == null || pair == null)
      return null;
    final row = await _client
        .from('key_handoffs')
        .select('sender_key, nonce, ciphertext')
        .eq('id', id)
        .maybeSingle();
    if (row == null) throw TimeoutException('Codice scaduto');
    if (row['ciphertext'] == null) return null;
    await cancel(); // one-shot: delete before using the key
    return open(
      pair,
      code,
      row['sender_key'] as String,
      row['nonce'] as String,
      row['ciphertext'] as String,
    );
  }

  Future<void> cancel() async {
    final id = _id;
    _id = null;
    if (id != null) {
      try {
        await _client.from('key_handoffs').delete().eq('id', id);
      } catch (_) {}
    }
  }

  void forget() => _pair = null;
}

/// Xtream details sent from the phone; shape-validated before use.
class XtreamHandoff {
  const XtreamHandoff(this.server, this.username, this.password);
  final String server, username, password;
  static XtreamHandoff? parse(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map || j['kind'] != 'xtream') return null;
      final h = j['host'], u = j['username'], p = j['password'];
      if (h is! String || u is! String || p is! String) return null;
      final uri = Uri.tryParse(h);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          u.isEmpty ||
          p.isEmpty)
        return null;
      return XtreamHandoff(h, u, p);
    } catch (_) {
      return null;
    }
  }
}

/// QR-login bundle sent from the phone: optional list details and/or key.
class BundleHandoff {
  const BundleHandoff(this.xtream, this.key);
  final XtreamHandoff? xtream;
  final String? key;
  static BundleHandoff? parse(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map || j['kind'] != 'bundle') return null;
      final x = j['xtream'] is Map
          ? XtreamHandoff.parse(
              jsonEncode({...j['xtream'] as Map, 'kind': 'xtream'}),
            )
          : null;
      final k = j['key'];
      final key =
          k is String &&
              RegExp(r'^STV1-', caseSensitive: false).hasMatch(k.trim())
          ? k.trim()
          : null;
      if (x == null && key == null) return null;
      return BundleHandoff(x, key);
    } catch (_) {
      return null;
    }
  }
}
