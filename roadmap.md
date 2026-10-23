# Roadmap

## Fluidità, banner e metadati — 23 ottobre 2026
- [x] Rimossa scansione categorie da Home; indice locale asincrono per schede, membership piattaforme per ID, invalidazione sui contenuti.
- [x] Banner 1280px normale/960px sotto pressione, anche nel limite effettivo PosterImage; diagnostica invariata.
- [x] Cache opzionale dettagli/cast/videos per ID, endpoint e lingua; scritture con account verificato, fallback e nessun prefetch. SQL manuale preparato.
- [x] Android 3.7.14 run 39999271795 riuscita: test, APK, prove native e pubblicazione completati; APK 112188897 byte e note neutre verificati; 27 test sito e 12 controlli grafici superati. Guida aggiornata.
- [ ] Attivazione cache condivisa: SQL nel database esterno e pubblicazione sito; lettura reale TMDB in locale non verificata perché TMDB_API_KEY non disponibile nell’anteprima.
- [ ] Prova fluidità sulla TV: richiede dispositivo utente.

## Crunchyroll e rifiniture TV — 23 ottobre 2026
- [x] Crunchyroll nei filtri piattaforma Film e Serie TV, senza scheda Anime; colori distintivi per tutte le piattaforme.
- [x] Generi subito selezionabili, conteggi locali senza scansioni nel disegno; filtri metadata/Kids invariati.
- [x] Indietro risolve l'icona anche con focus distaccato; callback obsolete annullate e frecce gestite dalla griglia.
- [x] Banner Home limitato a 480px sotto pressione; etichette categorie memorizzate e conteggi senza sort nei pannelli chiusi.
- [x] Android 3.7.10 (run 39979947181): test e build riusciti, APK pubblicato; errore del primo tentativo corretto. Guida e note neutre aggiornate, diagnostica invariata.
- [ ] Verifica 3.7.10 sul televisore reale: frecce rapide, banner e fluidità richiedono dispositivo utente; sito aggiornato solo in anteprima, pubblicazione non richiesta.

## Cataloghi progressivi e diagnostica persistente — 23 ottobre 2026
- [x] Eliminare raggruppamenti pesanti durante il disegno e preparare cataloghi progressivamente, conservando dati e protezioni player.
- [x] Salvare localmente la diagnostica e rendere esportabile la sessione precedente dopo un riavvio.
- [x] Aggiornare guida e note neutre, verificare regressioni.
- [x] GitHub 24a7d5b salvato; Android 3.7.2 run 92 (39945609120) riuscita: test, APK, verifiche native e pubblicazione. Corretto import ordinamento Diretta trovato nella prima build. Tredici test sito superati.
- [ ] Misurare fluidità e memoria sulla TV: richiede dispositivo dell’utente.

## Avvio TV, voce, chiave guidata e 3.7 — 23 ottobre 2026
- [x] Lavori pesanti all'avvio TV rinviati (30 s) e sospesi finché il telecomando non è fermo da 2 s.
- [x] Microfono in tutti i campi di testo TV (riconoscimento vocale di sistema).
- [x] Chiave di recupero guidata su app e sito: nessuna nuova chiave se la cassaforte esiste; guida aggiornata.
- [x] Numerazione passata a 3.7.0 dalla build 90.
- [x] Build Android 3.7.0 (run 90) riuscita: test, compilazione e pubblicazione; corrette prima note di rilascio mancanti.
- [ ] Prova su TV di avvio, microfono e chiave: richiede dispositivo dell'utente.

## Timeline EPG, fluidità TV e build — 23 ottobre 2026
- [x] Intervalli di presentazione EPG non sovrapposti, orari originali per playback e linea tema allineata.
- [x] Ridotti da tre a uno gli strati grafici Discover TV e tolta ombra linea EPG; transizioni già immediate, touch/player invariati.
- [x] Note automatiche con sintesi di tre novità e gestione frecce direttamente sul focus del testo; generazione neutra per Android/IPA basata sui cambiamenti dalla versione precedente.
- [x] Guida aggiornata; GitHub b3e65653 salvato. Android 3.6.22 run 87 (39919633264) seguita fino a successo: test EPG/telecomando, compilazione, prove native e pubblicazione riusciti; note pubbliche neutre e APK da 111.729.925 byte verificati. Sette test sito e tre test note superati; nessun errore da correggere.
- [ ] Verifica reale sulla TV: richiede installazione dell’utente.

## Build Android richiesta — 23 ottobre 2026
- [x] Confermate su GitHub le ottimizzazioni aggiornamento completo e guida del commit ed596bff; avviato workflow Android su main.
- [x] Android 3.6.21 run 86 (39879186951) seguita fino al completamento: test, compilazione, verifiche native e pubblicazione tutti riusciti, nessuna correzione o riavvio necessario.
- [x] APK pubblico verificato (111.729.925 byte), note neutre lette; risultato e controlli su TV pronti.

## EPG e aggiornamenti completi — 23 ottobre 2026
- [x] Guida con download/parser progressivo cancellabile, gzip/redirect, errori classificati e cache precedente conservata; precedenza agli aggiornamenti completi.
- [x] Pubblicazione playlist suddivisa in piccoli blocchi con controlli account/profilo/evidenze, salvataggi seriali, lavori preparatori rinviati e attese annullate su logout/dispose; cache e identificativi invariati.
- [x] Guida e note neutre aggiornate, punti diagnostici per ricezione/pubblicazione/cache; GitHub ed596bff verificato (16 file), dieci prove Dart superate, analisi nuovi moduli pulita e 12 controlli foreground/anteprima superati; 13 test sito superati, sito build OK.
- [x] Test Flutter integrati, incluse nuove prove EPG e pubblicazione catalogo, superati nella build Android 3.6.21 run 86.
- [ ] Verifica su TV di aggiornamento completo, telecomando e guida reale con diagnostica avvio: richiede installazione dell’APK e dispositivo dell’utente.

