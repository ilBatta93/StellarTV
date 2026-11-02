import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/services/personal_vault.dart';
import 'package:stellar_tv/services/sync_service.dart';

const _account = '00000000-0000-4000-8000-000000000001';

/// Minimal PostgREST stand-in for `personal_vaults` and its save RPC, with
/// counters for the requests the sync is expected to avoid.
class _FakeVaultServer {
  http.Response _reply(http.Request request, Object body, [int status = 200]) =>
      http.Response(
        jsonEncode(body),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );

  Map<String, dynamic>? row;
  int envelopeReads = 0, headReads = 0, saves = 0;

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/rpc/save_personal_vault')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final current = (row?['revision'] as int?) ?? 0;
      if (body['_expected_revision'] != current) {
        return _reply(request, {'code': '40001', 'message': 'conflict'}, 409);
      }
      saves++;
      row = {
        'envelope': body['_envelope'],
        'revision': current + 1,
        'updated_at': DateTime.utc(2026, 11, 2, 10, saves).toIso8601String(),
      };
      return _reply(request, current + 1);
    }
    final select = request.url.queryParameters['select'] ?? '';
    if (select.contains('envelope')) {
      envelopeReads++;
    } else {
      headReads++;
    }
    final fields = select.split(',');
    final rows = [
      if (row != null) {for (final f in fields) f: row![f]},
    ];
    final single = (request.headers['Accept'] ?? '').contains(
      'vnd.pgrst.object',
    );
    if (single) {
      return rows.isEmpty
          ? _reply(request, {'code': 'PGRST116', 'message': 'no rows'}, 406)
          : _reply(request, rows.first);
    }
    return _reply(request, rows);
  }

  /// Simulates another device saving [payload] at the next revision.
  Future<void> writeFromElsewhere(
    Map<String, dynamic> payload,
    String key,
  ) async {
    final current = (row?['revision'] as int?) ?? 0;
    row = {
      'envelope': await PersonalVault.encrypt(payload, key, _account),
      'revision': current + 1,
      'updated_at': DateTime.utc(2026, 11, 2, 12).toIso8601String(),
    };
  }
}

Future<SupabaseClient> _client(_FakeVaultServer server) async {
  final client = SupabaseClient(
    'https://example.test',
    'test',
    httpClient: MockClient(server.handle),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.setInitialSession(
    jsonEncode({
      'access_token': 'token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': _account,
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
  return client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final key = PersonalVault.generateKey();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'personal_vault_$_account': key,
    });
  });

  test('unchanged saves and pulls reuse the cached revision', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final server = _FakeVaultServer();
    final client = await _client(server);
    final sync = SyncService(client);

    expect(await sync.push(await sync.collectSnapshot(), _account), isNotNull);
    expect(server.saves, 1);
    final reads = server.envelopeReads;

    // Same data again: one revision read, no download, no write.
    expect(await sync.push(await sync.collectSnapshot(), _account), isNotNull);
    expect(server.saves, 1);
    expect(server.envelopeReads, reads);

    // First pull after the own save decrypts nothing new from the network.
    final first = await sync.pull(_account);
    expect(first.payload?.settings['theme_mode'], 'dark');
    expect(server.envelopeReads, reads);
    await sync.markApplied(_account, null, first.revision);

    final again = await sync.pull(_account);
    expect(again.unchanged, isTrue);
    expect(again.payload, isNull);
    expect(server.envelopeReads, reads);

    // A forced pull still returns the full copy.
    expect((await sync.pull(_account, force: true)).payload, isNotNull);
    await client.dispose();
  });

  test('a save from another device is downloaded once and merged', () async {
    SharedPreferences.setMockInitialValues({});
    final server = _FakeVaultServer();
    final client = await _client(server);
    final sync = SyncService(client);
    expect(await sync.push(await sync.collectSnapshot(), _account), isNotNull);
    final applied = (await sync.pull(_account)).revision;
    await sync.markApplied(_account, null, applied);

    await server.writeFromElsewhere({
      'history': {
        'a': {
          'id': 'a',
          'type': 'movie',
          'title': 'Sample',
          'watched': '2026-11-02T09:00:00Z',
        },
      },
    }, key);
    final reads = server.envelopeReads;
    final pulled = await sync.pull(_account);
    expect(pulled.unchanged, isFalse);
    expect(pulled.payload?.history.keys, contains('a'));
    expect(server.envelopeReads, reads + 1);

    // The push right after reuses that download.
    expect(await sync.push(await sync.collectSnapshot(), _account), isNotNull);
    expect(server.envelopeReads, reads + 1);
    await client.dispose();
  });

  test('a stale device does not revert a setting changed elsewhere', () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'dark',
      'ui_accent': 'blue',
    });
    final server = _FakeVaultServer();
    final client = await _client(server);
    final sync = SyncService(client);
    expect(await sync.push(await sync.collectSnapshot(), _account), isNotNull);

    // Elsewhere: theme changed. Here: only the accent changed.
    await server.writeFromElsewhere({
      'settings': {'theme_mode': 'light', 'ui_accent': 'blue'},
    }, key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ui_accent', 'red');
    expect(await sync.push(await sync.collectSnapshot(), _account), isNotNull);

    final cloud = (await sync.pull(_account, force: true)).payload!.settings;
    expect(cloud['theme_mode'], 'light');
    expect(cloud['ui_accent'], 'red');

    // The pull brings the remote theme here and keeps the local accent.
    await sync.applySnapshotSettings(cloud);
    expect(prefs.getString('theme_mode'), 'light');
    expect(prefs.getString('ui_accent'), 'red');
    await client.dispose();
  });

  test('resolveSettings keeps local changes and adopts untouched keys', () {
    final out = SyncService.resolveSettings(
      local: {'a': 1, 'b': 'x', 'c': true},
      remote: {'a': 2, 'b': 'y', 'c': false, 'd': 4},
      base: {'a': 1, 'b': 'old'},
    );
    // a: unchanged here -> remote; b: changed here -> local;
    // c: never synced -> local (previous behavior).
    expect(out, {'a': 2, 'b': 'x', 'c': true});
    expect(
      SyncService.resolveSettings(
        local: {'a': 1},
        remote: {'a': 2},
        base: null,
      ),
      {'a': 1},
    );
  });
}
