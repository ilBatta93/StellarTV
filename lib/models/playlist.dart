class Playlist {
  final String id;
  final String name;
  final String url;
  final DateTime addedAt;
  final int channelCount;

  Playlist({
    required this.id,
    required this.name,
    required this.url,
    required this.addedAt,
    this.channelCount = 0,
  });

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Untitled Playlist',
      url: map['url'] as String? ?? '',
      addedAt: map['added_at'] != null
          ? DateTime.parse(map['added_at'] as String)
          : DateTime.now(),
      channelCount: map['channel_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'added_at': addedAt.toIso8601String(),
      'channel_count': channelCount,
    };
  }
}
