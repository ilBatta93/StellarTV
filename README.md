<div align="center">

# ✦ STELLAR TV

### Il tuo universo di Diretta, Film e Serie TV — su TV, telefono e tablet.

**Android TV · Google TV · Fire TV · Chromecast · Android · iPhone · iPad**

![Versione](https://img.shields.io/badge/versione-3.1-FF9500?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Android](https://img.shields.io/badge/Android%20%2F%20TV-supportato-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-supportato-000000?style=for-the-badge&logo=apple&logoColor=white)
![Lingua](https://img.shields.io/badge/lingua-italiano-1C1C1E?style=for-the-badge)

</div>

---

> **StellarTV** è un lettore IPTV in stile Apple: unisce la tua playlist **M3U** o il tuo account **Xtream Codes** con locandine, trame, cast e classifiche di **TMDB**, una **Guida TV (EPG)** completa, il **MultiView**, i **download offline**, i **profili** (anche **Bambino** con filtro rigoroso) e la **sincronizzazione cloud istantanea** fra tutti i tuoi dispositivi.
>
> StellarTV **non fornisce contenuti**: riproduce soltanto le playlist e gli abbonamenti che possiedi già.

---

## 📑 Indice

1. [Panoramica rapida](#-panoramica-rapida)
2. [Installazione e aggiornamenti](#-installazione-e-aggiornamenti)
3. [Primo avvio: account, ospite e playlist](#-primo-avvio-account-ospite-e-playlist)
4. [Profili e profilo Bambino](#-profili-e-profilo-bambino)
5. [Navigazione generale](#-navigazione-generale)
6. [Home](#-home)
7. [Diretta TV](#-diretta-tv)
8. [Guida TV (EPG)](#-guida-tv-epg)
9. [Film e Serie TV](#-film-e-serie-tv)
10. [Schede titolo, attori ed episodi](#-schede-titolo-attori-ed-episodi)
11. [Ricerca, Preferiti e Visti di recente](#-ricerca-preferiti-e-visti-di-recente)
12. [Il Player](#-il-player)
13. [Motori di riproduzione](#-motori-di-riproduzione-mpv-exoplayer-mdk)
14. [MultiView](#-multiview)
15. [Download offline](#-download-offline)
16. [Impostazioni (guida voce per voce)](#-impostazioni-guida-voce-per-voce)
17. [Sincronizzazione cloud](#-sincronizzazione-cloud)
18. [Telecomando: mappa completa dei tasti](#-telecomando-mappa-completa-dei-tasti)
19. [Gesti su telefono e tablet](#-gesti-su-telefono-e-tablet)
20. [Risoluzione dei problemi](#-risoluzione-dei-problemi)
21. [Privacy e sicurezza](#-privacy-e-sicurezza)
22. [Per sviluppatori](#-per-sviluppatori)

---

## ✨ Panoramica rapida

| Area | Cosa offre |
|---|---|
| 📺 **Diretta** | Lista canali compatta con loghi, anteprima con audio, EPG integrata, canale precedente/successivo, categorie, preferiti, *Visti di recente* |
| 🎬 **Film & Serie** | Cataloghi arricchiti TMDB, 5 disposizioni (griglia, compatta, lista…), filtri per genere, ordinamenti, *Ultimi aggiunti*, *Visti di recente* |
| 🏠 **Home** | Banner dell'ultima visione, *Continua a guardare* (fino a 50 titoli), Top 10, Top per piattaforma, consigli personalizzati |
| ▶️ **Player** | MPV (predefinito per le dirette), ExoPlayer, MDK; tracce audio/sottotitoli, sottotitoli online, velocità, formato, prossimo episodio, salto intro |
| 🧩 **MultiView** | Più canali in riproduzione contemporanea, audio sul riquadro selezionato, selettore canali stile Apple |
| ⬇️ **Offline** | Download di film ed episodi non protetti, coda, pausa/ripresa, spazio occupato |
| 👨‍👩‍👧 **Profili** | Più profili per account, profilo Bambino con PIN e filtro contenuti rigoroso |
| ☁️ **Cloud** | Cronologia, preferiti, reazioni e impostazioni sincronizzati **a ogni azione** |
| 🎨 **Aspetto** | Design Apple (tvOS su TV, iOS su telefono), accento arancione, palette e bagliore personalizzabili |

---

## 📦 Installazione e aggiornamenti

### Android, Google TV, Fire TV, Chromecast
1. Scarica l'ultimo `StellarTV-v3.1.x.apk` dalla pagina **Releases** di [`ilBatta93/StellarTV-releases`](https://github.com/ilBatta93/StellarTV-releases/releases).
2. Su TV puoi usare app come *Downloader* inserendo il link diretto dell'APK.
3. Consenti l'installazione da **origini sconosciute** quando richiesto.
4. Apri l'APK e conferma l'installazione.

### iPhone e iPad
Viene pubblicato un file `.ipa` **non firmato**: va installato con uno strumento di firma personale (es. AltStore, Sideloadly o un certificato sviluppatore).

### Aggiornamento integrato ⟳
- **Impostazioni → Informazioni → Verifica aggiornamenti** controlla se esiste una nuova versione.
- Se disponibile, StellarTV **scarica e installa** l'APK direttamente dall'app; le tue impostazioni restano intatte (la firma dell'app è stabile fra le versioni).
- Ogni release riporta le **note di rilascio complete** di tutte le modifiche dalla build precedente.

### Numerazione
Dalla release **3.1.0** le versioni seguono lo schema `3.1.N`, dove `N` cresce a ogni nuova build.

---

## 🚀 Primo avvio: account, ospite e playlist

### 1. Account StellarTV (consigliato)
- Registrati con **email e password**. Riceverai una mail di **conferma**: finché non la confermi l'accesso non è attivo (su TV compare un avviso e puoi **reinviare la conferma**).
- L'account serve a sincronizzare cronologia, preferiti, profili e impostazioni fra tutti i dispositivi.

### 2. Continua come ospite
- Dalla schermata iniziale scegli **Continua come ospite**: l'app funziona completamente, ma i dati restano **solo su quel dispositivo**.
- Puoi creare o collegare un account in qualsiasi momento da **Impostazioni → Account**.

### 3. Aggiungi la playlist
| Metodo | Cosa inserire |
|---|---|
| **Xtream Codes** | Server (es. `http://provider.tld:8080`), nome utente, password |
| **M3U da URL** | Link completo della playlist `.m3u` / `.m3u8` |
| **M3U da file** | File locale sul dispositivo |

- Su TV il cursore parte dal **primo campo in alto** (Email / Server) per inserire i dati rapidamente col telecomando.
- La playlist viene salvata sul dispositivo: agli avvii successivi l'app apre **subito la copia locale** e la aggiorna solo all'intervallo scelto.
- Indicatori discreti mostrano separatamente il caricamento di **Diretta**, **Film** e **Serie TV**.

---

## 👨‍👩‍👧 Profili e profilo Bambino

- **Impostazioni → Profili → Gestisci profili**: crea, rinomina, scegli colore/iniziale ed elimina i profili.
- Ogni profilo ha la propria **cronologia**, **Continua a guardare**, **preferiti**, **Mi piace / Non mi piace** e consigli.

### Profilo Bambino 🧸
- Protetto da **PIN** per entrare e uscire.
- **Filtro rigoroso** applicato ovunque (Home, cataloghi, ricerca, Diretta, consigli, cronologia):
  - solo generi adatti (animazione, famiglia, ecc.) e classificazioni per l'età verificate su TMDB;
  - esclusione di horror, thriller, contenuti adulti e categorie sensibili;
  - **fail-safe**: se un titolo non può essere verificato, **non viene mostrato**.
- I controlli vengono eseguiti in background e memorizzati nel cloud, così i successivi avvii sono istantanei.

### Contenuti per adulti
- **Impostazioni → Cataloghi → Mostra contenuti per adulti**: disattivato di default; mai visibile nel profilo Bambino.

---

## 🧭 Navigazione generale

StellarTV adatta l'interfaccia al dispositivo:

| Dispositivo | Stile | Navigazione |
|---|---|---|
| **TV** (Android TV, Google TV, Fire TV, Chromecast) | tvOS | Barra superiore: **Home · Diretta · Film · Serie TV · Preferiti · Cerca · Impostazioni** + iniziale del profilo |
| **Telefono / tablet** | iOS | Barra a schede in basso |

- L'**ordine delle sezioni** e la **sezione di avvio** si scelgono in **Impostazioni → Navigazione → Ordine e sezione iniziale**.
- Su TV ogni elemento selezionato è evidenziato da un **bagliore** ben visibile da lontano.
- **Ogni funzione è raggiungibile col telecomando** (frecce, OK, Indietro).

---

## 🏠 Home

- **Banner principale**: l'ultimo titolo che stavi guardando, con solo il titolo (niente trama) e il pulsante per riprendere.
- **Continua a guardare**: film ed episodi iniziati, ordinati dal più recente, **fino a 50 titoli** per riga. Per le serie compare un solo episodio (l'ultimo) per serie.
- **Ultimi aggiunti**: gli ultimi **100 film** e **100 serie** arrivati nella tua playlist.
- **Top 10 della settimana** e **Top per piattaforma** (Netflix, Prime Video, Disney+, Apple TV+, HBO Max, Paramount+…) — solo titoli presenti nella tua playlist.
- **Consigliati per te**: basati su cosa guardi e su Mi piace / Non mi piace.
- Su TV le righe **restano nella stessa riga**: arrivato all'ultima locandina a destra (o alla prima a sinistra) il cursore si ferma, non salta alla riga sotto. Si cambia riga solo con ⬆️ / ⬇️.

---

## 📺 Diretta TV

- **Categorie** del provider in un pannello laterale (su TV si apre con ⬅️ dalla prima colonna o dalla barra strumenti).
- **Lista canali compatta** con loghi, numero e programma in onda.
- **Anteprima**: selezionando un canale parte una piccola anteprima **con audio**; premi **OK** per lo schermo intero.
- **EPG integrata**: programma attuale e successivo con barra di avanzamento.
- **Visti di recente**: categoria speciale con gli ultimi **100 canali** guardati, in ordine cronologico.
- **Preferiti**: aggiungi/rimuovi canali col cuore; compaiono nella pagina Preferiti.
- **Ricerca** canali sull'intera lista.
- **Categorie nascoste**: nascondi gruppi che non ti interessano (Impostazioni → Cataloghi).
- Pulsante **MultiView** direttamente dal player della diretta.

---

## 🗓 Guida TV (EPG)

- Fonte EPG automatica dal provider Xtream o URL **XMLTV** personalizzato (**Impostazioni → Guida TV**).
- Aggiornamento automatico (predefinito ogni 12 ore) e aggiornamento manuale.
- Nel player della diretta un pannello mostra **programma corrente, successivi e orari**.

---

## 🎬 Film e Serie TV

- Cataloghi arricchiti con **TMDB**: locandine HD, sfondi, trama, generi, anno, durata, voto.
- **Disposizioni**: griglia, compatta, lista e altre varianti moderne (5 in totale) — selettore nella barra strumenti o in **Impostazioni → Aspetto → Disposizione delle schede**.
- **Categorie speciali**:
  - *Visti di recente* — fino a **100 titoli** visti o iniziati, in ordine cronologico (per le serie, la serie intera);
  - *Ultimi aggiunti*, *Tutti i film*, *Tutte le serie*;
  - categorie del provider.
- **Filtri** per genere (pannello a scomparsa) e **ordinamenti**: provider, titolo A→Z, anno, voto, aggiunti di recente.
- **Ricerca a scomparsa** nella categoria aperta; cancellabile, si chiude scendendo verso la griglia.
- **Voti** e **etichette qualità** (4K, FHD, HD) sulle locandine (attivabili nelle impostazioni).
- Titoli duplicati con lo stesso nome vengono **raggruppati** automaticamente.

---

## 🧾 Schede titolo, attori ed episodi

### Scheda film / serie
- Sfondo grande stabile, locandina, trama, cast, generi, voto, durata.
- **Guarda ora** / **Riprendi da mm:ss** / **Ricomincia**.
- **Mi piace / Non mi piace** 👍👎 (per profilo, influenzano i consigli).
- **Preferiti** ❤️, **Scarica** ⬇️ (se il contenuto lo consente), **Titoli simili**.
- Su TV la scheda è posizionata in alto per vedere subito i comandi; con ⬆️ si torna sempre a *Guarda ora*.

### Serie TV
- Selettore **stagioni** e **episodi orizzontali** con immagine, titolo, durata, progresso e spunta *visto* (al 95%).
- Dall'episodio con ⬆️ si torna alle stagioni e poi ai pulsanti principali.

### Scheda attore
- Foto, biografia e filmografia filtrata sui titoli **presenti nella tua playlist**.

---

## 🔎 Ricerca, Preferiti e Visti di recente

- **Cerca** (barra superiore su TV, scheda su mobile): cerca contemporaneamente in canali, film e serie, con risultati suddivisi.
- **Preferiti**: canali, film e serie salvati, sincronizzati nel cloud.
- **Cronologia**: **Impostazioni → Cronologia** per consultarla o cancellarla.

---

## ▶️ Il Player

### Comandi principali
| Funzione | Descrizione |
|---|---|
| ⏯ Play / Pausa | Anche sulle dirette compatibili (timeshift) |
| ⏪ ⏩ Salto | Avanti/indietro del passo scelto (predefinito 10 s) |
| 🔊 Tracce audio | Scelta lingua/traccia, preferita `it` |
| 💬 Sottotitoli | Tracce interne + **ricerca online in italiano** con fallback automatico; dimensione, colore, sfondo, grassetto, ritardo |
| ⏱ Sincronia | Ritardo audio e sottotitoli regolabile |
| 🐢 Velocità | 0.5× → 2× |
| 🖼 Formato | Adatta, Riempi, Allunga, 16:9, 4:3… |
| ⏭ Prossimo episodio | Avvio automatico a fine episodio, con conto alla rovescia |
| ⤼ Salta intro | Quando l'intro della serie è nota |
| 📋 Episodi | Pannello laterale stagioni/episodi con progresso, senza uscire dal player |
| 📊 Statistiche | Codec, risoluzione, fps, buffer (opzionale) |
| 🖼 PiP | Picture-in-Picture automatico su mobile |
| ⏮ ⏭ Canale | Canale precedente/successivo nella diretta |
| 🧩 MultiView | Dalla diretta, apre il MultiView col canale corrente |

### Ripresa e cronologia
- Ogni film/episodio riparte **dal punto salvato**; al 95% viene marcato come *visto*.
- I progressi vengono sincronizzati **immediatamente** nel cloud.

### Uscita dal player
- Su TV il **primo Indietro** nasconde i controlli, il **secondo** esce.

---

## ⚙️ Motori di riproduzione (MPV, ExoPlayer, MDK)

| Motore | Uso consigliato |
|---|---|
| **MPV (media_kit)** | **Predefinito per la Diretta**. Gestisce MPEG-TS/HLS, timeshift, formati difficili |
| **ExoPlayer** | Film e Serie, anteprime e riquadri MultiView; molto leggero |
| **MDK (fvp)** | Alternativa aggiuntiva per flussi particolari |

- Impostazioni indipendenti per **Dirette TV** e **Film/Serie** (**Impostazioni → Player video**).
- **Fallback automatico**: se un motore non parte entro il tempo massimo (predefinito 12 s), si passa al successivo.
- **Protezione schermo nero**: StellarTV controlla che arrivino **fotogrammi reali**. Se c'è solo audio, il canale riparte in **decodifica software**; il canale viene ricordato e la volta dopo si apre direttamente nel modo giusto (anche in anteprima).
- Decodifica hardware solo per i codec che il chip disegna davvero (H.264, HEVC, VP9, AV1); MPEG-2 e VC-1 via software.

### Opzioni avanzate del Player video
Formato flusso diretta (Auto/TS/HLS) · Decodifica hardware (Auto/On/Off) · Cache rete e cache diretta · Buffer all'indietro · Riconnessione HTTP · Scarta fotogrammi in ritardo · Passthrough audio · Time-stretch audio · User-Agent · Lingua audio/sottotitoli preferita · Velocità predefinita · Formato immagine · Orientamento · Ripresa automatica · Passo di salto · Tempo di scomparsa controlli · Gesti · Doppio tocco per saltare · PiP automatico · Schermo sempre acceso · Audio in background · Statistiche.

---

## 🧩 MultiView

- Guarda **più canali contemporaneamente** (2, 3 o 4 riquadri, disposizioni in **Impostazioni → MultiView**).
- Tutti i riquadri restano **sempre in riproduzione**; l'**audio** viene solo dal riquadro selezionato.
- **Aggiungere un canale**: si apre un pannello laterale in stile Apple:
  - in alto le **categorie** della Diretta (predefinita *TV Sat* o la prima disponibile);
  - sotto una **griglia compatta** di canali con logo e nome;
  - ricerca su tutte le categorie.
- Su TV: frecce per spostarsi fra i riquadri, **OK** per renderlo attivo/aprire opzioni, **Indietro** dalla griglia torna alle categorie, un secondo **Indietro** chiude.

---

## ⬇️ Download offline

- Pulsante **Scarica** nelle schede film e negli episodi (solo per flussi non protetti che il provider rende scaricabili).
- **Impostazioni → Download**: coda, avanzamento, pausa/ripresa, annulla, spazio occupato, eliminazione.
- La riproduzione offline usa il player normale e aggiorna cronologia e punto di ripresa.
- I video restano **sul dispositivo**; nel cloud vanno solo i metadati leggeri.

---

## 🛠 Impostazioni (guida voce per voce)

### Account
| Voce | Funzione |
|---|---|
| **Account** | Email, stato sincronizzazione, uscita |
| **Account playlist** | Scadenza, stato, connessioni attive e dati del provider Xtream |
| **Promemoria scadenza** | Avvisi prima che l'abbonamento Xtream scada |
| **Metodo di connessione** | Xtream o M3U |
| **Disconnetti** | Rimuove la playlist dal dispositivo |

### Profili
**Gestisci profili** · PIN Bambino.

### Navigazione
**Ordine e sezione iniziale** — riordina Home, Diretta, Film e Serie TV (su TV con *Sposta su / Sposta giù*, su mobile trascinando) e scegli la sezione di avvio; *Ripristina ordine predefinito*.

### Aspetto
**Disposizione delle schede** · **Dimensione dei poster** · **Dimensione testo** (utile sulle TV lontane dal divano) · **Modalità compatta** · **Titoli sotto le locandine** · **Voti sulle locandine** · **Etichette qualità** · **Bagliore di selezione** (colore) · **Animazioni** · **Ripristina aspetto predefinito**.

### Cataloghi
**Categorie nascoste** · **Mostra anteprime** · **Mostra contenuti per adulti** · **Contenuti caricati** (riepilogo canali/film/serie).

### Aggiornamento playlist
**Aggiorna la playlist ogni…** (intervallo) · **Aggiorna tutto ora**. L'aggiornamento non interrompe mai la riproduzione: viene applicato alla chiusura del player.

### Guida TV
Fonte EPG, frequenza di aggiornamento, aggiornamento manuale.

### Riproduzione
**Player video** (vedi sopra) · **MultiView** · **Download**.

### Backup e sincronizzazione
Stato del cloud, sincronizzazione manuale, **Cronologia**.

### Informazioni
**Versione** · **Piattaforma** · **Verifica aggiornamenti**.

---

## ☁️ Sincronizzazione cloud

- Con un account, StellarTV sincronizza **a ogni singola azione** (mai in ritardo o a gruppi):
  cronologia e punti di ripresa · preferiti · Mi piace/Non mi piace · profili · impostazioni player, aspetto, disposizioni e ordine sezioni.
- I dati sono protetti: ogni utente accede **solo ai propri dati**.
- Le password della playlist non vengono mai mostrate in chiaro.

---

## 🎮 Telecomando: mappa completa dei tasti

### Ovunque
| Tasto | Azione |
|---|---|
| ⬆️ ⬇️ ⬅️ ➡️ | Sposta la selezione |
| **OK / Select** | Apre / conferma |
| **Indietro** | Torna al livello precedente (pannello → griglia → barra superiore → uscita) |
| **Menu / tasto lungo OK** | Opzioni contestuali, dove disponibili |

### Home e cataloghi
| Tasto | Azione |
|---|---|
| ⬅️ ➡️ in una riga | Scorre la riga; ai bordi **si ferma** |
| ⬆️ dalla prima riga | Torna alla barra superiore |
| ⬅️ dalla prima colonna | Apre il pannello categorie/filtri |
| ⬆️ dalla griglia | Strumenti: ricerca, ordinamento, disposizione, filtri |

### Diretta
| Tasto | Azione |
|---|---|
| ⬆️ ⬇️ | Canale precedente/successivo nella lista (anteprima con audio) |
| **OK** | Schermo intero |
| ⬅️ | Categorie |
| ➡️ | Guida EPG del canale |

### Player
| Tasto | Azione |
|---|---|
| **OK** | Mostra controlli / Play-Pausa |
| ⬅️ ➡️ | Salto indietro/avanti (Film/Serie) · timeshift (Diretta compatibile) |
| ⬆️ ⬇️ | Diretta: canale precedente/successivo · Film/Serie: barra comandi |
| **Play/Pausa, ⏪ ⏩** del telecomando | Supportati direttamente |
| **Indietro** (1°) | Nasconde i controlli / chiude pannelli (episodi → stagioni → player) |
| **Indietro** (2°) | Esce dal player |

### MultiView
| Tasto | Azione |
|---|---|
| Frecce | Cambia riquadro attivo (l'audio lo segue) |
| **OK** | Opzioni riquadro / aggiungi canale |
| **Indietro** | Griglia → categorie → chiudi selettore → esci |

---

## 👆 Gesti su telefono e tablet

| Gesto | Azione |
|---|---|
| Tocco | Mostra/nasconde i controlli |
| Doppio tocco a sinistra/destra | Indietro/avanti del passo scelto |
| Scorrimento orizzontale | Spostamento preciso (tutta la larghezza ≈ 90 s o 1/5 del titolo) |
| Scorrimento verticale a sinistra | Luminosità |
| Scorrimento verticale a destra | Volume |
| Pizzico | Cambia formato immagine |
| Home / chiusura app | Picture-in-Picture automatico |

---

## 🩺 Risoluzione dei problemi

| Problema | Soluzione |
|---|---|
| **Audio ma schermo nero** | Attendi qualche secondo: l'app riparte automaticamente in decodifica software e lo ricorda. In alternativa: Player video → Decodifica hardware *Off* |
| Canale che non parte | Player video → Formato flusso diretta *TS* o *HLS*; verifica le connessioni attive in *Account playlist* |
| Scatti su chiavette economiche | Riduci la cache, attiva *Scarta fotogrammi in ritardo*, prova ExoPlayer per Film/Serie |
| Catalogo non aggiornato | Impostazioni → *Aggiorna tutto ora* |
| EPG vuota | Impostazioni → Guida TV → aggiorna o imposta un URL XMLTV |
| Sottotitoli fuori sincrono | Player → Sottotitoli → Ritardo |
| Email non confermata | Controlla la posta (anche spam) e usa *Reinvia conferma* |
| Abbonamento scaduto | Impostazioni → Account playlist mostra la data di scadenza |

---

## 🔐 Privacy e sicurezza

- Nessun contenuto video passa dai server StellarTV: i flussi arrivano direttamente dal tuo provider.
- Il cloud conserva solo dati leggeri (cronologia, preferiti, impostazioni) con accesso limitato al proprietario.
- DRM e restrizioni del provider non vengono mai aggirati.

---

## 👩‍💻 Per sviluppatori

### Stack
Flutter · Provider · media_kit (mpv) · video_player (ExoPlayer/AVPlayer) · fvp (MDK) · Supabase · TMDB.

### Struttura
```text
lib/
├── config/      configurazione servizi cloud
├── models/      canali, categorie, EPG, cronologia, impostazioni player
├── navigation/  rotte
├── player/      motori mpv / Exo / MDK, sessione, memoria decoder, audio MultiView
├── providers/   stato app, cronologia, profili, EPG, sync, reazioni
├── screens/     Home, Diretta, Cataloghi, schede, player, MultiView, impostazioni
├── services/    Xtream/M3U, TMDB, EPG, cache, download, filtro Bambino, aggiornamenti
├── theme/       tema Apple (tvOS / iOS)
└── widgets/     card, righe, pannelli TV, controlli player
test/            test unitari e D-Pad
```

### Avvio locale
```sh
flutter pub get
flutter run            # dispositivo collegato
flutter test           # test
flutter analyze        # analisi statica
```

### Build e rilasci
- **Android**: workflow `StellarTV Android Release` (`.github/workflows/build.yml`), solo avvio manuale. Produce `StellarTV-v3.1.N.apk`, crea la release con le **note di tutti i commit dalla build precedente** e la pubblica anche su `StellarTV-releases`.
- **iOS**: workflow `build-ios.yml`, IPA non firmata aggiunta alla release indicata.

---

<div align="center">

**✦ StellarTV** — fatto con cura per il divano.

</div>
