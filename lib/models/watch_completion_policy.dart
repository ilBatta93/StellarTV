/// Portable preference; never stored as a completion flag in history rows.
class WatchCompletionPolicy {
  static const key = 'ui_watched_percent';
  static const defaultPercent = 94;
  static final List<int> options = List.unmodifiable(
    List.generate(51, (i) => 50 + i),
  );
  static int normalize(Object? value) =>
      value is int && value >= 50 && value <= 100 ? value : defaultPercent;
}
