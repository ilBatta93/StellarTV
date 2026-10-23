import 'package:flutter/material.dart';

class StreamingPlatform {
  final String name;
  final String providerIds;
  final String region;
  final Color color;

  /// Words providers commonly use in category or title names for the
  /// platform ("NETFLIX", "[NF]", "Disney+"): a local fallback when TMDB
  /// does not list the title. Matched case-insensitively on word bounds.
  final RegExp tags;

  const StreamingPlatform({
    required this.name,
    required this.providerIds,
    required this.region,
    required this.color,
    required this.tags,
  });

  /// True when a playlist category or title name explicitly names this
  /// platform. Never used for cloud data: the match runs on the device.
  bool tagMatches(String text) => text.isNotEmpty && tags.hasMatch(text);

  static final all = [
    StreamingPlatform(
      name: 'Netflix',
      providerIds: '8',
      region: 'IT',
      color: const Color(0xFFE50914),
      tags: RegExp(r'\bnetflix\b|[\[\(]\s*nf\s*[\]\)]', caseSensitive: false),
    ),
    StreamingPlatform(
      name: 'Prime Video',
      providerIds: '119',
      region: 'IT',
      color: const Color(0xFF00A8E1),
      tags: RegExp(
        r'\bprime\s*video\b|\bamazon\b|[\[\(]\s*amz\s*[\]\)]',
        caseSensitive: false,
      ),
    ),
    StreamingPlatform(
      name: 'Disney+',
      providerIds: '337',
      region: 'IT',
      color: const Color(0xFF113CCF),
      tags: RegExp(
        r'\bdisney\s*(\+|plus)|[\[\(]\s*dsnp\s*[\]\)]',
        caseSensitive: false,
      ),
    ),
    StreamingPlatform(
      name: 'Apple TV+',
      providerIds: '350',
      region: 'IT',
      color: const Color(0xFFE5E5EA),
      tags: RegExp(
        r'\bapple\s*tv\s*(\+|plus)|[\[\(]\s*atvp\s*[\]\)]',
        caseSensitive: false,
      ),
    ),
    StreamingPlatform(
      name: 'HBO Max',
      providerIds: '1899|384',
      region: 'IT',
      color: const Color(0xFF5B8CFF),
      tags: RegExp(r'\bhbo\b|\bmax\s+original', caseSensitive: false),
    ),
    StreamingPlatform(
      name: 'Paramount+',
      providerIds: '531',
      region: 'IT',
      color: const Color(0xFF0064FF),
      tags: RegExp(
        r'\bparamount\s*(\+|plus)|[\[\(]\s*pmtp\s*[\]\)]',
        caseSensitive: false,
      ),
    ),
    StreamingPlatform(
      name: 'Crunchyroll',
      providerIds: '283',
      region: 'IT',
      color: const Color(0xFFF47521),
      tags: RegExp(r'\bcrunchyroll\b', caseSensitive: false),
    ),
  ];

  static StreamingPlatform? byName(String? name) {
    for (final p in all) {
      if (p.name == name) return p;
    }
    return null;
  }
}
