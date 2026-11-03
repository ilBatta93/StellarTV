import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/catalog_order_store.dart';
import 'package:stellar_tv/services/title_metadata_store.dart';

// Records where the value was decoded: the store must decode off this isolate.
String? _decodedOn(Object? raw) => Isolate.current.debugName;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory dir;
  late bool wasDisabled;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('background-store-read');
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

  test('saved title metadata is decoded off the UI isolate', () async {
    File('${dir.path}/background_read_v1.json').writeAsStringSync(
      jsonEncode({
        'movie:noto': ['x', DateTime.now().millisecondsSinceEpoch],
      }),
    );
    final store = TitleMetadataStore<String>(
      fileName: 'background_read_v1.json',
      encode: (v) => v,
      decode: _decodedOn,
    );
    addTearDown(store.dispose);
    await store.load();
    expect(store.valueOf('movie:noto'), isNotNull);
    expect(store.valueOf('movie:noto'), isNot(Isolate.current.debugName));
  });

  test('saved catalog orders are read back from the device', () async {
    File('${dir.path}/catalog_rating_order_v1.json').writeAsStringSync(
      jsonEncode({
        'movie|tutti': ['1', '2'],
      }),
    );
    final store = CatalogOrderStore.instance;
    await store.load();
    expect(store.loaded, isTrue);
    expect(store.idsFor('movie|tutti'), ['1', '2']);
  });
}
