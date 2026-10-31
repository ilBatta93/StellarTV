import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/epg_program.dart';
import 'package:stellar_tv/widgets/player/tv_live_banner.dart';

EpgProgram _program(String title, DateTime start, DateTime end) => EpgProgram(
  id: title,
  channelId: 'c',
  title: title,
  description: '',
  startTime: start,
  endTime: end,
);

void main() {
  test('remote digits map top row and keypad', () {
    expect(remoteDigit(LogicalKeyboardKey.digit7), 7);
    expect(remoteDigit(LogicalKeyboardKey.numpad0), 0);
    expect(remoteDigit(LogicalKeyboardKey.arrowUp), isNull);
  });

  test('quality label follows the decoded picture', () {
    expect(liveQualityLabel(Size.zero), isNull);
    expect(liveQualityLabel(const Size(3840, 2160)), '4K');
    expect(liveQualityLabel(const Size(1920, 1080)), '1080p');
    expect(liveQualityLabel(const Size(720, 576)), 'SD');
  });

  test('programme progress is clamped', () {
    final start = DateTime(2026, 10, 31, 15);
    final p = _program('P', start, start.add(const Duration(hours: 1)));
    expect(TvLiveBanner.progressOf(p, start), 0);
    expect(
      TvLiveBanner.progressOf(p, start.add(const Duration(minutes: 30))),
      0.5,
    );
    expect(TvLiveBanner.progressOf(p, start.add(const Duration(hours: 2))), 1);
  });

  testWidgets('banner shows now, next and the channel number', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvLiveBanner(
            channelName: 'Canale Prova',
            number: 12,
            now: _program(
              'In onda',
              now.subtract(const Duration(minutes: 10)),
              now.add(const Duration(minutes: 20)),
            ),
            next: _program(
              'Dopo',
              now.add(const Duration(minutes: 20)),
              now.add(const Duration(minutes: 50)),
            ),
            qualityLabel: '1080p',
          ),
        ),
      ),
    );
    expect(find.text('Canale Prova'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.textContaining('In onda'), findsOneWidget);
    expect(find.textContaining('Dopo ·'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
  });
}
