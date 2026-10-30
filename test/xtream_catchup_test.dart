import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/epg_program.dart';
import 'package:stellar_tv/services/xtream_catchup.dart';

void main() {
  final now = DateTime.utc(2026, 10, 18, 12);
  final channel = Channel(
    id: 'live_42',
    name: 'TV',
    url: 'https://example.test/live/u/p/42.m3u8',
    logo: '',
    group: '',
    type: ContentType.live,
    archiveDays: 2,
  );
  EpgProgram programme(DateTime start, DateTime end) => EpgProgram(
    id: 'p',
    channelId: 'c',
    title: '',
    description: '',
    startTime: start,
    endTime: end,
  );
  test('Archive disabled never generates playback', () {
    expect(
      XtreamCatchup.available(
        channel.copyWith(archiveDays: 0),
        programme(now.subtract(const Duration(hours: 1)), now),
        now,
      ),
      isFalse,
    );
  });
  test('Future and expired programmes are rejected', () {
    expect(
      XtreamCatchup.available(
        channel,
        programme(
          now.add(const Duration(hours: 1)),
          now.add(const Duration(hours: 2)),
        ),
        now,
      ),
      isFalse,
    );
    expect(
      XtreamCatchup.available(
        channel,
        programme(now.subtract(const Duration(days: 3)), now),
        now,
      ),
      isFalse,
    );
  });
  test('Provider timezone and minute rounding are applied', () {
    expect(
      XtreamCatchup.url(
        channel,
        programme(
          DateTime.utc(2026, 10, 18, 11),
          DateTime.utc(2026, 10, 18, 11, 30, 1),
        ),
        now: now,
        timezone: 'Europe/Rome',
      ),
      'https://example.test/timeshift/u/p/31/2026-10-18:13-00/42.ts',
    );
  });
  test('Archive metadata survives cached serialization and copy', () {
    expect(
      Channel.fromJson(channel.toJson()).copyWith(name: 'Changed').archiveDays,
      2,
    );
  });
  test('Unknown provider timezone fails closed', () {
    expect(
      XtreamCatchup.url(
        channel,
        programme(now.subtract(const Duration(hours: 1)), now),
        now: now,
        timezone: 'Unknown/Zone',
      ),
      isNull,
    );
  });
}
