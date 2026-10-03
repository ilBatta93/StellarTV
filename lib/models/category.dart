import 'content_type.dart';

class Category {
  final String id;
  final String name;
  final ContentType type;
  final int channelCount;

  Category({
    required this.id,
    required this.name,
    required this.type,
    this.channelCount = 0,
  });

  String get displayName => name.isEmpty ? 'Uncategorized' : name;
}