## Ripresa sequenziale e build Android — 22 ottobre 2026
- [x] Ripresa dall’episodio più recente e successore immediato anche già visto, senza alterare le altre cronologie; controlli Home per profilo/progresso e risultati obsoleti scartati (4556fd1).
- [x] Cinque nuove prove ripresa superate; guida neutra aggiornata, sei test sito superati e sito build OK.
- [x] Android 3.6.20 run 85 completata e APK pubblico verificato: corretta prova aggiornamento (1254501, b1e3aea); rilanciata compilazione dopo download NDK danneggiato; tutti i passi riusciti e note neutre verificate.
- [ ] Verifica sul dispositivo: episodio 6 torna in Home alla posizione recente, poi 7→8 anche già visti; altri stati conservati, fine ultimo episodio e autoplay disattivato. Richiede dispositivo dell’utente.

## Regressione EPG — 22 ottobre 2026
- [x] Verificato anche il mancato download della lista: anteprima e blocco playback possono rinviare il lavoro EPG/cataloghi; nessuna richiesta al database.
- [x] Letti schermata, provider, parser, scheduling e policy: download EPG cancellato dall’anteprima e scheduling iniziale bloccato senza mantenere il lavoro dovuto.
- [x] GitHub 75f46514 verificato (7 file): anteprima attende inizializzazione/caricamenti/rinvii, download dovuti mantenuti, selezione riletta dal catalogo e ritorno da pagine gestito. Guida e note neutre aggiornate; quattro prove Dart e analisi policy superate, sei test sito superati e sito build OK.
- [ ] Compilazione e test Flutter superati in Android 3.6.20; conferma download EPG reale ancora da effettuare sul dispositivo dell’utente.

## Navigazione note aggiornamento — 22 ottobre 2026
- [x] Note scorribili Su/Giù con focus iniziale su Aggiorna e ritorno ai pulsanti.
- [x] Test mirati aggiunti, guida neutra aggiornata e GitHub 7de68bc2 salvato; nessuna build avviata.
- [ ] Tre prove Flutter aggiornamento superate in Android 3.6.20; conferma su TV ancora richiesta sul dispositivo dell’utente.

## Build Android richiesta — 22 ottobre 2026, 17:22 UTC
- [x] Android 3.6.17 run 82 da d989d89e completata con successo: test Flutter, compilazione, verifiche native e pubblicazione tutti riusciti.
- [x] Nessun errore bloccante né riavvio necessario; APK pubblico verificato (111.418.629 byte) e note neutre lette.
- [x] Download e riepilogo pronti; prova reale di fluidità resta sul dispositivo dell’utente.

## Raster e navigazione TV — 22 ottobre 2026
- [x] Alleggeriti focus TV, riempimenti immagini duplicati e dissolvenza di avvio; touch e dati invariati.
- [x] Memoria scarsa: sfondo decorativo rimosso fino al riavvio completo e nuove decodifiche limitate; riga vicina completa conservata per D-Pad, nessun ricaricamento simultaneo.
- [x] Guida e note neutre aggiornate; GitHub d989d89e verificato (13 file), 10 controlli policy e regressione ordinamenti/100.000 voci superati, analisi policy senza problemi; 9 test sito superati.
- [x] Prova widget D-Pad sotto memoria scarsa e compilazione Flutter superate nella build Android 3.6.17 run 82.
- [ ] Misurare nuovamente su TV reale: richiede APK autorizzata e dispositivo dell’utente.

## Build Android 3.6.15 — 22 ottobre 2026
- [x] Build avviata dal salvataggio 32d193de (run 80).
- [x] Corretto il passaggio «Verify Home and episode completion» (PaintingBinding, 92124fdf): Android 3.6.16 run 81 riuscita.

## Stabilizzazione guidata dal rapporto — 22 ottobre 2026
- [x] Ridotti precaricamenti TV, fade e memoria immagini; cache su disco conservata e limite ridotto su memoria scarsa.
- [x] Righe con identità stabile e indici limitati; ordinamenti in isolate, sorgenti filtrate/recenti memorizzate e risultati tardivi scartati.
- [x] Guida e regole aggiornate; GitHub 32d193de verificato (16 file), note pubbliche neutre. 93 test sito e prove Dart su otto ordini/100.000 voci superati; analisi modulo Dart senza problemi.
- [x] Prove widget Flutter e compilazione Android superate nelle build 3.6.16 e 3.6.17.
- [ ] Prova reale sulla TV dopo installazione: richiede dispositivo dell’utente; nessuna nuova build richiesta.

## Reattività e cronologia — 22 ottobre 2026
- [x] Home disponibile dai dati locali senza attese di rete; protezione per aggiornamenti pesanti conservata.
- [x] Gestisci visione più chiaro e utilizzabile col telecomando.
- [x] Ultima posizione effettiva del singolo episodio autorevole, anche indietro/avanti e riapertura.
- [x] Passaggio automatico sincronizzato come preferenza comune; eventuale SQL solo manuale.
- [x] Verifica servizio nella Diagnostica e mantenuta negli errori.
- [x] Tipi sito indipendenti dal Cloud interno, guida e controlli aggiornati.
- [x] Test e revisione stabilità; GitHub 7e4d8540 e 7abe788a. 197 test Flutter superati, 2 saltati; 43 test sito superati.
- [x] Android 3.6.8 run 73 riuscita; poi IPA unsigned 3.6.8 run 16 riuscita, analisi e pacchetto verificati.
- [x] Download, novità e verifiche pratiche preparati per la consegna.
- [ ] Prove reali Home, seek, gestione visione e sync su TV/telefono: richiedono installazione e account dell’utente. Nessuna modifica database eseguita; sito non pubblicato.

