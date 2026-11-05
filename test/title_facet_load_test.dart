import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/title_facet_index.dart';

void main() {
  // At launch the index is empty and takes the rows decoded off the UI
  // isolate as they are; links to the shared media rows must still be made.
  test('a saved index loads into an empty index with its links', () async {
    final dir = Directory.systemTemp.createTempSync('facet-load');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/title_facets_v1.json')
      ..writeAsStringSync(
        jsonEncode({
          'movie:il padrino': {'id': 238, 'mk': 'movie:238', 'tt': 'tt0068646'},
          'movie:238': {'i': 9.2, 'ia': 1700000000000, 'iv': 2000000},
        }),
      );
    final index = TitleFacetIndex.instance;
    await index.readFile(file.path);
    expect(index.imdbOfMedia('movie:238'), 9.2);
    expect(index.linkOf('movie:il padrino')?.mediaKey, 'movie:238');
    expect(index.imdbIdOf('movie:238'), 'tt0068646');
    // Rows read from the file are already saved: nothing is queued.
    expect(index.pendingRows, isEmpty);
  });
}
