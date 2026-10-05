# StellarTV

StellarTV è un'app IPTV per **Android** e **iOS**, sviluppata in Flutter, che combina le tue playlist M3U/Xtream con i metadati di TMDB (poster, trama, cast, stagioni ed episodi), la diretta con guida EPG, sottotitoli in italiano con sistema di fallback e la sincronizzazione cloud tra dispositivi.

- **Bundle Android:** `tv.stellar.app`
- **Lingua interfaccia:** italiano
- **Motore riproduzione predefinito:** MediaKit (mpv) — alternativo ExoPlayer

---

## Funzionalità

### Catalogo e contenuti
- Playlist **M3U** e account **Xtream Codes** (file locale o URL)
- Catalogo arricchito con TMDB: poster, trama, attori, generi, stagioni ed episodi nella stessa scheda
- Sezione **Scopri** con Top 10 settimanali e consigli personalizzati (dati TMDB)
- **Top 10 per piattaforma** (Netflix, Prime Video, Apple TV+, HBO Max, Paramount+) — solo titoli presenti nella tua playlist
- Categorie **"Ultimi Aggiunti"** (50 titoli, ordine cronologico), **"Tutti i Film"**, **"Tutte le Serie"** e filtro per genere
- Ricerca con debounce
- Titoli simili e consigli su film e serie
- Preferiti locali e nel cloud
- Duplicati con lo stesso titolo raggruppati automaticamente

### Diretta (Live)
- Guida **EPG** con aggiornamento automatico ogni 12 ore
- Pulsanti **canale precedente/successivo**
- Aggiornamento playlist automatico ogni 12 ore

### Riproduzione
- Due motori: **MediaKit (mpv)** e **ExoPlayer**
- Ripresa dal punto salvato (titolo marcato "visto" al 95%)
- **Prossimo episodio** automatico alla fine
- **Skip intro/outro** automatico (IntroDB, dove disponibile)
- Pulsante "Scheda titolo" direttamente nel player
- Gesture e statistiche del player

### Sottotitoli
- Tracce **incorporate** nel file video + sottotitoli **italiani online**
- Catena di fallback nel cloud: **Wyzie → SubDL → OpenSubtitles** (la quota dei provider gratuiti viene consumata il meno possibile)
- **Cache cloud condivisa**: un sottotitolo scaricato una volta è disponibile per tutti i dispositivi
- **Cache offline** sul dispositivo (funzionano anche senza rete)
- Dimensione, colore, sfondo, grassetto e **ritardo** regolabili
- Funzionano con **entrambi i motori** di riproduzione (overlay engine-agnostic)

### Profili e famiglia
- **Profili multipli** con avatar (stile Netflix)
- **Modalità bambini**: classificazioni TMDB, parole chiave vietate, catalogo filtrato
- **PIN a 4 cifre** per uscire dalla modalità bambini (sincronizzato nel cloud)
- Cronologia privata per profilo

### Sincronizzazione cloud
- Account con **email e password**
- Profili, preferiti, cronologia, impostazioni player e PIN sincronizzati tra dispositivi
- Cancellazione dei dati cloud dal profilo (salvo le classificazioni bambini)
- Le **credenziali della playlist non vengono mai inviate al cloud**: restano solo sul dispositivo

---

## Requisiti

- Flutter SDK `^3.13.5` (canale stable)
- Xcode (per la build iOS)
- Android SDK (per la build Android)

## Sviluppo locale

```sh
flutter pub get
flutter run
```

---

## Configurazione backend

L'app **non contiene chiavi API**: TMDB, IMDb, IntroDB e i provider di sottotitoli sono usati tramite un proxy nel cloud. L'indirizzo del backend è configurato in `lib/config/supabase_config.dart` (`apiBase`) e può essere modificato in un unico punto.

### Endpoint cloud

