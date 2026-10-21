# Telecomando durante la riproduzione

- Comandi nascosti: OK mette in pausa e mostra i comandi con Riproduci selezionato; il successivo OK riprende. Se il video è già in pausa, il primo OK mostra soltanto i comandi.
- Salta sigla e il riquadro automatico prossimo episodio conservano la priorità su OK.
- Film/serie: Su mostra nome, trama già disponibile, tempo rimanente e fine stimata per sei secondi. Nessun recupero metadata aggiuntivo. Back chiude soltanto le informazioni.
- Film/serie: Giù apre Audio/Sottotitoli e, sulle serie, Stagioni ed episodi. Riutilizza i selettori esistenti: nessuna duplicazione motori o logica di cambio episodio. Back chiude il selettore senza uscire dal player.
- Diretta: Su canale precedente, Giù successivo. La pausa usa la gestione Diretta già esistente; la ripresa/timeshift effettiva resta dipendente dal flusso/provider.
- A comandi visibili, frecce e OK navigano/attivano i comandi come prima. Mobile invariato. Ripetizioni OK ignorate; nessuna coda di pannelli o zapping da pressione prolungata.

## Verifica

17 controlli Dart della policy superati; analisi della policy senza problemi e formattazione dei file Dart effettuata. Il test telecomando esistente verifica ora anche pausa/ripresa, ripetizioni, apertura pannello e ritorno senza chiudere il player. Il controllo standalone è incluso nel workflow Android manuale.

SDK Flutter non disponibile (download archivio non riuscito): test widget e prova riproduzione reale non eseguiti. Nessuna build Android/IPA e nessuna modifica database. Stabilità dei decoder nativi e focus su TV reale da verificare con futura build esplicitamente richiesta.