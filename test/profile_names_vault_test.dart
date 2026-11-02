import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/providers/profile_provider.dart';
import 'package:stellar_tv/services/personal_vault.dart';
import 'package:stellar_tv/services/profile_service.dart';
import 'package:stellar_tv/services/sync_service.dart';

const _account = '00000000-0000-4000-8000-000000000002';

/// `user_profiles` stand-in: keeps rows and records every name written.
class _FakeProfiles {
  final rows = <Map<String, dynamic>>[];
  final writtenNames = <String>[];

  Future<http.Response> handle(http.Request r) async {
    http.Response reply(Object body) => http.Response(
      jsonEncode(body),
      200,
      request: r,
      headers: {'content-type': 'application/json'},
    );
    if (!r.url.path.endsWith('/user_profiles')) return reply([]);
    final id = r.url.queryParameters['id']?.replaceFirst('eq.', '');
    switch (r.method) {
      case 'POST':
        final body = jsonDecode(r.body);
        final row = Map<String, dynamic>.from(body is List ? body.first : body)
          ..['id'] = 'p${rows.length + 1}'
          ..['created_at'] = '2026-11-0${rows.length + 1}T00:00:00Z';
        writtenNames.add(row['name'] as String);
        rows.add(row);
        return reply([row]);
      case 'PATCH':
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        for (final row in rows) {
          if (row['id'] == id) row.addAll(body);
        }
        if (body['name'] is String) writtenNames.add(body['name'] as String);
        return reply([]);
      case 'DELETE':
        rows.removeWhere((row) => row['id'] == id);
        return reply([]);
      default:
        return reply(rows);
    }
  }
}

Future<SupabaseClient> _client(_FakeProfiles server) async {
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

  test('a plain name moves to the vault and leaves the table only after a '
      'confirmed encrypted save', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'personal_vault_$_account': PersonalVault.generateKey(),
    });
    final server = _FakeProfiles()
      ..rows.add({
        'id': 'p1',
        'sync_code': _account,
        'name': 'Sample',
        'is_kids': true,
        'created_at': '2026-11-01T00:00:00Z',
      });
    final client = await _client(server);
    final sync = SyncService(client);
    final profiles = ProfileProvider(ProfileService(client), sync);

    await profiles.load();
    expect(profiles.items.single.name, 'Sample');
    expect(server.rows.single['name'], 'Sample', reason: 'not saved yet');
    final events = await ProfileService(client).nameEvents();
    expect(events['p1']['name'], 'Sample');

    // A save collected before the name was recorded proves nothing.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'sync_last_saved_snapshot',
      DateTime.utc(2020).toIso8601String(),
    );
    await profiles.load();
    expect(server.rows.single['name'], 'Sample');

    await prefs.setString(
      'sync_last_saved_snapshot',
      DateTime.now().add(const Duration(seconds: 5)).toIso8601String(),
    );
    await profiles.load();
    expect(server.rows.single['name'], '');
    await profiles.load();
    expect(profiles.items.single.name, 'Sample', reason: 'from the vault');
    expect(profiles.items.single.isKids, true);

    // New and renamed profiles never write a name to the table.
    final created = await profiles.create(
      name: 'Second',
      avatarKey: 'star',
      avatarColor: 'verde',
    );
    expect(created.name, 'Second');
    await profiles.update(created, name: 'Renamed');
    expect(server.writtenNames.where((n) => n.isNotEmpty), isEmpty);
    await profiles.load();
    expect(profiles.items.map((p) => p.name), ['Sample', 'Renamed']);

    await profiles.delete(profiles.items.last);
    final after = await ProfileService(client).nameEvents();
    expect(after['p2']['deleted'], true);
    await client.dispose();
  });

  test('without encrypted data names stay in the table as before', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final server = _FakeProfiles();
    final client = await _client(server);
    final profiles = ProfileProvider(
      ProfileService(client),
      SyncService(client),
    );
    await profiles.create(
      name: 'Plain',
      avatarKey: 'star',
      avatarColor: 'verde',
    );
    expect(server.rows.single['name'], 'Plain');
    await profiles.load();
    expect(profiles.items.single.name, 'Plain');
    await client.dispose();
  });

  test('a profile without any name shows a numbered placeholder', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final server = _FakeProfiles()
      ..rows.add({
        'id': 'p1',
        'sync_code': _account,
        'name': '',
        'created_at': '2026-11-01T00:00:00Z',
      });
    final client = await _client(server);
    final profiles = ProfileProvider(
      ProfileService(client),
      SyncService(client),
    );
    await profiles.load();
    expect(profiles.items.single.name, 'Profilo 1');
    await client.dispose();
  });

  test('the names lane is reserved and never capped', () {
    final lane = {
      for (var i = 0; i < 600; i++)
        'p$i': {'id': 'p$i', 'name': 'n$i', 'watched': '2026-11-02T10:00:00Z'},
    };
    final merged = PersonalVault.merge({}, {
      'profile_histories': {PersonalVault.profilesLane: lane},
    });
    expect(
      (merged['profile_histories'][PersonalVault.profilesLane] as Map).length,
      600,
    );
    expect(PersonalVault.reservedLanes, contains(PersonalVault.profilesLane));
  });
}