## Stabilità e riproduzione — 22 ottobre 2026
- [x] Impostazione locale avanzamento automatico, diagnosi locale servizio su richiesta/errore e miglioramento sigla/coda senza scansioni pesanti; capitoli mpv una sola volta e suggerimento finale solo manuale.
- [x] Guida neutra e controlli sito aggiornati; revisione indipendente e modifiche GitHub 8f7f7b55/d45cc03a. Android run 71 riuscita, test nuovi e regressioni superati dopo correzione attesa di teardown; nessuna modifica DB.
- [x] Android 3.6.6 run 71 riuscita: 185 test Flutter superati, 2 saltati, controlli ibernazione/native riusciti. IPA 3.6.6 unsigned run 15 riuscita, analisi Dart e validazione bundle superate; entrambi i download pubblici verificati.
- [x] Download e lista prove consegnati; 26 test sito superati e sito senza errori. Nessuna pubblicazione sito richiesta o eseguita.
- [ ] Prova reale riproduzione, diagnosi servizio e capitoli su TV/telefono: richiede installazione dell’utente e sorgenti reali; non verificabile nel sandbox. Guida autenticata con account esterno non verificata dal browser.

## Comandi player TV — 21 ottobre 2026
- [x] OK: pausa e comandi; VOD Su informazioni locali per sei secondi, Giù pannello rapido con selettori esistenti; Diretta Su/Giù zapping. Priorità Salta sigla/outro, protezione ripetizioni/pausa pendente e Back duplicato conservate.
- [x] 17 controlli Dart superati, analisi policy senza problemi, revisione indipendente e GitHub 85c24adf verificato (9 file); test widget esteso e incluso nel workflow manuale. Nessuna build né modifica database.
- [ ] Test widget Flutter: SDK non disponibile, archivio non scaricabile; richiede ambiente Flutter o futura build autorizzata.
- [ ] Prova reale telecomando e riproduzione: richiede futura build autorizzata e TV dell’utente.

## Ibernazione automatica — 21 ottobre 2026
- [x] App: sospensione cloud e attività automatiche quando non visibile; dati locali conservati, ripresa coalescente e cooldown mantenuto.
- [x] Segnali Android schermo/HDMI e lifecycle integrati, senza polling né esclusiva account; rilevamento TV best-effort.
- [x] 22 controlli Dart superati, analisi policy/trasporto senza errori, 21 file Dart formattati; documentazione e GitHub 581014e verificati. Nessuna build o modifica DB.
- [ ] Compilazione Flutter/native e test integrazione timer: richiedono SDK/dipendenze complete e futura build autorizzata.
- [ ] Prova TV spenta/HDMI e richieste reali: richiede nuova build autorizzata e dispositivi utente.

## Rimozione polling disconnessione remota — 21 ottobre 2026
- [x] Eliminazione completa richiesta alle 17:22: ripuliti riferimenti sito/app e preparato SQL manuale per rimuovere solo la tabella richieste remote dal database esterno.
- [x] App Flutter: rimossi servizio periodico e integrazioni remote, preservando Esci e sicurezza account; GitHub 7ccccfd9.
- [x] Companion: eliminate richieste singole, polling e storico remoto; elenco su apertura/Aggiorna e guida coerente.
- [x] 11 test sito e 9 controlli Dart superati; main GitHub verificato, sito senza errori. Nessuna build, esecuzione SQL o pubblicazione.
- [ ] Eliminazione effettiva tabella sul database esterno: richiede esecuzione personale dell’SQL allegato, dopo aggiornamento/arresto vecchie app.
- [ ] Verifica Flutter completa e account reale sito: SDK Flutter/dipendenze non disponibili, autenticazione esterna non gestita; nessuna prova reale dichiarata.
- [ ] Misurare riduzione reale dopo nuova installazione: richiede futura build autorizzata e log esterni dell’utente.

## Stabilità player, EPG e cloud — 21 ottobre 2026
- [x] Player: comandi inizialmente nascosti, selezione telecomando Salta sigla senza riapertura barre; GitHub c0149890.
- [x] EPG/playlist: protezione condivisa player/anteprime/MultiView; cloud invii rinviati a pausa esplicita/fine/chiusura, jitter conflitti 250–400 ms e backoff conservato.
- [x] SQL manuale opzionale compatibilità cloud=2, wrapper con originale conservato e controllo firma; nessuna esecuzione DB, nessuna rotazione chiavi, nessuna build.
- [x] Sette controlli Dart e analisi policy superati; revisione indipendente e salvataggio GitHub confermati.
- [ ] Test Flutter completi e prova reale telecomando/cloud: Flutter assente, pacchetti pub.dev bloccati da TLS; test aggiunti al workflow manuale, richiedono futura build autorizzata e dispositivi/account reali.
- [ ] Protezione SQL da applicare personalmente dopo installazione nuova app; CPU/richieste da misurare: nessuna riduzione ancora dimostrata.

## Riduzione pressione database esterno — 21 ottobre 2026
- [x] App: coda normalizzata con protezione in-flight/cooldown; invii serializzati e confronto del merge con lettura remota fresca prima di riscrivere vault; GitHub 1d4111ad verificato, 5 file.
- [x] Sito: richieste vuote senza DB, parallelismo 6, insert cache concorrenti senza riscritture e confronto evidenze; 33 test sito superati, endpoint vuoto HTTP 200, build OK.
- [x] SQL manuale non distruttivo e misurazione prima/dopo consegnati; nessuna cancellazione, resize, pausa o modifica della frequenza sync applicata.
- [x] 6 verifiche coda Dart e analisi senza errori; salvataggio GitHub verificato; nessuna build app o pubblicazione.
- [ ] Applicazione SQL e confronto CPU/chiamate sul database esterno: richiedono esecuzione utente e nuovo report comparabile; riduzione del carico non ancora misurata.
- [ ] Compilazione/test Flutter completi e prova cloud multi-dispositivo: richiedono dipendenze Flutter e futura build autorizzata/account reale.

