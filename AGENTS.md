# Vincoli trasversali

I principi stabili stanno in `.cursorrules`. Non accodare resoconti: aggiorna la frase esistente.

Al termine di ogni modifica richiesta, crea un commit git e fai push sul branch remoto già tracciato. Non riscrivere la storia pubblicata. «Build Android» avvia il workflow GitHub `StellarTV Android Release` e lo segue fino al successo, correggendo gli errori.

- Le cache bambino sul dispositivo includono le certificazioni. I verdetti in cloud si rivalutano. Un consenso vecchio basato solo sul rating non basta. Un verdetto sconosciuto resta nascosto.
- L'identità nativa è StellarTV su ogni piattaforma. I nomi Dart e i bridge nativi del player cambiano insieme.
- La presentazione TV dipende dalla modalità di interfaccia Android. Il layout touch resta quello attuale.
- La sincronizzazione usa l'id dell'account autenticato.
- Le righe legacy del vault non si cancellano da sole. Un preferito rimosso resta un tombstone nella corsia riservata.
- Con una sola connessione ammessa il rilascio del player nativo precede il flusso successivo. Con più connessioni il successivo può aprirsi prima della chiusura, e `released` attende comunque lo smaltimento reale.
- La diretta non entra nella cronologia di visione né nel cloud.
- Un episodio non eredita il voto della serie ma ha il suo. Un voto IMDb non ancora arrivato non si mostra.
- Le note di rilascio pubbliche descrivono solo le novità rispetto a tutti commit fatti dal commit da cui è stata fatta l'ultima build riuscita dello stesso workflow, una volta sola e in linguaggio neutro, a partire da docs/release-current.md, senza copiare il testo dei commit.