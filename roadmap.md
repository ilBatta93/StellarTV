## Fluidità e metadati — 23 ottobre 2026
- [x] Rimossa scansione categorie dal disegno Home; indice locale asincrono per le schede e membership piattaforme per ID.
- [x] Banner limitato a 1280px normale/960px sotto pressione; diagnostica invariata.
- [x] Client invia sessione account per cache metadati opzionale; nessun prefetch massivo.
- [x] Android 3.7.14 run 39999271795 riuscita: test, compilazione, verifiche native e APK pubblico completati.
- [ ] Cache condivisa: SQL manuale esterno e pubblicazione sito necessari.
- [ ] Misura sul televisore reale: richiede dispositivo utente.

- [x] Ottobre 16 (2): dirette stabili — un solo player alla volta, formati del canale provati prima di cambiare motore, ExoPlayer predefinito per Dirette TV e anteprima/MultiView, MPV senza ricerca forzata, MDK sicuro e impostazioni per motore
- [ ] Ottobre 16 (2): prova su Fire TV, Google TV e Chromecast (serve build Codemagic)
- [x] Ottobre 16: MPV dirette (codec FFmpeg completi, decodifica sicura anti schermo nero, buffer Fire TV), terzo motore MDK, Diretta senza chiusure, icone→canali, MultiView nel player, lista episodi Apple con progresso e Back a due livelli
- [ ] Ottobre 16: prova su TV reale di MPV/MDK (serve build Codemagic)

# Roadmap

- [x] Promemoria scadenza Xtream, sync cloud istantanea, cache voti condivisa, cache immagini unica, filtri memorizzati

- [x] Profilo Bambino: generi rigorosi, rating, cache aggiornata e tutte le sezioni protette
- [x] Test regressione Bambino: 18 test Flutter e 5 test policy cloud superati
- [x] Analisi dei file modificati pulita, salvo API ScrollCacheExtent già presente e non supportata dall’SDK locale
- [ ] Build Codemagic con SDK richiesto e verifica catalogo Bambino su dispositivo

- [x] Rinominare app e riferimenti visivi in StellarTV su tutte le piattaforme
- [x] Integrare logo, logo testuale e icone app
- [x] Mostrare il totale contenuti allineato a destra nelle categorie Film e Serie
- [x] Correggere i filtri per genere nel tab Serie TV
- [x] Rendere più robusta la riproduzione live per l’errore HTTP 458
- [x] Formattare e verificare le modifiche (analisi completa demandata alla build Flutter/Codemagic)
- [x] Ridisegnare marchio e wordmark in codice e integrarli nell’interfaccia
- [x] Applicare la nuova palette e i font Sora/Manrope
- [x] Mostrare subito il catalogo salvato durante l’aggiornamento all’avvio
- [x] Aggiungere i titoli simili disponibili nella scheda delle serie
- [x] Salvare le modifiche nella repository GitHub
- [x] Ridurre proporzioni TV e correggere banner Home e righe Top
- [x] Aggiornare il banner anche da Continua a guardare
- [x] Aprire categorie con sinistra e chiuderle con destra ripristinando il focus
- [x] Rendere visibile il focus nelle schede e raggiungibili i controlli player
- [x] Verificare analisi Dart e test focus TV/touch (build APK da verificare in Codemagic)

- [x] Mostrare stati indipendenti Diretta/Film/Serie su mobile e TV
- [x] Verificare aggiornamento progressivo, errori/cache e navigazione invariata
- [x] Salvare gli indicatori nella repository GitHub

- [x] Banner Home TV a tutto schermo
- [x] Scaricamento playlist in background a flusso, tollerante a liste grandi/troncate, con progresso reale
- [x] Copia salvata separata per Diretta/Film/Serie
- [x] Riprova per singola sezione su mobile e TV (schermata sezione, barra copia salvata, Impostazioni)
- [x] Test scaricamento, riprova singola e analisi Dart
- [ ] Verifica APK su dispositivo (Codemagic)

