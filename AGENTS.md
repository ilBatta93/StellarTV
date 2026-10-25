# Vincoli trasversali

I principi stabili stanno in `.cursorrules`. I dettagli di un'area stanno in `.cursor/rules/` e vengono allegati solo quando i file di quell'area sono nel lavoro. Non accodare resoconti: aggiorna la frase esistente.

Al termine di ogni modifica richiesta, crea un commit git e fai push sul branch remoto già tracciato. Non riscrivere la storia pubblicata. «Build Android» avvia il workflow GitHub `StellarTV Android Release` e lo segue fino al successo, correggendo gli errori.

- Le cache bambino sul dispositivo includono le certificazioni. I verdetti in cloud si rivalutano. Un consenso vecchio basato solo sul rating non basta. Un verdetto sconosciuto resta nascosto.
- L'identità nativa è StellarTV su ogni piattaforma. I nomi Dart e i bridge nativi del player cambiano insieme.
- La presentazione TV dipende dalla modalità di interfaccia Android. Il layout touch resta quello attuale.
- La sincronizzazione usa l'id dell'account autenticato.
- Le righe legacy del vault non si cancellano da sole. Un preferito rimosso resta un tombstone nella corsia riservata.
- Una sola sessione di riproduzione nativa alla volta: prima il rilascio completo, poi il flusso successivo.
- La diretta non entra nella cronologia di visione né nel cloud. La pausa chiesta dallo spettatore non va riavviata dal controllo di salute.
- Un episodio non eredita il voto della serie. Un voto IMDb non ancora arrivato non si mostra.
- Le note di rilascio pubbliche descrivono solo le novità rispetto alla release precedente, una volta sola e in linguaggio neutro, a partire da docs/release-current.md, senza copiare il testo dei commit.

Aree: `player.mdc`, `tv-ui.mdc`, `catalog-data.mdc`, `live-guide.mdc`, `sync-account.mdc`, `metadata-kids.mdc`, `history.mdc`, `diagnostics.mdc`.
