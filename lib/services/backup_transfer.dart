import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'foreground_policy.dart';
import 'key_handoff.dart';

/// Moves a device backup between this app and the phone through the
/// companion site (`/backup`). The cloud rows only ever hold public keys and
/// AES-GCM ciphertext split in parts, and are deleted as soon as they are
/// read (or after twenty minutes, `backup_transfers_guard`).
///
/// Sealed form, twin of `src/lib/backupTransfer.ts` on the site:
/// base64url(senderPublicKey(32) | nonce(12) | ciphertext+tag), with the key
/// from X25519 + HKDF-SHA256 (empty salt, info `STV-BACKUP-1|code`) and
/// `STV-BACKUP-1|code|direction` as additional data.
class BackupTransfer {
  BackupTransfer(this._client, {required this.restore});

  static const siteUrl = 'https://stellartv.vercel.app/backup';

  /// Characters per cloud part (`backup_transfer_parts.data`).
  static const partChars = 524288;
  static const maxParts = 400;

  static final _x = X25519();
  static final _aes = AesGcm.with256bits();

  final SupabaseClient _client;

  /// false: this device sends its backup to the phone ('save').
  /// true: the phone sends a backup file to this device ('restore').
  final bool restore;
  String get direction => restore ? 'restore' : 'save';

  SimpleKeyPair? _pair;
  String? _id;
  String code = '';
  String publicKey = '';

  String get link => '$siteUrl?c=$code${restore ? '&m=r&k=$publicKey' : ''}';

  // Dart HMAC on purpose, as in KeyHandoff: Android's native HMAC rejects
  // the empty HKDF salt.
  static Future<SecretKey> _key(List<int> shared, String code) =>
      Hkdf(hmac: DartHmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(shared),
        nonce: const [],
        info: utf8.encode('STV-BACKUP-1|$code'),
      );

  static List<int> _aad(String code, String direction) =>
      utf8.encode('STV-BACKUP-1|$code|$direction');

  /// Seals [payload] for [receiverKey]. [senderSeed] and [nonce] only for
  /// tests (fixtures shared with the site).
  static Future<String> seal(
    String receiverKey,
    String code,
    String direction,
    List<int> payload, {
    List<int>? senderSeed,
    List<int>? nonce,
  }) async {
    final receiver = KeyHandoff.fromB64u(receiverKey);
    if (receiver.length != 32) throw const FormatException('Chiave non valida');
    final sender = senderSeed == null
        ? await _x.newKeyPair()
        : await _x.newKeyPairFromSeed(senderSeed);
    final shared = await _x.sharedSecretKey(
      keyPair: sender,
      remotePublicKey: SimplePublicKey(receiver, type: KeyPairType.x25519),
    );
    final box = await _aes.encrypt(
      payload,
      secretKey: await _key(await shared.extractBytes(), code),
      nonce: nonce ?? _aes.newNonce(),
      aad: _aad(code, direction),
    );
    final out = BytesBuilder(copy: false)
      ..add((await sender.extractPublicKey()).bytes)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return KeyHandoff.b64u(out.takeBytes());
  }

  /// Opens a sealed package. Throws on any tampering.
  static Future<List<int>> open(
    SimpleKeyPair receiver,
    String code,
    String direction,
    String sealed,
  ) async {
    final b = KeyHandoff.fromB64u(sealed);
    if (b.length < 32 + 12 + 16) throw const FormatException('Dati corti');
    final shared = await _x.sharedSecretKey(
      keyPair: receiver,
      remotePublicKey: SimplePublicKey(
        b.sublist(0, 32),
        type: KeyPairType.x25519,
      ),
    );
    return _aes.decrypt(
      SecretBox(
        b.sublist(44, b.length - 16),
        nonce: b.sublist(32, 44),
        mac: Mac(b.sublist(b.length - 16)),
      ),
      secretKey: await _key(await shared.extractBytes(), code),
      aad: _aad(code, direction),
    );
  }

  /// Splits sealed text into cloud parts.
  static List<String> split(String sealed) => [
    for (var i = 0; i < sealed.length; i += partChars)
      sealed.substring(i, min(i + partChars, sealed.length)),
  ];

