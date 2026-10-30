# packages/video_player_android/ — fork del plugin video Android

Regole d'area per Claude e Grok. Valgono anche il master `C:\Progetti\AGENTS.md`, l'`AGENTS.md` della radice e i `CLAUDE.md` delle cartelle superiori. Il `README.md` qui è quello originale del plugin: non descrive le modifiche di StellarTV.

## Perché esiste
Il `pubspec.yaml` dell'app lo sostituisce al plugin ufficiale (`path: packages/video_player_android`) per controllare ExoPlayer: buffer e caricamento (`ExoLoadControls`), header, eventi, diretta.

## Regole
- Il lato Java e il lato Dart (`lib/`) cambiano insieme a `lib/player/exo_engine.dart` dell'app: stessi nomi di metodo, stesso formato dei messaggi.
- I profili di buffer distinguono anteprima, multivista e riproduzione piena: un ritocco a uno non deve allungare gli altri (in multivista girano fino a quattro player).
- Il rilascio del player nativo deve completarsi prima che `released` risponda.
- Non aggiornare il fork alla versione upstream di propria iniziativa: le modifiche locali andrebbero perse.
- Nessun indirizzo di flusso o header nei log.

## Verifica
- `flutter analyze` dell'app non copre il Java. Compila solo nella build Android, che richiede «fai build android».
- Test Dart del pacchetto: `flutter test` dentro questa cartella.
