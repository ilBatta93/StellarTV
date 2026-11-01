import '../models/tmdb_item.dart';
import '../models/tmdb_person.dart';
import 'tmdb_service.dart';

/// Titles linked to a person found by name (actor, director or creator).
class PersonTitles {
  final TmdbPerson person;
  final List<TmdbItem> items;
  const PersonTitles(this.person, this.items);

  /// "Diretti da …" for directors, "Con …" for everyone else.
  String get label =>
      person.isDirector ? 'Diretti da ${person.name}' : 'Con ${person.name}';
}

/// Search by actor or director: TMDB answers who the person is and what
/// they made; the caller keeps only the titles available on the device.
/// Only the typed name goes to TMDB, never the playlist.
class PersonSearch {
  PersonSearch._();
  static final instance = PersonSearch._();

  static const maxPeople = 2;

  final Map<int, Future<List<TmdbItem>>> _credits = {};
  final Map<String, Future<List<TmdbPerson>>> _people = {};

  /// People in [found] whose name matches [query], most relevant first.
  static List<TmdbPerson> matching(List<TmdbPerson> found, String query) => [
    for (final person in found)
      if (personNameMatches(person.name, query)) person,
  ].take(maxPeople).toList();

  /// People named by [query] and their titles. [people] (from a multi
  /// search) skips the name lookup when one of them matches.
  Future<List<PersonTitles>> titlesFor(
    TmdbService tmdb,
    String query, {
    List<TmdbPerson>? people,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.length < 3) return const [];
    var found = matching(people ?? const [], q);
    if (found.isEmpty) found = matching(await _lookup(tmdb, q), q);
    final credits = await Future.wait([
      for (final person in found) _creditsOf(tmdb, person.id),
    ]);
    return [
      for (final (i, person) in found.indexed)
        if (credits[i].isNotEmpty) PersonTitles(person, credits[i]),
    ];
  }

  Future<List<TmdbPerson>> _lookup(TmdbService tmdb, String q) {
    if (_people.length >= 40 && !_people.containsKey(q)) {
      _people.remove(_people.keys.first);
    }
    return _people.putIfAbsent(q, () async {
      try {
        return await tmdb.searchPeople(q);
      } catch (_) {
        _people.remove(q);
        return const [];
      }
    });
  }

  Future<List<TmdbItem>> _creditsOf(TmdbService tmdb, int id) {
    if (_credits.length >= 40 && !_credits.containsKey(id)) {
      _credits.remove(_credits.keys.first);
    }
    return _credits.putIfAbsent(id, () async {
      try {
        return await tmdb.personCredits(id);
      } catch (_) {
        _credits.remove(id);
        return const [];
      }
    });
  }
}
