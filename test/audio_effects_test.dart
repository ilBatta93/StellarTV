import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/audio_effects.dart';
import 'package:stellar_tv/player/mediakit_engine.dart';
import 'package:stellar_tv/services/audio_effects_service.dart';
import 'package:stellar_tv/widgets/player/player_sheets.dart';

void main() {
  final noon = DateTime(2026, 11, 1, 12);
  final midnight = DateTime(2026, 11, 1, 23, 30);

  group('AudioEffectsSettings', () {
    test('round-trips through JSON', () {
      const s = AudioEffectsSettings(
        preset: EqPreset.custom,
        customGains: [3, -2, 0, 4, 12],
        dialog: DialogBoost.strong,
        night: NightMode.auto,
      );
      expect(AudioEffectsSettings.fromJson(s.toJson()), s);
    });

    test('reads missing or broken data as defaults', () {
      expect(AudioEffectsSettings.fromJson({}), const AudioEffectsSettings());
      final broken = AudioEffectsSettings.fromJson({
        'preset': 'unknown',
        'customGains': [1, 2],
        'dialog': 3,
        'night': null,
      });
      expect(broken, const AudioEffectsSettings());
      final clamped = AudioEffectsSettings.fromJson({
        'customGains': [40, -40, 1.6, 'x', 0],
      });
      expect(clamped.customGains, [12, -12, 2, 0, 0]);
    });

    test('a moved band starts a custom curve from the current preset', () {
      const cinema = AudioEffectsSettings(preset: EqPreset.cinema);
      final next = cinema.withBand(1, 99);
      expect(next.preset, EqPreset.custom);
      expect(next.eqGains, [4, 12, 0, 2, 3]);
    });

    test('automatic night mode follows 22–7', () {
      const s = AudioEffectsSettings(night: NightMode.auto);
      expect(s.nightActiveAt(DateTime(2026, 1, 1, 21, 59)), isFalse);
      expect(s.nightActiveAt(DateTime(2026, 1, 1, 22)), isTrue);
      expect(s.nightActiveAt(DateTime(2026, 1, 1, 6, 59)), isTrue);
      expect(s.nightActiveAt(DateTime(2026, 1, 1, 7)), isFalse);
    });
  });

  group('AudioEffectsPlan', () {
    test('defaults change nothing', () {
      final plan = AudioEffectsPlan.from(const AudioEffectsSettings(), noon);
      expect(plan.active, isFalse);
      expect(plan, AudioEffectsPlan.off);
      expect(plan.centerMixLevel, isNull);
      expect(plan.loudnessGainMb, 0);
    });

    test('dialogue boost lifts 1–4 kHz and cuts the rumble', () {
      final plan = AudioEffectsPlan.from(
        const AudioEffectsSettings(dialog: DialogBoost.strong),
        noon,
      );
      final speech = plan.preEqGains[5]; // 1.4–2.8 kHz
      expect(speech, greaterThan(0));
      expect(plan.preEqGains.first, lessThan(0));
      expect(plan.eqGains[3], greaterThan(0)); // 3.6 kHz
      expect(plan.centerMixLevel, greaterThan(1));
      expect(plan.compress, isFalse);
    });

    test('night mode compresses and implies a light dialogue boost', () {
      const s = AudioEffectsSettings(night: NightMode.auto);
      expect(AudioEffectsPlan.from(s, noon).active, isFalse);
      final night = AudioEffectsPlan.from(s, midnight);
      expect(night.compress, isTrue);
      expect(night.dialog, DialogBoost.light);
      expect(night.loudnessGainMb, greaterThan(0));
    });

    test('the viewer curve is interpolated on a log scale', () {
      final gains = <double>[0, 6, 0, 0, 0];
      expect(AudioEffectsPlan.userGainAt(gains, 230), 6);
      expect(AudioEffectsPlan.userGainAt(gains, 20), 0);
      expect(AudioEffectsPlan.userGainAt(gains, 20000), 0);
      final between = AudioEffectsPlan.userGainAt(gains, 117.5);
      expect(between, closeTo(3, 0.1));
    });

    test('gains stay within ±15 dB', () {
      final plan = AudioEffectsPlan.from(
        const AudioEffectsSettings(
          preset: EqPreset.custom,
          customGains: [-12, -12, 12, 12, 12],
          dialog: DialogBoost.strong,
        ),
        noon,
      );
      for (final g in [...plan.preEqGains, ...plan.eqGains]) {
        expect(g, inInclusiveRange(-15, 15));
      }
    });

    test('channel payload matches the native band layout', () {
      final payload = AudioEffectsPlan.from(
        const AudioEffectsSettings(preset: EqPreset.bass),
        noon,
      ).toChannel();
      expect(payload['active'], isTrue);
      expect(
        (payload['preEqGains'] as List).length,
        AudioEffectsPlan.preEqCutoffs.length,
      );
      expect((payload['eqGains'] as List).length, kEqBandCenters.length);
    });
  });

  group('mpv side', () {
    test('equalizer filter lists only the moved bands', () {
      expect(MediaKitEngine.equalizerFilter([0, 0, 0, 0, 0]), '');
      expect(
        MediaKitEngine.equalizerFilter([3, 0, 0, -2.5, 0]),
        'lavfi=[equalizer=f=60:t=o:w=1.5:g=3.0,'
        'equalizer=f=3600:t=o:w=1.5:g=-2.5]',
      );
    });

    test('downmix centre level resets when the boost is off', () {
      expect(MediaKitEngine.swresampleOptions(null), '');
      expect(MediaKitEngine.swresampleOptions(1.41), 'center_mix_level=1.41');
    });

    test('phones move to AudioTrack only when effects are on', () {
      expect(
        MediaKitEngine.audioOutput(
          passthrough: false,
          tv: false,
          android: true,
        ),
        isNull,
      );
      expect(
        MediaKitEngine.audioOutput(
          passthrough: false,
          tv: false,
          android: true,
          effects: true,
        ),
        'audiotrack,opensles',
      );
      expect(
        MediaKitEngine.audioOutput(
          passthrough: false,
          tv: false,
          android: false,
          effects: true,
        ),
        isNull,
      );
    });
  });

  group('AudioEffectsService', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('saves the choice and notifies the player', () async {
      SharedPreferences.setMockInitialValues({});
      final service = AudioEffectsService.instance;
      service.now = () => midnight;
      var notified = 0;
      void listener() => notified++;
      service.addListener(listener);
      addTearDown(() => service.removeListener(listener));

      const next = AudioEffectsSettings(
        dialog: DialogBoost.light,
        night: NightMode.auto,
      );
      await service.update(next);
      expect(service.settings, next);
      expect(service.plan.compress, isTrue);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('player_audio_effects_v1'), contains('auto'));
      // Off Android there is no session: mpv filters the sound itself.
      expect(service.sessionId, isNull);
      await service.update(const AudioEffectsSettings());
    });
  });

  test('menu summary', () {
    expect(audioEffectsSummary(const AudioEffectsSettings()), 'Spenti');
    expect(
      audioEffectsSummary(
        const AudioEffectsSettings(
          preset: EqPreset.cinema,
          dialog: DialogBoost.strong,
          night: NightMode.auto,
        ),
      ),
      'Notte auto · Dialoghi forte · Cinema',
    );
  });
}
