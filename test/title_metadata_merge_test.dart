import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/title_metadata_store.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('merge_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a delta replaces its keys and keeps the others', () {
    final path = '${dir.path}/rows.json';
    File(path).writeAsStringSync(
      jsonEncode({
        'a': {'i': 7.1},
        'b': {'i': 8.0},
      }),
    );
    final ok = mergeJsonMapFile(path, {
      'b': {'i': 9.3},
      'c': {'t': 6.5},
    });
    expect(ok, isTrue);
    expect(jsonDecode(File(path).readAsStringSync()), {
      'a': {'i': 7.1},
      'b': {'i': 9.3},
      'c': {'t': 6.5},
    });
  });

  test('a missing file is created from the delta', () {
    final path = '${dir.path}/new.json';
    expect(mergeJsonMapFile(path, {'a': 1}), isTrue);
    expect(jsonDecode(File(path).readAsStringSync()), {'a': 1});
  });

  test('an unreadable file is reported so every row is written again', () {
    final path = '${dir.path}/broken.json';
    File(path).writeAsStringSync('{"a": ');
    expect(mergeJsonMapFile(path, {'b': 2}), isFalse);
    expect(jsonDecode(File(path).readAsStringSync()), {'b': 2});
  });
}
