import 'dart:async';

import 'foreground_policy.dart';
import '../models/source_access.dart';

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Receives the recovery key typed on a phone. The X25519 private key lives
/// only in memory; the cloud row holds public keys and AES-GCM ciphertext and
/// is deleted as soon as it is read (or after ten minutes).
class KeyHandoff {
  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const siteUrl = 'https://stellartv.vercel.app/chiave';
  static final _x = X25519();
  static final _aes = AesGcm.with256bits();

  static String b64u(List<int> b) => base64Url.encode(b).replaceAll('=', '');
  static List<int> fromB64u(String s) =>
      base64Url.decode(s + '=' * ((4 - s.length % 4) % 4));

  static String newCode([Random? rnd]) {
    final r = rnd ?? Random.secure();
    return List.generate(6, (_) => alphabet[r.nextInt(alphabet.length)]).join();
  }

  // Dart HMAC on purpose: the site's HKDF salt is empty, and Android's native
  // HMAC (cryptography_flutter) rejects an empty key without falling back.
  static Future<SecretKey> _key(List<int> shared, String code) =>
      Hkdf(hmac: DartHmac.sha256(), outputLength: 32).deriveKey(
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

  /// '' = recovery key, 'x' = access details for a login, 'e' = access
  /// details for an edit (only the fields to change).
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
    if (!ForegroundPolicy.instance.active || id == null || pair == null) {
      return null;
    }
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
          p.isEmpty) {
        return null;
      }
      return XtreamHandoff(h, u, p);
    } catch (_) {
      return null;
    }
  }
}

/// QR-login bundle sent from the phone: optional list details and/or key.
class BundleHandoff {
  const BundleHandoff(this.xtream, this.key, [this.source]);
  final XtreamHandoff? xtream;
  final String? key;

  /// Access of any kind (newer phone pages); the account field above stays
  /// for older ones.
  final SourcePatch? source;

  /// Access data to fill in on the TV, whichever form the phone used.
  SourcePatch? get access =>
      source ??
      (xtream == null
          ? null
          : SourcePatch(
              kind: SourceKind.account,
              server: xtream!.server,
              username: xtream!.username,
              password: xtream!.password,
            ));
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
      final source = j['source'] is Map
          ? SourceHandoff.fromMap({...j['source'] as Map, 'kind': 'source'})
          : null;
      if (x == null && key == null && source == null) return null;
      return BundleHandoff(x, key, source);
    } catch (_) {
      return null;
    }
  }
}

/// Access data sent from the phone: the old complete account message, or a
/// `source` message with its kind and only the fields the user filled in
/// (when editing, an empty field keeps the stored value).
class SourceHandoff {
  SourceHandoff._();

  static SourcePatch? parse(String raw) {
    try {
      final j = jsonDecode(raw);
      return j is Map ? fromMap(j) : null;
    } catch (_) {
      return null;
    }
  }

  static SourcePatch? fromMap(Map j) {
    if (j['kind'] == 'xtream') {
      final x = XtreamHandoff.parse(jsonEncode(j));
      return x == null
          ? null
          : SourcePatch(
              kind: SourceKind.account,
              server: x.server,
              username: x.username,
              password: x.password,
            );
    }
    if (j['kind'] != 'source') return null;
    final kind = switch (j['type']) {
      'account' => SourceKind.account,
      'link' => SourceKind.link,
      'portal' => SourceKind.portal,
      _ => null,
    };
    if (kind == null) return null;
    String? text(String key) {
      final v = j[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final host = text('host');
    if (host != null) {
      final uri = Uri.tryParse(host);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        return null;
      }
    }
    final rawPass = j['password'];
    String? user, pass;
    switch (kind) {
      case SourceKind.account:
        user = text('username');
        pass = rawPass is String && rawPass.isNotEmpty ? rawPass : null;
      case SourceKind.portal:
        final mac = text('mac');
        if (mac != null) {
          user = SourceAccess.normalizeMac(mac);
          if (user == null) return null;
        }
      case SourceKind.link:
        break;
    }
    final patch = SourcePatch(
      kind: kind,
      server: host,
      username: user,
      password: pass,
    );
    return patch.isEmpty ? null : patch;
  }
}
