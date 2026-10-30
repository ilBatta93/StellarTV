# ios/ — progetto nativo iOS

Regole comuni: master e `CLAUDE.md` della radice.

## Contenuto
- Bundle `tv.stellar.app`, piattaforma minima iOS 15 (`Podfile`).
- `Runner/`: `Info.plist`, `AppDelegate`, asset. `Runner.xcodeproj` è generato in parte da Flutter: modifiche minime e mirate.

## Regole
- L'IPA è non firmata e si produce solo col workflow `build-ios.yml`, su richiesta esplicita.
- Niente certificati, profili di provisioning o chiavi nel repository.
- Il fork `packages/video_player_android` e i canali Kotlin non esistono qui: su iOS la riproduzione passa da media_kit (rami `Platform.isIOS` in `lib/player/mediakit_engine.dart`). Una funzione del player nuova va controllata anche su questa strada.
- Eventuali testi di permesso in `Info.plist` sono in italiano e neutri (master §4).

## Verifica
Non c'è un Mac locale: la compilazione si verifica solo nel workflow iOS. Dichiara la modifica non compilata finché non gira.
