# android/ — progetto nativo Android

Regole comuni: master e `CLAUDE.md` della radice.

## Contenuto
- `app/build.gradle.kts`: `applicationId = "tv.stellar.app"`, firma letta da `key.properties` (non versionato, negato in lettura).
- `app/src/main/AndroidManifest.xml`: launcher touch e `LEANBACK_LAUNCHER` per TV, `banner`, niente backup (`allowBackup=false`, `local_only_data.xml`).
- `app/src/main/kotlin/tv/stellar/app/MainActivity.kt`: canali `stellartv/device` e affini (tipo dispositivo, voce, schermo spento, aggiornamenti).
- Il player ExoPlayer vive nel fork `packages/video_player_android`, non qui.

## Regole
- Mai chiavi, keystore o password nel repository. In CI la firma arriva dai secret (`ANDROID_KEYSTORE_BASE64`…).
- Il backup resta disattivato: credenziali e configurazione non lasciano il dispositivo, nemmeno tramite backup di sistema.
- L'app resta installabile su TV (leanback non obbligatorio, touchscreen non richiesto) e su telefono.
- Un metodo di canale cambiato in Kotlin va cambiato anche nel servizio Dart che lo chiama.
- `minSdk` e versioni Gradle/AGP si toccano solo su richiesta: rompono la build di rilascio.

## Verifica
- `flutter analyze` non copre questa cartella. Una build locale o di rilascio richiede «fai build android» (master §9).
- Senza build, dichiara la modifica non compilata.
