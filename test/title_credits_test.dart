import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/title_credits.dart';
import 'package:stellar_tv/models/tmdb_person.dart';
import 'package:stellar_tv/services/person_search.dart';
import 'package:stellar_tv/services/tmdb_service.dart';

void main() {
  test('credits keep directors once, labelled, and the cast in order', () {
    final credits = TitleCredits.parse({
      'cast': [
        {'id': 1, 'name': 'Jacob Elordi', 'character': 'Hig'},
        {'id': 2, 'name': ''},
      ],
      'crew': [
        {'id': 9, 'name': 'Ridley Scott', 'job': 'Director'},
        {'id': 9, 'name': 'Ridley Scott', 'job': 'Director'},
        {'id': 8, 'name': 'Someone', 'job': 'Producer'},
      ],
    });
    expect(credits.directors.map((p) => p.name), ['Ridley Scott']);
    expect(credits.directors.single.character, 'Regia');
    expect(credits.cast.map((p) => p.name), ['Jacob Elordi']);
    expect(TitleCredits.parse({}).directors, isEmpty);
  });

  test('details: runtime, episode length, original title, creators', () {
    final movie = TitleInfo.parse({
      'title': 'Il padrino',
      'original_title': 'The Godfather',
      'runtime': 175,
      'tagline': ' ',
    });
    expect(movie.runtime, 175);
    expect(movie.originalTitle, 'The Godfather');
    expect(movie.tagline, isNull);

    final series = TitleInfo.parse({
      'name': 'Dark',
      'original_name': 'Dark',
      'episode_run_time': [52],
      'created_by': [
        {'id': 3, 'name': 'Baran bo Odar'},
      ],
    });
    expect(series.runtime, 52);
    expect(series.originalTitle, isNull);
    expect(series.creators.single.character, 'Ideazione');
    expect(TitleInfo.parse({'runtime': 0}).runtime, isNull);
  });

  test('runtime and names read naturally in Italian', () {
    expect(formatRuntime(52), '52 min');
    expect(formatRuntime(120), '2 h');
    expect(formatRuntime(107), '1 h 47 min');
    TmdbPerson p(String name) => TmdbPerson(id: name.length, name: name);
    expect(joinNames([p('A')]), 'A');
    expect(joinNames([p('A'), p('BB')]), 'A e BB');
    expect(joinNames([p('A'), p('BB'), p('CCC')]), 'A, BB e CCC');
  });

  test('a query names a person by word prefixes, accents ignored', () {
    expect(personNameMatches('Christopher Nolan', 'nolan'), isTrue);
    expect(personNameMatches('Christopher Nolan', 'chris nol'), isTrue);
    expect(personNameMatches('Pedro Almodóvar', 'almodovar'), isTrue);
    expect(personNameMatches('Christopher Nolan', 'olan'), isFalse);
    expect(personNameMatches('Christopher Nolan', 'no'), isFalse);
    expect(personNameMatches('Christopher Nolan', 'nolan batman'), isFalse);
  });

  test('person search keeps only matching people, at most two', () {
    final found = PersonSearch.matching(const [
      TmdbPerson(id: 1, name: 'Tom Hanks'),
      TmdbPerson(id: 2, name: 'Tom Holland'),
      TmdbPerson(id: 3, name: 'Tom Hardy'),
      TmdbPerson(id: 4, name: 'Anna Tom'),
    ], 'tom h');
    expect(found.map((p) => p.id), [1, 2]);
  });

  test('person credits include directed and created titles', () {
    final items = TmdbService.parsePersonCredits({
      'cast': [
        {'id': 1, 'media_type': 'movie', 'title': 'Cameo', 'popularity': 1},
      ],
      'crew': [
        {
          'id': 2,
          'media_type': 'movie',
          'title': 'Diretto',
          'job': 'Director',
          'popularity': 9,
        },
        {
          'id': 3,
          'media_type': 'tv',
          'name': 'Ideata',
          'job': 'Creator',
          'popularity': 5,
        },
        {
          'id': 4,
          'media_type': 'movie',
          'title': 'Prodotto',
          'job': 'Producer',
          'popularity': 50,
        },
        {
          'id': 1,
          'media_type': 'movie',
          'title': 'Cameo',
          'job': 'Director',
          'popularity': 1,
        },
      ],
    });
    expect(items.map((i) => i.title), ['Diretto', 'Ideata', 'Cameo']);
  });

  test('person titles label directors apart from actors', () {
    const director = TmdbPerson(
      id: 1,
      name: 'Greta Gerwig',
      department: 'Directing',
    );
    const actor = TmdbPerson(id: 2, name: 'Tom Hanks', department: 'Acting');
    expect(const PersonTitles(director, []).label, 'Diretti da Greta Gerwig');
    expect(const PersonTitles(actor, []).label, 'Con Tom Hanks');
    expect(director.roleLabel, 'Regia');
  });
}
