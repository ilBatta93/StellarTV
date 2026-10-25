# Vincoli trasversali

Queste frasi valgono in ogni modifica. I dettagli di un'area stanno in `.cursor/rules/` e vengono allegati solo quando i file di quell'area sono nel lavoro. Non accodare qui il resoconto di una modifica: aggiorna la frase esistente, oppure il file `.mdc` dell'area.

Al termine di ogni modifica richiesta, crea un commit git e fai push sul branch remoto già tracciato. Non riscrivere la storia pubblicata.

- Profilo bambino: una sola politica su generi, categorie e certificazioni, in cataloghi, risultati esterni, cronologia, episodi e navigazione. Le cache sul dispositivo includono le certificazioni in una versione nuova. I verdetti in cloud si rivalutano. Un vecchio consenso basato solo sul rating non basta. Un verdetto sconosciuto resta nascosto.
- L'identità nativa è StellarTV su ogni piattaforma. I nomi Dart e i bridge nativi del player cambiano insieme.
- La presentazione TV dipende dalla modalità di interfaccia Android. Il layout e il comportamento touch restano quelli attuali.
- La sincronizzazione usa l'id dell'account autenticato. URL della sorgente, credenziali e indirizzi dei flussi non vanno nel cloud.
- Il vault è AES-256-GCM con revisione. La chiave di recupero resta solo nel deposito sicuro del dispositivo. Le righe legacy non si cancellano da sole. Un preferito rimosso resta un tombstone nella corsia riservata, così un dispositivo vecchio non lo ripristina.
- Una sola sessione di riproduzione nativa alla volta: prima il rilascio completo, poi il flusso successivo. Guida programmi, catalogo e invii cloud aspettano la chiusura della riproduzione; il cloud può partire alla pausa esplicita.
- La diretta non entra nella cronologia di visione né nel cloud. La pausa chiesta dallo spettatore non va riavviata dal controllo di salute.
- IMDb ha la priorità. Un episodio non eredita il voto della serie. Un voto IMDb non ancora arrivato non si mostra.
- Ogni controllo TV nuovo è una tappa raggiungibile col telecomando. Nel player, Indietro chiede conferma.
- Le note di rilascio pubbliche elencano ogni commit incluso, in linguaggio neutro, a partire dai punti di docs/release-current.md. Non copiare il testo dei commit. La sintesi breve alimenta la finestra di aggiornamento.

Aree: `player.mdc`, `tv-ui.mdc`, `catalog-data.mdc`, `live-guide.mdc`, `sync-account.mdc`, `metadata-kids.mdc`, `history.mdc`, `diagnostics.mdc`.