## Completamento piano Companion e visione — 21 ottobre 2026
- [x] Companion: organizzazione adattiva, sezioni ordinate e checklist post-aggiornamento; telefono/tablet/computer verificati con sessione simulata, senza dati utente.
- [x] Durata browser 1/8/24 ore, dal prossimo accesso e logout locale; 10 test e persistenza scelta verificata.
- [x] App: Gestisci visione, episodi/stagioni/serie e precedenti, suggerimento discreto; eventi cifrati reversibili separati dai progressi; GitHub aac0d8b verificato (14 file).
- [x] Diagnostica guidata sicura app/sito con scelta facoltativa e invio/export espliciti, senza cambiare il player.
- [x] 29 test sito, 9 verifiche logica Dart, analisi modelli senza errori; build sito OK. Nessuna build app o pubblicazione avviata.
- [ ] Test Flutter completi e prova telecomando/persistenza su TV: richiedono SDK Flutter con dipendenze (qui download pub.dev bloccato) e dispositivo reale; test aggiunti in repository.
- [ ] Verifica Companion con account reale e invio diagnostica/cloud tra dispositivi: autenticazione esterna non disponibile per prove gestite; nessun dato utente modificato.


## QR TV e rete di sicurezza aggiornamenti — 21 ottobre 2026
- [x] Sito: riaprendo il link QR (pagina chiusa o accesso fatto dopo) l'account che ha autorizzato la TV torna all'inserimento dati; test 5/5.
- [x] App: pulizia post-aggiornamento una volta per versione, solo cache immagini ricostruibili, mai dati personali; mai blocca l'avvio (GitHub 91274d6).
- [ ] Prova su TV: richiede nuova build su richiesta dell'utente.

## Navigazione superiore e pausa Diretta — 20 ottobre 2026
- [x] Su dagli strumenti Film/Serie verso scheda attiva e navigazione esplicita orizzontale; GitHub bf833887 verificato.
- [x] Dirette escluse dal replay; pausa protetta da watchdog e recupero automatico; GitHub bf833887 verificato.
- [x] Aggiunte regressioni per cataloghi/ordine/telecomando e pausa/ripresa/VOD; incluse nei controlli Android.
- [x] Android 3.5.2 pubblicata: run 61 riuscita, APK 110,7 MB, test Flutter e Android superati; note complete verificate su entrambe le release. Primo tentativo 3.5.1 fermato da simulazione Back nel test, corretta in 22287b8.
- [ ] Prova telecomando e pausa su TV reale: richiede dispositivo dell’utente.

## Indietro nelle liste filtro Film e Serie TV — 20 ottobre 2026
- [x] Correzione generi/piattaforme: ritorno all’icona anche durante cambio focus e doppio invio hardware/sistema; GitHub bbadc566 verificato in lettura.
- [x] Aggiunti test primo Back, ritorno all’icona e successivo Back al menu; nessuna build richiesta.
- [x] Test Flutter superati nella build Android 3.5.2.
- [ ] Prova su TV dei filtri: richiede dispositivo utente.

## Nuove impostazioni predefinite — 20 ottobre 2026
- [x] Valori delle foto verificati: Home e soglia 94% già conformi; cataloghi aggiornati a Poster e Grande, sia iniziali sia al ripristino, senza sovrascrivere preferenze salvate.
- [x] Modifiche e test di regressione salvati e riletti su GitHub (d16c599); verifiche statiche superate, nessuna build richiesta.
- [x] Test Flutter superati nella build Android 3.5.2.
- [ ] Prova dei default su dispositivo: richiede TV dell’utente.

## Log player e dispositivo per film e serie — 20 ottobre 2026
- [x] Impostazioni: «Diagnostica film e serie» con la stessa struttura di quella delle Dirette (GitHub 9bb4a87)
- [x] Sito: stesso archivio «Log errori»; il rapporto porta già l'etichetta «film e serie» nel file
- [ ] Prova su TV reale con micro scatti: serve la prossima build richiesta dall'utente



## Chiusura stream — 20 ottobre 2026
- [x] Player, anteprima Diretta e MultiView chiudono la connessione del provider all'uscita, in background, a schermo spento e TV spenta (GitHub 13b6db8)
- [ ] Prova automatica e su TV reale: serve la prossima build richiesta dall'utente

## Build 3.3.8 — 19 ottobre 2026
- [x] Build Android 3.3.8 riuscita (run 45, commit d56ca82): APK da 110 MB pubblicato, nel repository pubblico resta solo l'ultima versione.
- [x] Note di rilascio riscritte in modo comprensibile e applicate a entrambe le pubblicazioni.
- [x] /apk del sito reindirizza a v3.3.8 (verificato live, aggiornamento automatico).
- [ ] Prova 3.3.8 su TV reale: serve l'utente

## Archivio immagini condiviso — 19 ottobre 2026
- [x] Archivio cloud condiviso di loghi/locandine/sfondi (solo percorsi pubblici TMDB) e servizio /api/public/artwork; 3 test.
- [x] App: loghi letti prima dall'archivio condiviso, poi TMDB diretto; immagini del provider solo locali. GitHub 970774e.
- [ ] Prove Flutter non eseguibili qui (download dipendenze bloccato); serve pubblicazione sito e nuova APK su richiesta.

