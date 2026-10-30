import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/player_settings.dart';
import 'package:stellar_tv/player/mediakit_engine.dart';
import 'package:stellar_tv/widgets/phone_tap.dart';

void main() {
  testWidgets('a phone tap reaches a control without a remote', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhoneTap(onTap: () => taps++, child: const Text('Aspetto')),
        ),
      ),
    );
    await tester.tap(find.text('Aspetto'));
    expect(taps, 1);
  });

  test('television hardware strings stay on the television path', () {
    expect(
      MediaKitEngine.hardwareDecoder(
        mode: HardwareDecoding.auto,
        tv: true,
        vod: true,
        ios: false,
        android: true,
      ),
      'mediacodec,mediacodec-copy',
    );
    expect(
      MediaKitEngine.hardwareDecoder(
        mode: HardwareDecoding.auto,
        tv: true,
        vod: false,
        ios: false,
        android: true,
      ),
      'mediacodec-copy',
    );
    expect(
      MediaKitEngine.hardwareDecoder(
        mode: HardwareDecoding.auto,
        tv: true,
        vod: true,
        ios: true,
        android: false,
      ),
      'videotoolbox-copy',
    );
  });

  test('tv films follow the display and live stays on the audio clock', () {
    expect(
      MediaKitEngine.videoSync(tv: true, live: false, preview: false),
      'display-resample',
    );
    expect(
      MediaKitEngine.videoSync(tv: true, live: true, preview: false),
      'audio',
    );
    expect(
      MediaKitEngine.videoSync(tv: true, live: false, preview: true),
      'audio',
    );
    expect(
      MediaKitEngine.videoSync(tv: false, live: false, preview: false),
      'audio',
    );
  });

  test('phones use their own decoder and can fall back to a copy', () {
    expect(
      MediaKitEngine.hardwareDecoder(
        mode: HardwareDecoding.auto,
        tv: false,
        vod: true,
        ios: true,
        android: false,
      ),
      'videotoolbox',
    );
    expect(
      MediaKitEngine.hardwareDecoder(
        mode: HardwareDecoding.auto,
        tv: false,
        vod: true,
        ios: true,
        android: false,
        copy: true,
      ),
      'videotoolbox-copy',
    );
    expect(
      MediaKitEngine.hardwareDecoder(
        mode: HardwareDecoding.auto,
        tv: false,
        vod: false,
        ios: true,
        android: false,
      ),
      'videotoolbox-copy',
    );
    expect(
      MediaKitEngine.hardwareDecoder(
        mode: HardwareDecoding.auto,
        tv: false,
        vod: true,
        ios: false,
        android: true,
      ),
      'mediacodec-copy',
    );
    expect(
      MediaKitEngine.hardwareDecoder(
        mode: HardwareDecoding.auto,
        tv: false,
        vod: false,
        ios: false,
        android: true,
      ),
      'mediacodec-copy',
    );
    expect(
      MediaKitEngine.hardwareDecoder(
        mode: HardwareDecoding.disabled,
        tv: false,
        vod: true,
        ios: true,
        android: false,
      ),
      'no',
    );
  });
}
