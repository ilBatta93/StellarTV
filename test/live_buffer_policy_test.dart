import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/live_buffer_policy.dart';
import 'package:stellar_tv/player/buffer_memory.dart';
import 'package:stellar_tv/player/exo_engine.dart';

const _mib = 1024 * 1024;
const _gib = 1024 * _mib;

void main() {
  group('liveRewindBytes', () {
    test('TV stick da 1-2 GB resta piccola, il telefono più ampio', () {
      final stick1 = liveRewindBytes(
        tv: true,
        totalRamBytes: _gib,
        lowRam: false,
      );
      final stick2 = liveRewindBytes(
        tv: true,
        totalRamBytes: 2 * _gib,
        lowRam: false,
      );
      final phone = liveRewindBytes(
        tv: false,
        totalRamBytes: 6 * _gib,
        lowRam: false,
      );
      expect(stick1, greaterThanOrEqualTo(32 * _mib));
      expect(stick1, lessThan(64 * _mib));
      expect(stick2, greaterThan(stick1));
      expect(stick2, lessThanOrEqualTo(192 * _mib));
      expect(phone, greaterThan(stick2));
      expect(phone, lessThanOrEqualTo(384 * _mib));
    });

    test('limiti, RAM sconosciuta e dispositivi a poca memoria', () {
      expect(
        liveRewindBytes(tv: true, totalRamBytes: 16 * _gib, lowRam: false),
        192 * _mib,
      );
      expect(
        liveRewindBytes(tv: false, totalRamBytes: 16 * _gib, lowRam: false),
        384 * _mib,
      );
      expect(
        liveRewindBytes(tv: true, totalRamBytes: null, lowRam: false),
        48 * _mib,
      );
      expect(
        liveRewindBytes(tv: false, totalRamBytes: 8 * _gib, lowRam: true),
        24 * _mib,
      );
    });
  });

  group('finestra della diretta', () {
    const window = LiveWindow(
      start: Duration(seconds: 40),
      edge: Duration(seconds: 130),
    );

    test('ritardo, riavvolgibile e limiti', () {
      const pos = Duration(seconds: 100);
      expect(window.behind(pos), const Duration(seconds: 30));
      expect(window.rewindable(pos), const Duration(seconds: 60));
      expect(window.clamp(Duration.zero), const Duration(seconds: 40));
      expect(
        window.clamp(const Duration(minutes: 10)),
        const Duration(seconds: 129),
      );
    });

    test('sceglie il tratto che contiene la posizione', () {
      final ranges = [
        const SeekRange(Duration(seconds: 500), Duration(seconds: 800)),
        const SeekRange(Duration(seconds: 10), Duration(seconds: 70)),
      ];
      final found = liveWindowAt(const Duration(seconds: 60), ranges);
      expect(found?.start, const Duration(seconds: 10));
      expect(found?.edge, const Duration(seconds: 70));
      expect(liveWindowAt(const Duration(seconds: 300), ranges), isNull);
    });

    test('legge demuxer-cache-state di mpv', () {
      final state = CacheState.parse({
        'seekable-ranges': [
          {'start': 12.5, 'end': 70.25},
          {'start': 'x', 'end': 3},
        ],
        'underrun': true,
      });
      expect(state, isNotNull);
      expect(state!.underrun, isTrue);
      expect(state.ranges, hasLength(1));
      expect(state.ranges.single.start, const Duration(milliseconds: 12500));
      expect(state.ranges.single.end, const Duration(milliseconds: 70250));
      expect(CacheState.parse('testo'), isNull);
      expect(CacheState.parse(const {})!.ranges, isEmpty);
    });

    test('un salto indietro senza seek è un azzeramento dell\'orologio', () {
      expect(
        liveClockJumped(
          previous: const Duration(seconds: 900),
          current: const Duration(seconds: 2),
          seeking: false,
        ),
        isTrue,
      );
      expect(
        liveClockJumped(
          previous: const Duration(seconds: 900),
          current: const Duration(seconds: 2),
          seeking: true,
        ),
        isFalse,
      );
      expect(
        liveClockJumped(
          previous: const Duration(seconds: 100),
          current: const Duration(seconds: 101),
          seeking: false,
        ),
        isFalse,
      );
    });
  });

  group('buffer adattivo', () {
    test('un blocco isolato non cambia, due ravvicinati salgono', () {
      final buffer = AdaptiveBuffer();
      final t0 = DateTime(2026, 11, 2, 20);
      expect(buffer.onStall(t0), isFalse);
      expect(buffer.level, 0);
      expect(buffer.onStall(t0.add(const Duration(seconds: 30))), isTrue);
      expect(buffer.level, 1);
    });

    test('blocchi lontani nel tempo non si sommano', () {
      final buffer = AdaptiveBuffer();
      final t0 = DateTime(2026, 11, 2, 20);
      buffer.onStall(t0);
      expect(buffer.onStall(t0.add(const Duration(minutes: 5))), isFalse);
      expect(buffer.level, 0);
    });

    test('non supera il massimo e scende dopo la calma', () {
      final buffer = AdaptiveBuffer(level: 9);
      expect(buffer.level, AdaptiveBuffer.maxLevel);
      final t0 = DateTime(2026, 11, 2, 20);
      expect(buffer.onStall(t0), isFalse);
      expect(buffer.onStall(t0.add(const Duration(seconds: 1))), isFalse);
      expect(buffer.onSteady(t0.add(const Duration(minutes: 5))), isFalse);
      expect(buffer.onSteady(t0.add(const Duration(minutes: 11))), isTrue);
      expect(buffer.level, AdaptiveBuffer.maxLevel - 1);
    });

    test('mpv: il livello 0 della diretta resta sul bordo live', () {
      expect(mpvCachePauseWait(level: 0, live: true), isNull);
      expect(mpvCachePauseWait(level: 1, live: true), 2.0);
      expect(mpvCachePauseWait(level: 3, live: true), 6.0);
      expect(mpvCachePauseWait(level: 0, live: false), 1.0);
      expect(mpvCacheSeconds(0), 30);
      expect(mpvCacheSeconds(7), 90);
    });

    test('ExoPlayer: il livello allarga diretta e film, non l\'anteprima', () {
      final base = ExoLoadProfile.forPlayback(
        preview: false,
        live: true,
        backBufferMs: 60000,
      );
      final deep = ExoLoadProfile.forPlayback(
        preview: false,
        live: true,
        backBufferMs: 60000,
        level: 3,
      );
      final preview = ExoLoadProfile.forPlayback(
        preview: true,
        live: true,
        backBufferMs: 0,
        level: 3,
      );
      expect(deep.minBufferMs, greaterThan(base.minBufferMs));
      expect(deep.maxBufferMs, greaterThan(base.maxBufferMs));
      expect(
        deep.bufferForPlaybackAfterRebufferMs,
        greaterThan(base.bufferForPlaybackAfterRebufferMs),
      );
      // Il nativo taglia a 120 s.
      expect(deep.maxBufferMs, lessThanOrEqualTo(120000));
      expect(preview.maxBufferMs, 4000);
    });
  });

  test('BufferMemory salva solo un\'impronta dell\'host', () {
    final a = BufferMemory.keyFor('http://Tv.Example.com:8080/live/u/p/1.ts');
    final b = BufferMemory.keyFor('http://tv.example.com/live/x/y/2.m3u8');
    expect(a, b);
    expect(a, hasLength(8));
    expect(a.contains('example'), isFalse);
    expect(BufferMemory.keyFor('non un indirizzo'), isEmpty);
  });
}