## Film recenti e completamento 95% — 18 ottobre 2026
- [x] Soglia visto regolabile nelle impostazioni, iniziale 95%, sincronizzata tra dispositivi.
- [x] Schede film e serie: minuti rimanenti nel pulsante Guarda ora per contenuti già avviati.
- [x] Minuti rimanenti a destra dei film recenti, con lo stesso layout di stagione/episodio.
- [x] Regola condivisa di completamento dal 95% per film ed episodi, con test e verifica GitHub.
- [ ] Prova su TV reale: richiede nuova APK autorizzata e dispositivo dell’utente.

- [x] Home TV: proporzioni adattive per banner con trama e caroselli a piena altezza utile; stagione/episodio a destra dei titoli recenti, recupero dal nome per cronologia ripristinata; GitHub ac8b61b. Sintassi e 4 test logica episodio superati tramite Dart; verifica numerica a 4 altezze. Test UI Flutter bloccati da TLS scaricamento dipendenze; prova visiva/telecomando resta da eseguire con prossima APK e TV. Nessuna build APK avviata.

- [x] Invio chiave dal telefono alla TV cifrato end-to-end monouso (2 min); sito /chiave e app (GitHub 7f5a986); compatibilità cifratura sito↔TV e invio reale verificati. Serve APK e prova su TV.
- [ ] Dirette: attendere nuovo log dall’utente (log precedente annullato, problema provider).

- [x] Companion: elenco accessi attivi tramite funzione owner-only, metadati senza token/IP, disconnessione generale confermata; lettura account reale e annullamento provati, anon senza permessi. Revoca reale non eseguita per non disconnettere i dispositivi utente; sessione di test sintetica non corrisponde a un dispositivo reale.

- [x] Privacy ottobre 18: ripuliti campi sorgenti nei salvataggi attivi senza cancellare cronologia/preferiti; scritture legacy bloccate, conteggi e assenza campi sensibili verificati.
- [x] Privacy ottobre 18: copia cifrata sito AES-256-GCM, chiave separata non cloud e scritture con revisione; 20 test passati, account e chiave errata verificati nel browser senza scrivere dati utente.
- [ ] Privacy ottobre 18: integrazione Flutter e trasferimento chiave QR, rimozioni preferiti multi-dispositivo e test nativi; copia temporanea persa al rinnovo sandbox prima del salvataggio GitHub, da ricostruire. Nessuna modifica Flutter integrata.
- [ ] Privacy ottobre 18: migrazione completa e prova cloud cifrata fra dispositivi con chiave conservata dall’utente; pulizia legacy disabilitata per evitare perdite, dati precedenti ancora in chiaro senza sorgenti.
- [x] Privacy ottobre 18: testi sito neutrali, noindex pagine/risposte e limiti backup documentati; serve pubblicazione richiesta dall’utente per sito live.
- [ ] Privacy ottobre 18: testi app e release GitHub da aggiornare con integrazione Flutter; nessuna riscrittura della cronologia.

- [x] Ottobre 18: accesso app device-local; esclusi token e PKCE dalla sync, logout locale e avvio senza attesa inutile; regressioni superate.
- [x] Ottobre 18: sito con scadenza assoluta 8 ore e logout locale; 6 test e controllo account autenticato, refresh e scadenza nel browser.
- [x] Ottobre 18: cache persistente loghi it/en, precaricamento adiacente limitato e Home TV con locandine più grandi e meno spazio vuoto.
- [x] Ottobre 18: QR Apple e sfondo spaziale, screenshot TV/telefono; 19 test Flutter mirati nella copia compatibile, nessun lettore cambiato.
- [x] Ottobre 18: integrato commit 592dd6e; nessuna nuova APK avviata.
- [x] Ottobre 18: tre SVG E orbitale v2 con tracciati e sfumature editabili consegnati; tutti renderizzati e ispezionati.
- [x] Ottobre 18: SVG in app e sito, favicon, immagini profili/QR e icone native aggiornati; GitHub 4559ae2, prova Flutter isolata e sito desktop/mobile superate. Nessuna APK o pubblicazione sito avviata.
- [ ] Ottobre 18: verifica riavvio app su hardware e dipendenze originali; serve prossima APK e dispositivo utente. Pubblicazione sito su richiesta.

