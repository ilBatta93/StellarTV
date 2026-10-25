import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/image_cache_service.dart';

void main() {
  test('image cache trim drops the oldest files and keeps the index', () async {
    final dir = await Directory.systemTemp.createTemp('stv_cache');
    try {
      final old = File('${dir.path}${Platform.pathSeparator}old')
        ..writeAsStringSync('12345');
      old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
      File('${dir.path}${Platform.pathSeparator}young').writeAsStringSync('abc');
      File('${dir.path}${Platform.pathSeparator}cache.db').writeAsStringSync('database');
      final removed = trimCacheDirectory(dir.path, 4);
      expect(removed, 5);
      expect(old.existsSync(), isFalse);
      expect(
        File('${dir.path}${Platform.pathSeparator}young').existsSync(),
        isTrue,
      );
      expect(
        File('${dir.path}${Platform.pathSeparator}cache.db').existsSync(),
        isTrue,
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
