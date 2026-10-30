# lib/player/ — motori e sessione di riproduzione

Regole comuni: master, radice e `lib/CLAUDE.md`.

## Contenuto
- `playback_engine.dart`: interfaccia comune (`PlaybackEngine`, tracce, snapshot, eccezioni).
- `exo_engine.dart`: ExoPlayer tramite il fork `packages/video_player_android` e il canale nativo.
- `mediakit_engine.dart`: mpv (media_kit), più tollerante su flussi difficili, sottotitoli e tracce audio multiple.
- `playback_session.dart`: possiede il player visibile, pianifica i tentativi (motore × indirizzo).
- `stream_health.dart`: budget unico per prima immagine e blocchi successivi.
- `decoder_memory.dart`: ricorda le dirette che il decoder hardware non riesce a disegnare.
- `multiview_audio.dart`: un solo proprietario dell'audio in multivista.
- `tv_playback_shortcuts.dart`: tasti del telecomando a controlli nascosti.

## Invarianti
- Con una sola connessione ammessa, il rilascio del player nativo precede l'apertura del flusso successivo. Con più connessioni il successivo può aprirsi prima, e `released` attende comunque lo smaltimento reale.
- Un cambio di focus rapido non crea mai due proprietari dell'audio.
- La diretta non entra nella cronologia di visione né nel cloud.
- I bridge nativi e i nomi Dart cambiano insieme (vedi `packages/video_player_android/CLAUDE.md`).
- Nessun indirizzo di flusso nei log inviati o nella diagnostica cloud.

## Verifica
- `dart run test/tv_playback_shortcuts_check.dart`, `dart run test/playback_work_policy_check.dart`, `dart run test/live_preview_policy_check.dart`.
- I test `test/*player*`, `test/*playback*`, `test/*stream*` pertinenti.
- Il comportamento reale (decoder, buffer, TV) non si verifica in CI: dichiaralo non verificato.
- Analisi di riferimento: `docs/live-playback-review.md`, `docs/playback-cloud-stability.md`, `docs/tv-playback-shortcuts.md`.