- [x] Ottobre 18: valutare le proposte allegate contro il codice corrente delle dirette, anteprima e MultiView
- [x] Ottobre 18: applicare correzioni sicure a ciclo di vita, rendering e recupero flussi; 19 test mirati passati nella copia compatibile, test nativi/dipendenze originali richiedono CI
- [x] Ottobre 18: integrato su GitHub e0d25ed; nessuna nuova build avviata
- [ ] Ottobre 18: test nativi/dipendenze originali (serve ambiente CI) e prova hardware/provider (servono dispositivi e lista dell'utente)

- [ ] Ottobre 17 (12): loghi senza titolo transitorio, avvio e interfaccia più fluidi
- [ ] Ottobre 17 (12): compatibilità dirette ExoPlayer e recupero sicuro dei canali
- [ ] Ottobre 17 (12): catch-up provider e timeshift/pausa ExoPlayer dove supportato
- [ ] Ottobre 17 (12): test multipiattaforma e limiti reali; integrare tutto e avviare build APK Android richiesta dall’utente

- [x] Ottobre 17 (11): scheda film coerente con serie, azioni orizzontali preparate localmente
- [x] Ottobre 17 (11): ripristino frecce orizzontali episodi con ruoli runtime e percorso esplicito selettori Top Home
- [x] Ottobre 17 (11): trailer italiano con fallback inglese nelle schede film/serie, apertura esterna con OK verificata
- [x] Ottobre 17 (11): 12 test Flutter mirati e 6 test sito superati; immagini reali a 960×540 e 1280×720
- [x] Ottobre 17 (11): immagini approvate dall’utente
- [ ] Ottobre 17 (11): integrare schede, trailer e navigazione approvati insieme alle ottimizzazioni attuali; nessuna build richiesta

- [x] Ottobre 17 (10): episodi TV con navigazione orizzontale separata dalle azioni raggiungibili con Giù, preparati nella copia locale
- [x] Ottobre 17 (10): Home TV sotto la barra, logo e descrizione distanziati, un solo carosello intero; logo anche nella route serie effettiva, preparati nella copia locale
- [x] Ottobre 17 (10): 14 test locali superati con adattamento del solo lettore video nella copia di prova; foto reali Flutter a 960×540 e 1280×720, analisi mirata senza errori né warning
- [x] Ottobre 17 (10): correzioni salvate su GitHub (dfb32971), build Android 3.2.0 (run 25) riuscita e APK pubblicato
- [ ] Ottobre 17 (10): prova finale sulla TV dell’utente (serve utente)

- [x] Ottobre 17 (8): Home con loghi titoli e schede panoramiche, nomi puliti, progresso percentuale (b2024a79)
- [x] Ottobre 17 (8): completamento episodio dal riquadro automatico successivo, 13 test regole/cronologia profili/telecomando superati localmente; CI screenshot reso autonomo (91077f84)
- [x] Ottobre 17 (8): build Android 3.1.10 (run 23) riuscita dopo controlli CI completi, APK pubblicato
- [x] Ottobre 17 (9): build Android 3.1.11 (run 24) riuscita, APK pubblicato con note della Home aggiornata; /apk punta a v3.1.11
- [ ] Ottobre 17 (8): loghi disponibili nell’app dopo pubblicazione sito (serve richiesta pubblicazione); prova su dispositivi reali (serve utente)

- [x] Ottobre 17 (7): login account/Xtream ridisegnato; tastiera solo tap/OK e riapertura verificata TV/mobile; composizione raster ufficiale senza lettere inventate
- [ ] Ottobre 17 (7): orbita indipendente nell’animazione (servono asset originali separati di simbolo e orbita)
- [ ] Ottobre 17 (7): build completa e prove accesso/logout/Xtream cloud su dispositivi reali (servono autorizzazione build e dispositivo utente)
- [x] Ottobre 17 (7): Disconnetti torna ad AccountScreen iniziale; editor URL/username/password verifica prima di salvare, forza sync cloud esistente e segnala download incompleti; 13 test isolati e analisi mirata superati

- [x] Ottobre 17 (6): scorrimento visibile Home TV e recenti corretto su GitHub (fc18d5ad); test telecomando con 50 e 100 titoli superati, falliscono sul codice precedente; analisi mirata senza errori
- [ ] Ottobre 17 (6): nuova build APK e prova dello scorrimento su Fire TV (serve conferma build e dispositivo utente)
- [x] Ottobre 17 (5): sito con versione esatta dell'ultima release, pagina Download con APK/IPA e codice Downloader 2252158, indirizzo /apk (commits sito)
- [x] Ottobre 17 (5): build 3.1.7 riuscita (run 20) con QR completato, accesso mantenuto, dirette con decoder nativo e righe Home bloccate ai bordi; APK pubblicato e /apk punta a v3.1.7
- [ ] Ottobre 17 (5): build iOS 3.1.7 (da avviare, serve conferma utente)
- [ ] Ottobre 17 (5): prova su Fire TV di dirette, QR e navigazione (serve utente)



- [x] Ottobre 16 (3): schermo nero con solo audio (watchdog ExoPlayer → formato/motore alternativo, anche in anteprima), schede titolo TV più in alto, selettore disposizione locandine (griglia/compatta/lista), cache immagini 8000 + precaricamento poster (commit 28424bd8)
- [ ] Ottobre 16 (3): prova su TV reale delle nuove correzioni (serve build Codemagic + utente)
- [x] Ottobre 16 (2): dirette stabili (un player alla volta, ExoPlayer predefinito Dirette TV, anteprima ExoPlayer, MPV/MDK corretti, impostazioni per motore)
- [ ] Ottobre 16 (2): prova su TV reale (serve build Codemagic + utente)
- [ ] Ottobre 16: prova su TV reale di MPV/MDK (serve build Codemagic)

- [x] Ottobre 16: MPV dirette schermo nero, codec e fluidità; terzo player IPTV/Xtream
- [x] Ottobre 16: crash Diretta scendendo con anteprima attiva; icone → lista canali e risalita da ogni elemento
- [x] Ottobre 16: pulsante MultiView nel player diretta
- [x] Ottobre 16: pannello episodi nel player con progresso/visto, immagini, Back episodi→stagioni→player, stile Apple

- [x] Ottobre 15: Home TV con solo titolo nel banner, senza trama
- [x] Ottobre 15: Diretta loghi e separatori coerenti; percorsi Su strumenti/menu da canali, EPG e anteprima
- [x] Ottobre 15: 25 test D-Pad superati e correzioni salvate su StellarTV main, commit 3e03c63f

- [x] Ottobre 15: testi Home, Diretta compatta sonora, banner ultima visione e MultiView salvati in StellarTV main, commit 2851f1fa
- [x] Ottobre 15: 10 test mirati superati; regressione 53 superati, uno splash bloccato da inizializzazione cloud del test
- [ ] Ottobre 15: build originale e verifica MPV/audio/telecomando su TV reale (servono Codemagic e dispositivo utente)

- [ ] Foto ottobre: intestazioni Home intere e selettori Top raggiungibili da ogni locandina
- [ ] Ultimi aggiunti: 100 film e 100 serie
- [ ] Episodi orizzontali e pannello stagioni/episodi durante la riproduzione
- [ ] Mi piace/non mi piace per profilo e consigli personalizzati
- [ ] Diretta moderna con EPG integrata e anteprima canale
- [ ] Rifacimento schermate Apple e verifiche automatiche D-Pad

- [x] Promemoria scadenza Xtream, sync istantanea, cache voti e immagini, filtri memorizzati
- [ ] Ottimizzazione parte 2: buffer player, avvio differito, effetti TV più leggeri (da fare)

- [ ] TV: doppio Back serie verso scheda titolo; Back progressivo ricerca e filtri genere
- [ ] TV: opzioni compatibili con motore player e margini nomi locandine
- [x] TV: voto veloce, EPG, uscita player, poster, cronologia, aggiorna tutto, info Xtream, orologio, serie consigliate

- [x] Playlist aperta dalla copia sul dispositivo, aggiornamento solo a intervallo
- [x] Avvio e navigazione più leggeri (controlli bambini, salvataggi in background)
- [x] Player TV: telecomando riscritto, doppio Indietro per uscire
- [x] Riproduzione più fluida (ExoPlayer su superficie nativa, mpv ottimizzato)
- [x] Schede film/serie: risalita fino a "Guarda ora", episodio dentro lo schermo
- [ ] Prova dell'APK sul televisore (in attesa dell'utente)
- [x] Cataloghi TV: ricerca a scomparsa e ordinamento nella categoria
- [x] Cataloghi TV: ritorno alla barra superiore e voti locandine
- [x] Scheda attore TV coerente con schede titolo
- [x] TV: percorso verticale menu, strumenti, filtri e griglia; ordinamento provider
- [x] TV: ricerca cancellabile e chiusa verso il basso, spazi e nomi leggibili
- [x] TV: cuore preferiti, iniziale profilo, risalita attori e sfondo titolo stabile
- [x] Player: primo Back nasconde controlli; inizializzazione dirette MPV corretta (prova reale nel task APK)
- [x] Impostazioni player TV: Dirette TV e Film/Serie indipendenti
- [x] Filtri e categorie TV: pannello a scomparsa e percorsi strumenti/pannello/griglia testati; Preferiti con controlli espliciti
- [ ] Compilazione APK completa con Dart ^3.13.5 e video_player ^2.14.0 (SDK locale meno recente; da verificare in Codemagic)