| Endpoint | Uso |
| --- | --- |
| `GET /api/public/tmdb` | Metadati TMDB (ricerca, dettagli, consigli) |
| `GET /api/public/imdb` | ID IMDb da ID TMDB o titolo (film e serie) |
| `GET /api/public/kids-check` | Valutazioni contenuti per la modalità bambini |
| `GET /api/public/opensubtitles` | Ricerca e download sottotitoli OpenSubtitles |
| `GET /api/public/subtitles` | Sottotitoli con cache cloud e fallback multi-provider |

### Tabelle cloud

`watch_history`, `user_sync_data`, `sync_profiles`, `user_profiles`, `cloud_favorites`, `subtitle_cache`, `kids_ratings` — tutte protette da **Row Level Security** (ogni utente accede solo ai propri dati).

Le migrazioni SQL sono in `supabase/migrations/`.

---

## Build Android

### Locale

```sh
flutter build apk --release --build-number=<n>
```

L'APK viene prodotto in `build/app/outputs/flutter-apk/app-release.apk`.

### Con Codemagic

Il workflow `android-apk` in `codemagic.yaml`:

- usa Flutter **stable**
- esegue `flutter build apk --release --build-number=$BUILD_NUMBER`
- pubblica gli artefatti con il filtro `build/**/outputs/**/*.apk`

**Nota sulle architetture:** l'APK è **universale** e contiene `arm64-v8a`, `armeabi-v7a` e `x86_64`, quindi funziona su qualsiasi dispositivo Android, inclusi **Fire TV** e **Google TV** (arm64-v8a). Codemagic può mostrare lo stesso APK due volte perché il filtro artefatti include due cartelle di output di Gradle: i due file sono identici.

### Build per architettura (opzionale)

Per APK più piccoli separati per architettura:

```sh
flutter build apk --release --split-per-abi
```

Per Fire TV e Google TV usa `app-arm64-v8a-release.apk`.

## Build iOS

Il workflow `ios-unsigned` in `codemagic.yaml` produce una build **senza firma** da installare via sideload (AltStore, Sideloadly, ecc.). L'analisi Dart statica (`flutter analyze`) gira come primo passaggio del workflow.

---

## Struttura del progetto

```
lib/
├── config/       # Configurazione (SupabaseConfig: apiBase, ecc.)
├── models/       # Modelli dati (Channel, Playlist, TmdbItem, ...)
├── navigation/   # Routing e helper di navigazione
├── player/       # Motori di riproduzione (ExoEngine, MediaKitEngine)
├── providers/    # Stato dell'app (Provider)
├── screens/      # Schermate (Home, Live, Catalogo, Player, ...)
├── services/     # Servizi (TMDB, EPG, sottotitoli, sync, cache, ...)
├── theme/        # Tema v3 "Nebula Glass"
└── widgets/      # Componenti UI (card, sezioni, controlli player)

supabase/
├── functions/    # Edge function TMDB
└── migrations/   # Migrazioni SQL del database
```

### Servizi principali

| Servizio | Ruolo |
| --- | --- |
| `xtream_service.dart` | Login e caricamento playlist Xtream/M3U |
| `playlist_service.dart` | Parsing e gestione playlist |
| `tmdb_service.dart` | Metadati TMDB via proxy cloud |
| `epg_service.dart` | Guida EPG per la diretta |
| `subtitles_service.dart` | Sottotitoli (cache memoria + disco + cloud) |
| `kids_content_service.dart` | Valutazione contenuti per la modalità bambini |
| `sync_service.dart` | Sincronizzazione cloud |
| `catalog_cache_service.dart` | Cache locale del catalogo (avvio istantaneo) |
| `introdb_service.dart` | Skip intro/outro |

---

## Formattazione e analisi

```sh
dart format lib
flutter analyze
```

---

## Sicurezza

- Le chiavi API (TMDB, OpenSubtitles, SubDL, Wyzie) vivono **solo nel backend**, mai nell'app
- **RLS** su tutte le tabelle cloud: ogni utente accede solo ai propri dati
- Le credenziali della playlist non lasciano mai il dispositivo
- Le richieste tra app e cloud passano solo per endpoint pubblici dedicati
