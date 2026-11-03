import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/player_settings.dart';
import 'package:stellar_tv/models/video_resolution_policy.dart';
import 'package:stellar_tv/services/playback_assistance.dart';
import 'package:stellar_tv/services/introdb_service.dart';

void main() {
  const tv4k = DisplayResolution(
    width: 3840,
    height: 2160,
    currentWidth: 1920,
    currentHeight: 1080,
  );
  const phone = DisplayResolution(width: 1080, height: 2400);

  group('videoSizeCap', () {
    test('no limit and unknown screen mean no cap', () {
      expect(videoSizeCap(MaxVideoResolution.unlimited, tv4k), isNull);
      expect(videoSizeCap(MaxVideoResolution.native, null), isNull);
    });

    test('native follows the panel, not the 1080p interface', () {
      expect(
        videoSizeCap(MaxVideoResolution.native, tv4k),
        const VideoSizeCap(3840, 2160),
      );
      expect(tv4k.outputDiffers, isTrue);
    });

    test('a portrait phone compares long and short sides', () {
      final cap = videoSizeCap(MaxVideoResolution.native, phone)!;
      expect(cap, const VideoSizeCap(2400, 1080));
      expect(cap.fits(1920, 1080), isTrue);
      expect(cap.fits(3840, 2160), isFalse);
    });

    test('fixed sizes are 16:9 boxes with a coded-size slack', () {
      final cap = videoSizeCap(MaxVideoResolution.p1080, null)!;
      expect(cap, const VideoSizeCap(1920, 1080));
      expect(cap.fits(1920, 1088), isTrue);
      expect(cap.fits(1440, 1080), isTrue);
      expect(cap.fits(2560, 1440), isFalse);
      expect(
        videoSizeCap(MaxVideoResolution.p720, null),
        const VideoSizeCap(1280, 720),
      );
    });
  });

  group('pickCappedVariant', () {
    const sizes = [(3840, 2160), (1280, 720), (1920, 1080), (640, 360)];

    test('largest variant inside the cap', () {
      expect(pickCappedVariant(sizes, const VideoSizeCap(1920, 1080)), 2);
      expect(pickCappedVariant(sizes, const VideoSizeCap(1280, 720)), 1);
    });

    test('smallest variant when none fits', () {
      expect(pickCappedVariant(sizes, const VideoSizeCap(320, 180)), 3);
    });

    test('unknown sizes are ignored', () {
      expect(pickCappedVariant(const [(0, 0)], const VideoSizeCap(1, 1)), null);
    });
  });

  test('initial mpv bitrate only below 4K', () {
    expect(hlsBitrateFor(null), isNull);
    expect(hlsBitrateFor(const VideoSizeCap(854, 480)), 1500000);
    expect(hlsBitrateFor(const VideoSizeCap(1920, 1080)), 6000000);
    expect(hlsBitrateFor(const VideoSizeCap(3840, 2160)), isNull);
  });

  test('describeResolution names the size', () {
    expect(describeResolution(3840, 2160), '3840 × 2160 (4K)');
    expect(describeResolution(1080, 2400), '1080 × 2400 (Full HD)');
  });

  group('settings', () {
    test('old settings read with no cap and no automatic skip', () {
      final s = PlayerSettings.fromJson(const {'engineV': 2});
      expect(s.maxResolution, MaxVideoResolution.unlimited);
      expect(s.autoSkipIntro, isFalse);
    });

    test('new fields survive a round trip', () {
      final s = PlayerSettings()
        ..maxResolution = MaxVideoResolution.p720
        ..autoSkipIntro = true;
      final back = PlayerSettings.fromJson(s.toJson());
      expect(back.maxResolution, MaxVideoResolution.p720);
      expect(back.autoSkipIntro, isTrue);
    });
  });

  group('automatic skip flag', () {
    SkipSegment seg(String type, int from, int to) =>
        SkipSegment(type, Duration(seconds: from), Duration(seconds: to));

    test('an opening is marked, a lone recap is not', () {
      final intro = EpisodeSegments(all: [seg('intro', 0, 60)]);
      expect(activeSkip(intro, const Duration(seconds: 5))!.intro, isTrue);
      final recap = EpisodeSegments(all: [seg('recap', 0, 60)]);
      expect(activeSkip(recap, const Duration(seconds: 5))!.intro, isFalse);
    });

    test('a recap glued to the opening skips both', () {
      final glued = EpisodeSegments(
        all: [seg('recap', 0, 40), seg('intro', 41, 100)],
      );
      final choice = activeSkip(glued, const Duration(seconds: 5))!;
      expect(choice.intro, isTrue);
      expect(choice.target, const Duration(seconds: 100));
    });
  });
}
