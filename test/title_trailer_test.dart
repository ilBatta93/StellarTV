import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stellar_tv/models/title_trailer.dart';
import 'package:stellar_tv/services/tmdb_service.dart';
import 'home_banner_remote_test.dart' as fixture;
Map<String, dynamic> video(String key, String language, {String type = 'Trailer'}) =>
 {'key': key, 'iso_639_1': language, 'type': type, 'site': 'YouTube', 'official': true};
void main() {
 test('Italian trailer has priority and does not request English', () async {
  final languages = <String>[];
  await http.runWithClient(() async {
   final result = await TmdbService().trailer(fixture.item(7, 'Film'));
   expect(result?.language, 'it');
   expect(result?.url.toString(), 'https://www.youtube.com/watch?v=abcDEF12345');
   expect(languages, ['it-IT']);
  }, () => MockClient((request) async {
   languages.add(request.url.queryParameters['language'] ?? '');
   return http.Response(jsonEncode({'results': [video('abcDEF12345','it')]}), 200);
  }));
 });
 test('English trailer is fallback when Italian has no trailer', () async {
  final languages = <String>[];
  await http.runWithClient(() async {
   final result = await TmdbService().trailer(fixture.item(7, 'Film'));
   expect(result?.language, 'en');
   expect(result?.key, 'abcDEF12345');
   expect(languages, ['it-IT', 'en-US']);
  }, () => MockClient((request) async {
   final lang = request.url.queryParameters['language']; languages.add(lang ?? '');
   return http.Response(jsonEncode({'results': lang == 'en-US' ? [video('abcDEF12345','en')] : []}), 200);
  }));
 });
 test('Unavailable trailer stays absent, unsafe keys and teasers are excluded', () {
  expect(TitleTrailer.select({'results': [video('../unsafe','it'), video('abcDEF12345','en'), video('abcDEF12345','it',type: 'Teaser')]},'it'), isNull);
 });
}
