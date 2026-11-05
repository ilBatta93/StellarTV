import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/services/device_json_file.dart';
import 'package:stellar_tv/services/platform_catalog_service.dart';
import 'package:stellar_tv/services/title_metadata_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory dir;
  late bool wasDisabled;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('device-json-file');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
    wasDisabled = TitleMetadataStore.disabled;
    TitleMetadataStore.disabled = false;
  });

  tearDown(() async {
    TitleMetadataStore.disabled = wasDisabled;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });

  // Large caches in the preferences were decoded on the UI thread at every
  // launch: the saved copy moves to a file and the key goes away.
  test('a value saved in the preferences moves to its file', () async {
    SharedPreferences.setMockInitialValues({
      'discover_cache_v1': jsonEncode({
        'movies': [
          {'id': 1},
        ],
      }),
      'other': 'kept',
    });
    const cache = DeviceJsonFile(
      'discover_cache_v1',
      legacyKey: 'discover_cache_v1',
    );
    final moved = await cache.read();
    expect((moved as Map)['movies'], [
      {'id': 1},
    ]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('discover_cache_v1'), isFalse);
    expect(prefs.getString('other'), 'kept');
    expect(
      File('${dir.path}/json_cache/discover_cache_v1.json').existsSync(),
      isTrue,
    );
    expect(await cache.read(), moved);
  });

  test('a written value reads back without touching the preferences', () async {
    SharedPreferences.setMockInitialValues({});
    const cache = DeviceJsonFile('sample', legacyKey: 'sample');
    expect(await cache.read(), isNull);
    await cache.write({'at': 'x', 'items': const []});
    expect(await cache.read(), {'at': 'x', 'items': const []});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('a platform catalog file name keeps only safe characters', () {
    final file = PlatformCatalogService.fileOf('Apple TV+:movie');
    expect(file.name, 'platform_catalog_v1_Apple_TV_movie');
    expect(file.legacyKey, 'platform_catalog_v1:Apple TV+:movie');
  });
}
