import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/player/exo_engine.dart';

void main() {
  test('anteprima e MultiView non usano il buffer di un film', () {
    final preview = ExoLoadProfile.forPlayback(
      preview: true,
      live: true,
      backBufferMs: 30000,
    );
    final film = ExoLoadProfile.forPlayback(
      preview: false,
      live: false,
      backBufferMs: 30000,
    );
    final live = ExoLoadProfile.forPlayback(
      preview: false,
      live: true,
      backBufferMs: 30000,
    );

    expect(preview.maxBufferMs, lessThan(film.maxBufferMs));
    expect(preview.backBufferMs, 0);
    expect(preview.backBufferRequiresSeekable, isFalse);
    expect(preview.targetBufferBytes, ExoLoadProfile.previewTargetBytes);
    expect(live.maxBufferMs, lessThan(film.maxBufferMs));
    expect(live.minBufferMs, 800);
    // Avvio rapido: basta 400 ms di buffer per la prima immagine.
    expect(live.bufferForPlaybackMs, 400);
    // Ripresa dopo un buco: 2 s per catturare un keyframe.
    expect(live.bufferForPlaybackAfterRebufferMs, 2000);
    // Finestra in avanti: 12 s per assorbire la jitter del provider.
    expect(live.maxBufferMs, 12000);
    expect(live.backBufferMs, 30000);
    expect(live.backBufferRequiresSeekable, isTrue);
    expect(film.backBufferRequiresSeekable, isFalse);
    expect(film.backBufferMs, 30000);
    expect(preview.wire.split(','), [
      '1500',
      '4000',
      '500',
      '1000',
      '0',
      '0',
      '${ExoLoadProfile.previewTargetBytes}',
    ]);
    expect(live.wire.split(',')[5], '1');
  });
}