- [x] Aggiornamento playlist non blocca il player (applicato alla chiusura)
- [x] Cronologia: un solo episodio per serie
- [x] Rilascio C: pausa/riavvolgimento diretta + LIVE (motore MPV)
- [x] Nomi locandine TV interi dentro la cornice
- [ ] Build Codemagic e prova sul televisore (in attesa dell'utente)
- [x] Rilascio D: registrazioni (ora dal player, programmate dalla guida)
- [x] Design Apple fase 1: colori, caratteri, pulsanti, focus stile Apple TV
- [x] Design Apple fase 2: uniformate schermate e controlli condivisi in StellarTV (commit c5a08113)
- [x] 43 test locali superati, player 960×540/1280×720 senza debordamenti
- [ ] Avvio completo con dipendenze originali: SDK locale non supporta le API video_player richieste
- [ ] Test completi su TV con telecomando (serve build Codemagic + prova dell'utente)
- [x] Login TV: selezione iniziale sul primo campo in alto (Email / Server)
- [x] Accesso ospite senza account

- [x] Ottobre 18: sezione privata Log errori sul sito, lettura/copia/download e rifiuto accesso altrui verificati; diagnostica app integrata su GitHub (73c923a), 5 test passati con SDK adattato.
- [ ] Ottobre 18: compilazione diagnostica con dipendenze originali e prova dispositivi reali (serve prossima build autorizzata e hardware).
- [x] Ottobre 18: build Android 3.2.2 (run 27, commit 6711e447) integrata e pubblicata; loghi titoli solo in italiano/inglese, /apk reindirizza a v3.2.2.
- [ ] Ottobre 18: prova 3.2.2 su dispositivi reali (Fire TV, Google TV, Chromecast, iPhone, Android) per dirette, diagnostica e loghi.

## Sincronizzazione cifrata — integrazione finale
- [x] Integrare formato cifrato condiviso, rimozioni preferiti e lettura legacy paginata nel sito; pulizia legacy disabilitata
- [x] App integrata su main di StellarTV (ec515655), senza avviare build o pubblicazione
- [x] Sito autenticato: Dati cifrati raggiungibile e conferma chiave verificata senza scrivere dati reali; 24 test sito e 27 Flutter isolati superati
- [ ] Verificare compilazione completa e dispositivi reali (richiede futura build autorizzata e hardware)
- [ ] Migrare dati reali con chiave privata dell’utente (richiede autorizzazione dalla schermata Dati cifrati; nessuna eliminazione automatica)
- [x] Sito companion: Home unica con account, download APK/IPA, codice Downloader; /apk e /ipa pubblici
- [x] Repo pubblica StellarTV-releases: tenere solo l'ultima release, eliminare le vecchie

## Ottobre 18 sera
- [x] Logo app identico a "E finale" (colori, nitidezza)
- [x] Animazione avvio più lunga
- [x] Import chiave TV: errore finale nonostante dati parzialmente applicati
- [x] Home: serie in corso mancanti, film nella riga sbagliata
- [x] Pannello QR chiave compatto
- [x] Credenziali Xtream da telefono (login e impostazioni)
- [x] "Invia cloud" fallisce
- [x] User agent predefinito per le dirette
- [ ] Prova 3.2.8 su TV (serve l'utente)
- [x] Nomi ovunque 'Film' e 'Serie TV' (no Raccolte/Video)
- [x] Indietro dopo il trailer deve tornare all'app

## Ottobre 18 notte — dirette e logo E orbitale v2
- [x] Dirette: rivedere da capo la pipeline live dei player (log 3.2.11)
- [x] Logo: 4 SVG (intero, stella, STELLAR, TV) dal logo del sito, lettere proporzionate
- [x] Logo nel sito (header, favicon, immagini)
- [x] Logo nell'app: widget, avvio, icone Android/iOS/Fire TV/Google TV, banner TV, schermate chiavette
- [x] Trailer: telecomando non può avviare il video né premere "Apri in YouTube"
- [x] Invio al cloud dalla TV fallisce sempre (eventuale azzeramento dati cloud)
- [x] Home: locandine verticali ovunque tranne le due righe visti di recente; Top con numero esterno come prima
- [x] Scheda Cerca: ridisegno in linea con il resto dell'app (TV + telefono)
- [x] Build 3.3.0 (run 37) riuscita: APK pubblicato, /apk e codice Downloader puntano a v3.3.0. Resta la prova sulla TCL dell'utente.

- [x] Telecomando TV, tasti destra/sinistra durante riproduzione: seek senza aprire comandi player; test telecomando.

- [x] Preferenze Home/UI condivise nella sync; esclusione player e codec da raccolta/ripristino, 13 test sito passati.

## Sottotitoli
- [x] Corrette selezione anno/episodio, ZIP stagionali, sovrapposizioni, aggiornamento dopo seek e scelta sorgente tra player; regolazione Exo online e alternative col telecomando. 21 prove Flutter superate, nessun errore/warning analisi. Nessuna APK avviata.
- [x] Correzioni app salvate e verificate su GitHub (58bdbf321296); 11 prove servizio superate, inclusi ZIP reale e versione alternativa; sito senza errori.
- [ ] Pubblicare il servizio sottotitoli aggiornato: richiede richiesta esplicita dell’utente.
- [ ] Prova su contenuti e TV reali con 3.3.2: richiede installazione dell’utente.

## Build 3.3.2 — 18 ottobre 2026
- [x] Build Android 3.3.2 riuscita (run 39): tutti i test Flutter e Android previsti superati, APK da 110 MB pubblicato.
- [x] Note di rilascio riscritte in modo comprensibile e applicate a entrambe le pubblicazioni.
- [x] /apk del sito reindirizza a v3.3.2 verificato sul sito live; nel repository pubblico resta solo l'ultima versione.
- [ ] Servizio sottotitoli del sito da pubblicare: la versione live è precedente, serve richiesta esplicita dell'utente.
- [x] Preferiti: focus non si perde quando la scheda si svuota
- [x] Cronologia: schede Tutti/Film/Serie TV
- [x] Diretta: rimuovere singolo canale e svuotare "Visti di recente"
- [x] Guida Diretta: orari al posto di Ora/A seguire/Poi, riga selezionata scorrevole con tutti i programmi
- [x] Build 3.3.3 (run 40) riuscita, APK pubblicato, /apk punta a v3.3.3, note riscritte
- [ ] Prova 3.3.3 su TV reale: serve l’utente

## Build 3.3.4 — 19 ottobre 2026
- [x] Build Android 3.3.4 riuscita (run 41, commit 970774e): APK da 110 MB pubblicato su entrambe le pubblicazioni, nel repository pubblico resta solo l’ultima versione.
- [x] Note di rilascio riscritte in modo comprensibile e applicate a entrambe le pubblicazioni.
- [x] /apk del sito reindirizza a v3.3.4 verificato sul sito live.
- [ ] Servizio sottotitoli del sito da pubblicare: la versione live è precedente, serve richiesta esplicita dell’utente.
- [ ] Prova 3.3.4 su TV reale: serve l’utente

## Categorie, piattaforme e disconnessioni — 19 ottobre 2026
- [x] Sito: stato disconnessione per dispositivo (in attesa / completata)
- [x] App: categorie personali e riordino categorie playlist in Impostazioni
- [x] App: pannello a scomparsa piattaforme (Netflix, Prime, Disney+, Apple TV+, Paramount+, HBO) in Film/Serie
- [x] App: Top 10 Disney+ in Home
- [ ] Prove Flutter e prova su TV: girano con la prossima build (GitHub 61bccc7); serve «Fai build»
- [x] App: sottotitoli più affidabili e sincronizzati
- [x] App: pulsante «Ricomincia da capo» in alto nel player
- [x] App: tenendo premuto destra/sinistra nei comandi player, avanti/indietro veloce come trascinare la barra
- [x] App: Impostazioni ridisegnate (Variante A, macro-categorie con icone)
- [x] App: pausa nelle Dirette che riparte da sola + pulsante Torna in diretta
- [ ] Prova su TV delle modifiche del commit 09bdf0a: serve la prossima build
- [ ] Applicare StellarTV-ottimizza-accessi.sql sul database esterno e confrontare CPU (utente)
- [ ] Nuova build app con correzione ciclo vault (commit 1d236bd), poi confronto CPU
- [ ] Guida generale e controlli dopo build 3.5.x (richiesto dall'utente)
- [x] Android 3.7.5: cataloghi immediati, Diretta prioritaria, diagnostica navigabile da TV
- [x] Pulizia automatica: ultimi 5 artifact e ultime 5 release a ogni build
- [x] Ottobre 23: filtri TV a quattro direzioni e Indietro sull’icona di apertura
- [x] Ottobre 23: Sinistra nelle Impostazioni torna alla categoria attiva
- [x] Ottobre 23: riuso locale di generi/piattaforme e guida EPG con aggiornamento coerente, diagnostica invariata
- [x] Ottobre 23: test, guida e note aggiornati; build Android seguita fino all’esito

- [ ] Prova Android 3.7.8 su TV: frecce rapide, ritorno alle icone/categorie, generi e guida al secondo avvio (serve dispositivo utente).