- [x] Cataloghi TV: ricerca a scomparsa e ordinamento nella categoria
- [x] Cataloghi TV: ritorno alla barra superiore e voti locandine
- [x] Scheda attore TV coerente con schede titolo

- [x] TV: doppio Indietro durante una serie ritorna alla scheda titolo anche da Home/cronologia
- [x] TV Film/Serie: icona generi e pannello senza categorie playlist; Indietro ripristina l’icona
- [x] TV ricerca cataloghi: primo Indietro chiude tastiera, secondo chiude barra e ripristina lente
- [x] TV impostazioni player: opzioni filtrate per motore scelto, impostazioni touch invariate
- [x] TV locandine: titoli con margini interni laterali e inferiori
- [x] 22 test selezionati superati con Flutter 3.38.3/Dart 3.10.1 su copia di verifica
- [ ] Build completa con SDK richiesto e verifica telecomando su TV reale

- [x] Ordine sezioni navigabile col telecomando (OK prende, Su/Giù sposta, OK/Back conferma)
- [x] Rilascio B: download offline di film ed episodi (file diretti non protetti)
- [ ] Rilascio C: timeshift e pulsante LIVE
- [ ] Rilascio D: registrazioni

## Schermate e preferenze ottobre
- [x] Modifiche preparate nella copia di verifica: episodi orizzontali, pannello episodi nel player, reazioni per profilo, 100 ultimi aggiunti, selettori Top e Diretta con EPG/anteprima
- [x] 29 test selezionati superati nella copia con Flutter locale e dipendenze adattate solo per verifica
- [x] Repository di destinazione confermata dall’utente: ilBatta93/StellarTV, main
- [x] Modifiche salvate su main di StellarTV nel commit 5d0bf717
- [ ] Build con SDK e dipendenze originali: analisi locale bloccata dalle API video_player non disponibili nella versione di verifica
- [ ] Verificare pannello player, preview EPG, cloud e tutte le nuove schermate con account/provider e telecomando su TV reale
- [ ] Completare le restanti schermate del rifacimento Apple dopo verifica delle modifiche preparate

## Diretta e MultiView
- [x] Titoli TV adattati senza ellissi e intestazioni Home rivelate al focus
- [x] Diretta compatta con guida, anteprima sonora, preferiti e accesso MultiView
- [x] Banner Home iniziale dall’ultima visione idonea
- [x] MultiView fino a quattro canali, disposizioni sincronizzate e audio esclusivo
- [x] Contenimento memoria e buffer MPV Fire TV applicato (prestazioni hardware non verificate)
- [x] 10 test mirati Home/Diretta/MultiView superati a 960×540 e 1280×720
- [x] Regressione locale: 53 test superati; test splash preesistente bloccato da inizializzazione cloud assente nel test
- [ ] Build Codemagic con SDK e dipendenze originali (ambiente locale non compatibile)
- [ ] Prova reale di audio, provider multi-connessione, MPV Fire TV e telecomando (serve dispositivo/account dell’utente)

## Rifinitura Home e Diretta TV
- [x] Banner Home TV con solo titolo, senza trama o metadati
- [x] Loghi canali disponibili nella guida e anteprima, separatori e selezione coerenti
- [x] Risalita da primo canale, EPG e anteprima a strumenti e menu principale
- [x] Test con menu HomeScreen reale, ritorno alla guida e controlli a 960×540/1280×720
- [ ] Verifica finale dell’APK con provider e telecomando su televisore reale

