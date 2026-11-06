/// "Scena sulla locandina selezionata" (TV Home rows): which picture the
/// selected cover turns into. Pure, no I/O.
typedef SceneEpisode = ({int season, int episode});

/// The episode whose still is shown, null for the title's own scene still.
///
/// A film always shows its scene. A series not started shows its first
/// episode; one in progress the episode being watched; when the last one
/// reached was finished, the next one ([focusSceneFallback] covers a new
/// season). A series with nothing left falls back to its scene still,
/// decided by the caller when no next episode exists.
SceneEpisode? focusSceneEpisode({
  required bool series,
  SceneEpisode? last,
  bool lastWatched = false,
}) {
  if (!series) return null;
  if (last == null) return (season: 1, episode: 1);
  if (!lastWatched) return last;
  return (season: last.season, episode: last.episode + 1);
}

/// Where to look when [focusSceneEpisode] pointed past the end of a season:
/// the first episode of the next one. Null when nothing else to try.
SceneEpisode? focusSceneFallback({
  SceneEpisode? last,
  bool lastWatched = false,
}) {
  if (last == null || !lastWatched) return null;
  return (season: last.season + 1, episode: 1);
}

/// "S2 E5 · Titolo dell'episodio", or just the numbers without a title.
String focusSceneEpisodeLabel(int season, int episode, String? title) {
  final numbers = 'S$season E$episode';
  final name = title?.trim() ?? '';
  return name.isEmpty ? numbers : '$numbers · $name';
}
