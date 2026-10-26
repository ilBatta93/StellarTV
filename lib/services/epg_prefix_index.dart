import 'dart:convert';
import 'dart:io';

/// Sorted word index shared by guide titles and channel names.
/// A query is a binary search plus a posting intersection, never a scan of
/// the programmes.
class EpgPrefixIndex {
  final List<String> words;
  final List<int> starts;
  final List<int> postings;

  const EpgPrefixIndex({
    required this.words,
    required this.starts,
    required this.postings,
  });

  static const empty = EpgPrefixIndex(words: [], starts: [0], postings: []);

  static final _split = RegExp(r'[^a-z0-9à-ÿ]+');

  factory EpgPrefixIndex.build(List<List<String>> texts) {
    final buckets = <String, Set<int>>{};
    for (var ordinal = 0; ordinal < texts.length; ordinal++) {
      final seen = <String>{};
      for (final raw in texts[ordinal]) {
        for (final part in raw.split('\u0001')) {
          for (final word in part.toLowerCase().split(_split)) {
            if (word.length < 2 || !seen.add(word)) continue;
            (buckets[word] ??= <int>{}).add(ordinal);
          }
        }
      }
    }
    final keys = buckets.keys.toList()..sort();
    final starts = <int>[0];
    final postings = <int>[];
    for (final key in keys) {
      final hits = buckets[key]!.toList()..sort();
      postings.addAll(hits);
      starts.add(postings.length);
    }
    return EpgPrefixIndex(words: keys, starts: starts, postings: postings);
  }

  factory EpgPrefixIndex.fromJson(Map<dynamic, dynamic> json) {
    final words = <String>[
      for (final word in json['w'] is List ? json['w'] as List : const [])
        word.toString(),
    ];
    final starts = _ints(json['s']);
    final postings = _ints(json['p']);
    if (starts.length != words.length + 1) return empty;
    return EpgPrefixIndex(words: words, starts: starts, postings: postings);
  }

  Map<String, dynamic> toJson() => {'w': words, 's': starts, 'p': postings};

  /// Channel ordinals whose indexed words match every token of [query].
  Set<int> ordinals(String query) {
    final tokens = <String>[
      for (final token in query.toLowerCase().split(_split))
        if (token.length >= 2) token,
    ];
    if (tokens.isEmpty || words.isEmpty) return const {};
    Set<int>? matched;
    for (final token in tokens) {
      final hits = _hits(token);
      if (hits.isEmpty) return const {};
      matched = matched == null ? hits : matched.intersection(hits);
      if (matched.isEmpty) return const {};
    }
    return matched ?? const {};
  }

  Set<int> _hits(String token) {
    var index = _lowerBound(words, token);
    final hits = <int>{};
    while (index < words.length && words[index].startsWith(token)) {
      final from = starts[index];
      final to = index + 1 < starts.length ? starts[index + 1] : postings.length;
      for (var i = from; i < to && i < postings.length; i++) {
        hits.add(postings[i]);
      }
      index++;
    }
    return hits;
  }
}

EpgPrefixIndex readEpgPrefixFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return EpgPrefixIndex.empty;
  try {
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map) return EpgPrefixIndex.empty;
    return EpgPrefixIndex.fromJson(json);
  } catch (_) {
    return EpgPrefixIndex.empty;
  }
}

List<int> _ints(Object? raw) => raw is List
    ? [for (final value in raw) if (value is num) value.toInt()]
    : const [0];

int _lowerBound(List<String> keys, String token) {
  var low = 0;
  var high = keys.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (keys[mid].compareTo(token) < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}
