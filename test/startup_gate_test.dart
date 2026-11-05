import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/startup_gate.dart';
import 'package:stellar_tv/services/title_metadata_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    StartupGate.reset();
    StartupGate.openInTests = false;
  });

  tearDown(() {
    StartupGate.fallback = const Duration(seconds: 8);
    StartupGate.openInTests = true;
    StartupGate.reset();
  });

  test('held loads wait for the intro, then start', () async {
    var started = false;
    final waiting = StartupGate.wait().then((_) => started = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(started, isFalse);
    StartupGate.open();
    await waiting;
    expect(started, isTrue);
    expect(StartupGate.isOpen, isTrue);
  });

  test('held loads start anyway when the intro never ends', () async {
    StartupGate.fallback = const Duration(milliseconds: 100);
    var started = false;
    final waiting = StartupGate.wait().then((_) => started = true);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(started, isFalse);
    await waiting;
    expect(started, isTrue);
  });

  test('saved title metadata is read only once the gate opens', () async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final dir = await Directory.systemTemp.createTemp('startup-gate');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
    final wasDisabled = TitleMetadataStore.disabled;
    TitleMetadataStore.disabled = false;
    addTearDown(() async {
      TitleMetadataStore.disabled = wasDisabled;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await dir.delete(recursive: true);
    });
    File('${dir.path}/gate_v1.json').writeAsStringSync(
      jsonEncode({
        'movie:noto': ['x', DateTime.now().millisecondsSinceEpoch],
      }),
    );
    final store = TitleMetadataStore<String>(
      fileName: 'gate_v1.json',
      encode: (v) => v,
      decode: (v) => v as String?,
    );
    addTearDown(store.dispose);
    var loaded = false;
    final loading = store.load().then((_) => loaded = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(loaded, isFalse);
    expect(store.valueOf('movie:noto'), isNull);
    StartupGate.open();
    await loading;
    expect(store.valueOf('movie:noto'), 'x');
  });
}
