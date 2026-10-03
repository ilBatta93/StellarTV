import 'package:flutter/material.dart';

class StreamingPlatform {
  final String name;
  final String providerIds;
  final String region;
  final Color color;

  const StreamingPlatform({
    required this.name,
    required this.providerIds,
    required this.region,
    required this.color,
  });

  static const all = [
    StreamingPlatform(
        name: 'Netflix', providerIds: '8', region: 'IT', color: Color(0xFFE50914)),
    StreamingPlatform(
        name: 'Prime Video',
        providerIds: '119',
        region: 'IT',
        color: Color(0xFF00A8E1)),
    StreamingPlatform(
        name: 'Apple TV+',
        providerIds: '350',
        region: 'IT',
        color: Color(0xFFE5E5EA)),
    StreamingPlatform(
        name: 'HBO Max',
        providerIds: '1899|384',
        region: 'IT',
        color: Color(0xFF5B8CFF)),
    StreamingPlatform(
        name: 'Paramount+',
        providerIds: '531',
        region: 'IT',
        color: Color(0xFF0064FF)),
  ];
}
