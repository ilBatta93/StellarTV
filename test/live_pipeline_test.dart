import 'package:flutter_test/flutter_test.dart';

import 'package:stellar_tv/player/mediakit_engine.dart';
import 'package:stellar_tv/player/playback_session.dart';

void main() {
  group('mpv: solo gli errori di apertura sono fatali', () {
    test('rumore del decoder non chiude la diretta', () {
      expect(MediaKitEngine.isFatalMpvError('Error while decoding frame!'), isFalse);
      expect(MediaKitEngine.isFatalMpvError('Could not open codec.'), isFalse);
      expect(MediaKitEngine.isFatalMpvError('non-existing PPS 0 referenced'), isFalse);
    });

    test('connessione o apertura fallita sono fatali', () {
      expect(MediaKitEngine.isFatalMpvError('Failed to open http://x/1.ts.'), isTrue);
      expect(MediaKitEngine.isFatalMpvError('tcp: Connection refused'), isTrue);
      expect(MediaKitEngine.isFatalMpvError('HTTP error 403 Forbidden'), isTrue);
    });

    test('un errore non fatale viene confermato solo dopo 6 secondi', () {
      expect(MediaKitEngine.confirmWindow, const Duration(seconds: 6));
    });
  });

  group('dirette: pause tra i tentativi', () {
    test('riconnessione a metà visione con attesa crescente', () {
      expect(PlaybackSession.liveReconnectDelay(1), const Duration(milliseconds: 1200));
      expect(PlaybackSession.liveReconnectDelay(2), const Duration(milliseconds: 2400));
    });

    test('cambio formato dello stesso canale attende 1,2 secondi', () {
      expect(PlaybackSession.liveFormatSwitchDelay, const Duration(milliseconds: 1200));
    });
  });
}