  /// Opens the transfer row and shows its code.
  Future<void> start() async {
    await cancel();
    if (restore) {
      _pair = await _x.newKeyPair();
      publicKey = KeyHandoff.b64u((await _pair!.extractPublicKey()).bytes);
    }
    for (var i = 0; i < 3; i++) {
      code = KeyHandoff.newCode();
      try {
        if (restore) {
          // Works before signing in: the phone then approves a session of
          // this device's own (TV pairing).
          _id = await _client.rpc(
            'backup_restore_open',
            params: {'p_code': code, 'p_receiver_key': publicKey},
          ) as String;
          return;
        }
        final row = await _client
            .from('backup_transfers')
            .insert({'code': code, 'direction': direction})
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

  Future<Map<String, dynamic>?> _row() async {
    final id = _id;
    if (id == null) return null;
    return _client
        .from('backup_transfers')
        .select('receiver_key, parts')
        .eq('id', id)
        .maybeSingle();
  }

  /// Save: the phone's public key once its page is open, null while waiting.
  Future<String?> phoneKey() async {
    if (!ForegroundPolicy.instance.active) return null;
    final row = await _row();
    if (row == null) throw TimeoutException('Codice scaduto');
    return row['receiver_key'] as String?;
  }

  /// Save: seals [payload] for the phone and uploads it part by part.
  /// [onProgress] gets the share of parts sent, 0 to 1.
  Future<void> upload(
    List<int> payload,
    String phoneKey, {
    void Function(double)? onProgress,
  }) async {
    final id = _id;
    if (id == null) throw StateError('Trasferimento chiuso');
    final parts = split(await seal(phoneKey, code, direction, payload));
    if (parts.length > maxParts) throw StateError('Backup troppo grande');
    for (var i = 0; i < parts.length; i++) {
      await _retry(() async {
        try {
          await _client.from('backup_transfer_parts').insert({
            'transfer_id': id,
            'part': i,
            'data': parts[i],
          });
        } on PostgrestException catch (e) {
          // Already there: an earlier attempt arrived but its answer did not.
          if (e.code != '23505') rethrow;
        }
      });
      onProgress?.call((i + 1) / parts.length);
    }
    await _retry(
      () => _client
          .from('backup_transfers')
          .update({'parts': parts.length})
          .eq('id', id),
    );
  }

  /// Save: true once the phone has taken the backup (it deletes the row).
  Future<bool> taken() async {
    if (!ForegroundPolicy.instance.active) return false;
    return await _row() == null;
  }

  /// Restore: the backup sent by the phone, null while waiting.
  /// [onProgress] gets the share of parts read, 0 to 1.
  Future<List<int>?> receive({void Function(double)? onProgress}) async {
    final id = _id, pair = _pair;
    if (!ForegroundPolicy.instance.active || id == null || pair == null) {
      return null;
    }
    final keys = {'p_id': id, 'p_receiver_key': publicKey};
    final parts = await _client.rpc('backup_restore_status', params: keys);
    if (parts is! int || parts < 0) throw TimeoutException('Codice scaduto');
    if (parts == 0) return null;
    final text = StringBuffer();
    for (var i = 0; i < parts; i++) {
      final part = await _retry(
        () =>
            _client.rpc('backup_restore_part', params: {...keys, 'p_part': i}),
      );
      if (part is! String) throw StateError('Pezzo mancante');
      text.write(part);
      onProgress?.call((i + 1) / parts);
    }
    await cancel(); // one-shot: delete before using the data
    return open(pair, code, direction, text.toString());
  }

  Future<void> cancel() async {
    final id = _id;
    _id = null;
    if (id != null) {
      try {
        if (restore) {
          await _client.rpc(
            'backup_restore_close',
            params: {'p_id': id, 'p_receiver_key': publicKey},
          );
        } else {
          await _client.from('backup_transfers').delete().eq('id', id);
        }
      } catch (_) {}
    }
  }

  void forget() => _pair = null;

  /// A part sent or read again after a short network failure (three tries,
  /// two and four seconds apart). Refusals of the database are not retried.
  static Future<T> _retry<T>(Future<T> Function() run) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await run();
      } on PostgrestException {
        rethrow;
      } catch (_) {
        if (attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
    }
  }
}
