import 'content_type.dart';

/// A category the user created and filled by hand (Film or Serie TV).
/// Stored only on this device: it references playlist ids, which are
/// provider data and never go to the cloud.
class CustomCategory {
  final String id;
  final String name;
  final ContentType type;
  final List<String> itemIds;

  const CustomCategory({
    required this.id,
    required this.name,
    required this.type,
    this.itemIds = const [],
  });

  CustomCategory copyWith({String? name, List<String>? itemIds}) =>
      CustomCategory(
        id: id,
        name: name ?? this.name,
        type: type,
        itemIds: itemIds ?? this.itemIds,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'items': itemIds,
  };

  static CustomCategory? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], name = raw['name'], type = raw['type'];
    if (id is! String || name is! String || name.trim().isEmpty) return null;
    final kind = ContentType.values.where((t) => t.name == type).firstOrNull;
    if (kind == null) return null;
    final items = raw['items'];
    return CustomCategory(
      id: id,
      name: name.trim(),
      type: kind,
      itemIds: items is List ? items.whereType<String>().toList() : const [],
    );
  }
}

/// Final category order: labels the user placed explicitly come first in
/// their saved order (unknown labels are skipped), then every other label
/// keeps its default position. Pure and shared with tests.
List<String> applyCategoryOrder(List<String> defaults, List<String> saved) {
  final available = defaults.toSet();
  final seen = <String>{};
  return [
    for (final label in saved)
      if (available.contains(label) && seen.add(label)) label,
    for (final label in defaults)
      if (seen.add(label)) label,
  ];
}

/// Moves [label] one step within the visible [order]; returns the new list.
List<String> moveCategory(List<String> order, String label, int delta) {
  final list = [...order];
  final from = list.indexOf(label);
  final to = from + delta;
  if (from < 0 || to < 0 || to >= list.length) return list;
  list
    ..removeAt(from)
    ..insert(to, label);
  return list;
}
