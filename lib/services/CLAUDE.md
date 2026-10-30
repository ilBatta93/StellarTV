# lib/services/ — logica senza interfaccia

Regole d'area per Claude e Grok. Valgono anche il master `C:\Progetti\AGENTS.md`, l'`AGENTS.md` della radice e i `CLAUDE.md` delle cartelle superiori.

## Famiglie di file
- Sorgente e catalogo: `catalog_*`, `series_grouping`, `title_*`, `playlist_refresh_service`, `download_service` e i file legacy della sorgente.
- Guida TV: `epg_*` (download, indice, archivio, timeline).
- Metadati e voti: `tmdb_service`, `imdb_*`, `episode_metadata_service`, `introdb_service`, `segment_library`, `catalog_rating_service`.
- Cloud e privacy: `sync_service`, `sync_hooks`, `personal_vault`, `key_handoff`, `tv_pairing_service`, `device_identity`.
- Profilo bambino: `kids_policy`, `kids_content_service`, `kids_pin_service`.
- Primo piano e lavoro: `foreground_*`, `app_foreground_service`, `playback_work_policy`, `stream_slot_policy`, `tv_render_policy`.
- Diagnostica: `live_diagnostics_*`, `vod_diagnostics_*`, `frame_telemetry_*`.

## Invarianti
- Credenziali e indirizzi dei flussi restano sul dispositivo, mai in righe cloud né in snapshot.
- Le chiavi del vault stanno solo nello storage sicuro del dispositivo (`personal_vault.dart`), mai in preferenze o cloud. Cronologia e preferiti vanno in cloud solo tramite il vault cifrato; `cloud_favorites_service` è un adattatore ritirato e non riprende a scrivere.
- La sincronizzazione usa l'id dell'account autenticato. La diretta non entra in cronologia né in cloud.
- Le righe legacy del vault non si cancellano da sole. Un preferito rimosso resta un tombstone nella corsia riservata.
- Profilo bambino: la cache sul dispositivo include le certificazioni; i verdetti in cloud si rivalutano; un vecchio consenso basato solo sul rating non basta; un verdetto sconosciuto resta nascosto.
- Un episodio ha il suo voto, non quello della serie. Un voto IMDb non ancora arrivato non si mostra.
- Le chiamate al sito passano dalle API pubbliche del sito (`src/routes/api/public/`): un formato cambiato qui va cambiato anche lì.
- La diagnostica parte solo da un invio esplicito dell'utente e non contiene credenziali o indirizzi.

## Policy pure
I file `*_policy.dart` sono funzioni pure, verificate da script `test/*_check.dart` gemelli. Se cambi una policy aggiorna lo script, non indebolirlo.

## Verifica
`flutter test test/<servizio>_test.dart` e i `*_check.dart` collegati.
