import '../models/channel.dart';
import 'catalog_index_builder.dart' show catalogEntryKey;

/// Built off the UI thread once per playlist revision, never during rendering.
Map<String, List<String>> buildTitleCategoryIndex(List<Channel> channels) {
  final groups = <String, Set<String>>{};
  for (final channel in channels) {
    if (channel.group.isEmpty) continue;
    (groups[catalogEntryKey(channel)] ??= <String>{}).add(channel.group);
  }
  return {
    for (final entry in groups.entries)
      entry.key: List<String>.unmodifiable(entry.value),
  };
}
