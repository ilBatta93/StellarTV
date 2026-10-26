import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/player/stream_health.dart';
import 'package:stellar_tv/services/stream_slot_policy.dart';

void main() {
  test('un keyframe lento non consuma il budget della prima immagine', () {
    final health = StreamHealth(
      pictureBudget: const Duration(seconds: 8),
      stallSamples: 8,
      keyframeGrace: const Duration(seconds: 6),
    );
    StreamHealthDecision? last;
    for (var i = 0; i < 6; i++) {
      last = health.tick(
        evaluatePicture: true,
        evaluateStall: true,
        viewerPaused: false,
        audioOnly: false,
        playing: true,
        buffering: true,
        ended: false,
        frameAvailable: false,
        frames: null,
        mediaAdvanced: false,
      );
    }
    expect(last, isNull);
    for (var i = 0; i < 7; i++) {
      last = health.tick(
        evaluatePicture: true,
        evaluateStall: true,
        viewerPaused: false,
        audioOnly: false,
        playing: true,
        buffering: false,
        ended: false,
        frameAvailable: false,
        frames: null,
        mediaAdvanced: false,
      );
    }
    expect(last, isNull);
    last = health.tick(
      evaluatePicture: true,
      evaluateStall: true,
      viewerPaused: false,
      audioOnly: false,
      playing: true,
      buffering: false,
      ended: false,
      frameAvailable: false,
      frames: null,
      mediaAdvanced: true,
    );
    expect(last?.kind, StreamHealthKind.picture);
    expect(last?.mediaAdvancing, isTrue);
  });

  test('dopo il primo movimento lo stallo usa lo stesso budget', () {
    final health = StreamHealth(
      pictureBudget: const Duration(seconds: 8),
      stallSamples: 2,
    );
    health.tick(
      evaluatePicture: true,
      evaluateStall: true,
      viewerPaused: false,
      audioOnly: false,
      playing: true,
      buffering: false,
      ended: false,
      frameAvailable: true,
      frames: 4,
      mediaAdvanced: true,
    );
    health.tick(
      evaluatePicture: true,
      evaluateStall: true,
      viewerPaused: false,
      audioOnly: false,
      playing: true,
      buffering: false,
      ended: false,
      frameAvailable: true,
      frames: 9,
      mediaAdvanced: true,
    );
    final first = health.tick(
      evaluatePicture: true,
      evaluateStall: true,
      viewerPaused: false,
      audioOnly: false,
      playing: true,
      buffering: false,
      ended: false,
      frameAvailable: true,
      frames: 9,
      mediaAdvanced: true,
    );
    expect(first, isNull);
    final stalled = health.tick(
      evaluatePicture: true,
      evaluateStall: true,
      viewerPaused: false,
      audioOnly: false,
      playing: true,
      buffering: false,
      ended: false,
      frameAvailable: true,
      frames: 9,
      mediaAdvanced: true,
    );
    expect(stalled?.kind, StreamHealthKind.stall);
  });

  test('il tetto connessioni si legge dal numero della sorgente', () {
    expect(parseMaxConnections(2), 2);
    expect(parseMaxConnections('4'), 4);
    expect(parseMaxConnections(null), isNull);
  });
}