## Ottobre 17 — integrazione e APK 3.2.1
- [x] Integrare schede film/serie, trailer ITA/ENG ed episodi/Top con navigazione telecomando approvati
- [x] Placeholder logo senza titolo transitorio, rimuovere attesa splash fissa e condividere refresh Discovery
- [x] Decoder fallback Android, timeline DVR nativa e recupero provider con isolamento cronologia
- [x] Protezione Kids applicata prima del catalogo e conservata offline
- [x] 37 test selezionati passati nella copia di verifica con SDK locale adattato
- [x] APK 3.2.1 pubblicato: build con dipendenze originali, test Flutter e test nativi DVR superati (run 26)
- [ ] Provare flussi reali e prestazioni su Fire TV/Google TV/Chromecast/Android/iOS (richiede dispositivi e provider dell'utente)

## Ottobre 18 — correzioni dirette
- [x] Valutare proposte allegate senza eliminare MultiView, DVR o impostazioni provider
- [x] Rendering reale anziché dimensioni, rilascio completo prima del cambio player, fallback anteprima e memoria software dopo successo
- [x] 19 test mirati Flutter superati su copia con dipendenze adattate; API contatori Media3 1.9.2 verificate nel sorgente ufficiale
- [ ] Test nativo primo fotogramma e compilazione con dipendenze originali (richiedono ambiente Android CI; nessuna nuova build richiesta)
- [ ] Flussi provider e tutte le piattaforme su dispositivi reali (richiedono hardware/provider dell'utente)

- [x] Ottobre 18: diagnostica dirette opzionale locale, piattaforma/dispositivo, avvio, blocchi/errori e esportazione su telefono/TV; 5 test superati nella copia con SDK adattato, nessuna APK avviata.
- [x] Ottobre 18: invio manuale autenticato e Log errori privati sul sito; lettura/copia/download e rifiuto proprietario diverso verificati nel browser.
- [ ] Ottobre 18: verifica diagnostica su dispositivi reali e compilazione con dipendenze originali (richiede prossima build e hardware; build non richiesta).

- [x] Ottobre 18: logo E orbitale v2 approvato, tre SVG editabili, brand app e icone aggiornati senza avviare APK.

## Protezione dati e sincronizzazione cifrata
- [x] Proseguimento: operazioni simultanee/importazioni preferiti corrette, uscita account protetta, 27 test Flutter isolati e 24 sito superati
- [x] Copia locale: chiave separata, cifratura account-bound, revisioni e verifica lettura senza cancellare copie precedenti
- [x] Copia locale: rimozioni preferiti persistenti, isolamento account, accesso telecomando e blocco backup automatici; 21 test isolati Flutter e 10 web superati
- [ ] Integrare app e sito su nuova richiesta dell’utente: prepararli per pubblicazione e build, senza avviarle
- [ ] Verifica completa con SDK originale e dispositivi Android/iOS (richiede integrazione e ambiente compatibile)
- [x] Testi visibili dell’app e nuove note di release neutri; identificatori tecnici invariati per compatibilità
- [ ] Aggiornamenti storici GitHub (intervento separato sulle vecchie release; non riscrivere la cronologia Git)
- [ ] Migrare e verificare dati reali con chiave privata dell’utente (nessuna scrittura reale né pulizia eseguita)

## Dirette ottobre 18 (sera)
- [x] Analisi log 3.3.0 e correzione schermi neri: MPEG-TS prima di HLS, controllo prima immagine, 503 gestito, HLS preparato dai segmenti reali
- [x] "Visti di recente" della Diretta popolato (lista locale dei canali aperti)
- [x] Player diretta: freccia sinistra senza comandi apre elenco canali trasparente (categorie + canali), telecomando, Indietro chiude, riproduzione continua
- [x] Build 3.3.1 pubblicata su GitHub Releases (run 38, commit 868f99a)
- [ ] Verifica su TCL dei canali [VS], elenco canali, Home ridimensionata e invio cloud (richiede installazione 3.3.1 e log dell'utente)

## Personalizzazione Home e UI
- [x] Preferenze Home: forma, densità, quantità consigliati/recenti, banner e scala UI con limiti sicuri.
- [x] Sync immediata delle preferenze comuni; player e compatibilità solo locali anche nel ripristino.
- [x] Test di regole, persistenza, geometria e navigazione: 32 Flutter + 13 sito superati; analisi senza errori/warning, lock originale preservato.

- [x] Telecomando TV, tasti destra/sinistra durante riproduzione: seek senza aprire comandi player; test telecomando.

- [x] Build 3.3.2 (run 39, commit 58bdbf3) pubblicata su GitHub Releases e nel repository pubblico.
- [ ] Prova su TV/telefono e sync tra dispositivi reali: richiede installazione 3.3.2 e dispositivi dell’utente.

## Sottotitoli
- [x] Corrette selezione anno/episodio, ZIP stagionali, sovrapposizioni, aggiornamento dopo seek e scelta sorgente tra player; regolazione Exo online e alternative col telecomando. 21 prove Flutter superate, nessun errore/warning analisi. Nessuna APK avviata.
- [x] Correzioni app pronte per GitHub; 11 prove servizio superate, inclusi ZIP reale e versione alternativa; sito senza errori.
- [ ] Pubblicare il servizio sottotitoli aggiornato: richiede richiesta esplicita dell’utente.
- [ ] Prova su contenuti e TV reali con 3.3.2: richiede installazione dell’utente.

## Build 3.3.2 — 18 ottobre 2026
- [x] Build Android 3.3.2 riuscita (run 39): tutti i test Flutter e Android previsti superati, APK da 110 MB pubblicato.
- [x] Note di rilascio riscritte in modo comprensibile e applicate a entrambe le pubblicazioni.
- [x] /apk del sito reindirizza a v3.3.2 verificato sul sito live; nel repository pubblico resta solo l'ultima versione.
- [ ] Servizio sottotitoli del sito da pubblicare: la versione live è precedente, serve richiesta esplicita dell'utente.

## Film recenti e completamento 95% — 18 ottobre 2026
- [x] Soglia visto regolabile nelle impostazioni, iniziale 95%, sincronizzata tra dispositivi.
- [x] Schede film e serie: minuti rimanenti nel pulsante Guarda ora per contenuti già avviati.
- [x] Minuti rimanenti a destra dei film recenti, con lo stesso layout di stagione/episodio.
- [x] Regola condivisa di completamento dal 95% per film ed episodi, con test e verifica GitHub.
- [ ] Prova su TV reale: richiede nuova APK autorizzata e dispositivo dell’utente.

## 23 ottobre — caricamento e guida
- [x] Guida progressiva in worker cancellabile, errori classificati, gzip/redirect e copia precedente conservata.
- [x] Pubblicazione cataloghi cooperativa con controlli account/profilo, salvataggi seriali e precedenza aggiornamento alla guida.
- [x] Dieci prove mirate Dart superate su sorgenti reali; analisi dei nuovi moduli pulita; protezioni foreground/anteprima verificate.
- [x] Note pubbliche neutre e guida allineata.
- [ ] Test integrati Flutter e misura su TV: SDK locale 3.38.3 non soddisfa il vincolo 3.44.0; nessuna build richiesta.

## Ottobre 23 — focus e cache locali
- [x] Filtri quattro direzioni, ritorno icona e Sinistra alla categoria attiva
- [x] Conteggi generi persistiti, caricamento evidenze deduplicato e EPG permanente per fonte
- [x] Diagnostica invariata, guida e note neutre aggiornate
- [x] Android 3.7.8 pubblicata: 251 test passati, 2 saltati; test nativi e APK riusciti
- [ ] Prova focus, generi e guida tra avvii su TV reale (serve dispositivo utente)

## Voti ed episodi — 23 ottobre sera
- [x] IMDb nei cataloghi e schede; trama/voto individuale episodio e pannello Su locale.
- [x] Guida, note neutrali e test aggiornati; workflow serie 3.8 esplicito.
- [x] Android 3.8.2 run 40038787549 riuscita: test, APK e verifiche native; correzione test focus nel primo tentativo.
- [ ] Prova reale su TV e servizio pubblicato: richiedono utente.
