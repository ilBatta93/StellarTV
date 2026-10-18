import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Receives the recovery key typed on a phone. The X25519 private key lives
/// only in memory; the cloud row holds public keys and AES-GCM ciphertext and
/// is deleted as soon as it is read (or after two minutes).
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
      remotePublicKey: SimplePublicKey(fromB64u(senderKey), type: KeyPairType.x25519),
    );
    final ct = fromB64u(ciphertext);
    final plain = await _aes.decrypt(
      SecretBox(ct.sublist(0, ct.length - 16),
          nonce: fromB64u(nonce), mac: Mac(ct.sublist(ct.length - 16))),
      secretKey: await _key(await shared.extractBytes(), code),
      aad: utf8.encode(code),
    );
    return utf8.decode(plain);
  }

  final SupabaseClient _client;
  KeyHandoff(this._client);
  SimpleKeyPair? _pair;
  String? _id;
  String code = '';
  String publicKey = '';

  String get link => '$siteUrl?c=$code&k=$publicKey';

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
    if (id == null || pair == null) return null;
    final row = await _client
        .from('key_handoffs')
        .select('sender_key, nonce, ciphertext')
        .eq('id', id)
        .maybeSingle();
    if (row == null) throw TimeoutException('Codice scaduto');
    if (row['ciphertext'] == null) return null;
    await cancel(); // one-shot: delete before using the key
    return open(pair, code, row['sender_key'] as String,
        row['nonce'] as String, row['ciphertext'] as String);
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
