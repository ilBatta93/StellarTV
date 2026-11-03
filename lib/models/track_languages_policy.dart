/// Languages of the audio and subtitle tracks seen in a title, kept on the
/// device only. Codes are ISO 639-1 ("it"), or "und" when a track does not
/// say its language.
class TitleTracks {
  final List<String> audio;
  final List<String> subtitles;

  /// Days since epoch of the last playback that saw these tracks.
  final int seenDay;

  const TitleTracks({
    this.audio = const [],
    this.subtitles = const [],
    this.seenDay = 0,
  });

  static const empty = TitleTracks();

  bool get isEmpty => audio.isEmpty && subtitles.isEmpty;

  /// More than one audio track: dubbing or original language.
  bool get alternateAudio => audio.length > 1;

  factory TitleTracks.fromJson(Map<String, dynamic> j) => TitleTracks(
    audio: _codes(j['a']),
    subtitles: _codes(j['s']),
    seenDay: (j['d'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {'a': audio, 's': subtitles, 'd': seenDay};

  static List<String> _codes(Object? raw) => raw is List
      ? [
          for (final c in raw)
            if (c is String && c.isNotEmpty) c,
        ]
      : const [];
}

const _aliases = <String, List<String>>{
  'it': ['it', 'ita', 'italian', 'italiano'],
  'en': ['en', 'eng', 'english', 'inglese'],
  'es': ['es', 'spa', 'spanish', 'español', 'spagnolo', 'castellano'],
  'fr': ['fr', 'fra', 'fre', 'french', 'français', 'francese'],
  'de': ['de', 'deu', 'ger', 'german', 'deutsch', 'tedesco'],
  'pt': ['pt', 'por', 'portuguese', 'português', 'portoghese'],
  'ja': ['ja', 'jpn', 'japanese', 'giapponese'],
  'ko': ['ko', 'kor', 'korean', 'coreano'],
  'zh': ['zh', 'chi', 'zho', 'chinese', 'cinese'],
  'ru': ['ru', 'rus', 'russian', 'russo'],
  'ar': ['ar', 'ara', 'arabic', 'arabo'],
  'nl': ['nl', 'nld', 'dut', 'dutch', 'olandese'],
  'pl': ['pl', 'pol', 'polish', 'polacco'],
  'tr': ['tr', 'tur', 'turkish', 'turco'],
};

/// The track's own language tag first, then a language word in its label.
String trackLanguageCode(String? language, String label) {
  final tag = language?.trim().toLowerCase().split(RegExp('[-_]')).first;
  if (tag != null && tag.isNotEmpty && tag != 'und') {
    for (final e in _aliases.entries) {
      if (e.value.contains(tag)) return e.key;
    }
    if (RegExp(r'^[a-z]{2}$').hasMatch(tag)) return tag;
  }
  final words = label.toLowerCase().split(RegExp(r'[^a-zà-ÿñ]+'));
  for (final e in _aliases.entries) {
    if (words.any(e.value.contains)) return e.key;
  }
  return 'und';
}

/// Distinct codes in track order; unknown tracks still count, once each,
/// so two untagged audio tracks still read as alternate audio.
List<String> trackLanguageCodes(Iterable<(String?, String)> tracks) {
  final out = <String>[];
  for (final (language, label) in tracks) {
    final code = trackLanguageCode(language, label);
    if (code == 'und' || !out.contains(code)) out.add(code);
  }
  return out;
}

/// Every episode seen, merged: a series shows the languages of any of them.
TitleTracks mergeTitleTracks(Iterable<TitleTracks> all) {
  final audio = <String>[];
  final subs = <String>[];
  var day = 0;
  for (final t in all) {
    // Untagged tracks of different episodes collapse into one "und", so a
    // long series of single-track episodes does not look multilingual.
    for (final c in t.audio) {
      if (!audio.contains(c)) audio.add(c);
    }
    for (final c in t.subtitles) {
      if (!subs.contains(c)) subs.add(c);
    }
    if (t.seenDay > day) day = t.seenDay;
  }
  // Only untagged audio: alternate audio only if one episode had several.
  if (audio.length == 1 && audio.single == 'und') {
    final most = all.fold<int>(
      0,
      (m, t) => t.audio.length > m ? t.audio.length : m,
    );
    if (most > 1) audio.add('und');
  }
  return TitleTracks(audio: audio, subtitles: subs, seenDay: day);
}

/// "IT · EN" with unknown tracks at the end as "altra"/"altre".
String languagesLabel(List<String> codes) {
  final known = [
    for (final c in codes)
      if (c != 'und') c.toUpperCase(),
  ];
  final unknown = codes.where((c) => c == 'und').length;
  if (unknown > 0) known.add(unknown == 1 ? 'altra' : '$unknown altre');
  return known.join(' · ');
}
