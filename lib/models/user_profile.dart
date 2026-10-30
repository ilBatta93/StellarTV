class UserProfile {
  final String id;
  final String name;
  final String avatarKey;
  final String avatarColor;
  final bool isKids;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.name,
    required this.avatarKey,
    required this.avatarColor,
    required this.isKids,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'].toString(),
    name: (json['name'] ?? 'Profilo').toString(),
    avatarKey: (json['avatar_key'] ?? 'rocket').toString(),
    avatarColor: (json['avatar_color'] ?? 'arancio').toString(),
    isKids: json['is_kids'] == true,
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatar_key': avatarKey,
    'avatar_color': avatarColor,
    'is_kids': isKids,
    'created_at': createdAt.toIso8601String(),
  };

  UserProfile copyWith({
    String? name,
    String? avatarKey,
    String? avatarColor,
    bool? isKids,
  }) => UserProfile(
    id: id,
    name: name ?? this.name,
    avatarKey: avatarKey ?? this.avatarKey,
    avatarColor: avatarColor ?? this.avatarColor,
    isKids: isKids ?? this.isKids,
    createdAt: createdAt,
  );
}
