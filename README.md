# StellarTV

Lettore TV, film e serie per iPhone, iPad e Android, realizzato con Flutter, con dati sincronizzati tramite account email e password.

## Funzionalità

- Caricamento di playlist M3U e account Xtream Codes
- Canali TV in diretta, film e serie TV, con categorie, ricerca e preferiti
- Pagina "Scopri" con Top 10 settimanali e consigli personalizzati (dati TMDB)
- Playlist, profili, cronologie, preferiti e impostazioni sincronizzati tra dispositivi tramite account email e password
- Carosello "Continua a guardare" con ripresa esatta dal punto interrotto
- Player con due motori (ExoPlayer / AVPlayer e mpv), gesti, tracce audio/sottotitoli e statistiche

---

## Indice

1. [Struttura del progetto](#1-struttura-del-progetto)
2. [Caricare il progetto su GitHub](#2-caricare-il-progetto-su-github)
3. [Configurare Supabase (backend)](#3-configurare-supabase-backend)
4. [Compilare l'app iPhone senza Mac (Codemagic + TestFlight)](#5-compilare-lapp-iphone-senza-mac-codemagic--testflight)
6. [Compilare l'app Android (facoltativo)](#6-compilare-lapp-android-facoltativo)
7. [Sviluppo locale (facoltativo, con Mac o PC)](#7-sviluppo-locale-facoltativo-con-mac-o-pc)
8. [Risoluzione dei problemi](#8-risoluzione-dei-problemi)

---

## 1. Struttura del progetto

```
lib/
  config/        Indirizzo e chiave pubblica di Supabase
  models/        Modelli dati (canali, playlist, cronologia, ...)
  navigation/    Navigazione tra le schermate e avvio del player
  player/        Motori di riproduzione (ExoPlayer / VLC) e sessione
  providers/     Stato dell'app (cronologia, catalogo)
  screens/       Schermate (Home, Catalogo, Player, Impostazioni, ...)
  services/      Accesso a playlist, Xtream, TMDB, Supabase
  theme/         Colori e stile
  widgets/       Elementi grafici riutilizzabili
supabase/
  functions/     Funzioni server (tmdb)
  migrations/    Struttura del database (solo riferimento storico)
ios/             Progetto iPhone / iPad
android/         Progetto Android
codemagic.yaml   Configurazione della compilazione automatica iOS
```

**Identificativi dell'app**

| Piattaforma | Identificativo         |
|-------------|------------------------|
| iOS         | `tv.stellar.app` |
| Android     | `tv.stellar.app` |

---

## 2. Caricare il progetto su GitHub

### Opzione A — dal browser (senza installare nulla)

1. Scarica il progetto come archivio ZIP ed estrailo sul computer.
2. Vai su <https://github.com/new>, scegli un nome (es. `stellartv`), seleziona **Private** e premi **Create repository**.
   Non aggiungere README, .gitignore o licenza: sono già inclusi.
3. Nella pagina del repository vuoto clicca **uploading an existing file**.
4. Trascina **il contenuto** della cartella estratta (non la cartella stessa).
   Su macOS i file nascosti come `.gitignore` non sono visibili: premi `Cmd + Shift + .` nel Finder per mostrarli e includerli.
5. Non caricare le cartelle `.dart_tool`, `build`, `.v3` e il file `.env` se presenti.
6. Premi **Commit changes**.

### Opzione B — da terminale

```bash
cd stellartv
git init
git add .
git commit -m "Prima versione di StellarTV"
git branch -M main
git remote add origin https://github.com/TUO-UTENTE/stellartv.git
git push -u origin main
```

Il file `.gitignore` esclude automaticamente file temporanei, file generati e segreti locali.

> La chiave Supabase presente in `lib/config/supabase_config.dart` è la chiave **pubblica** (anon): è progettata per stare nell'app e i dati sono protetti dalle regole di sicurezza del database. Usa comunque un repository **privato**.

---

## 3. Configurare Supabase (backend)

Il database, le tabelle e le funzioni server sono **già creati e attivi**: non serve alcuna configurazione aggiuntiva.

### Componenti già attivi

| Componente | Descrizione |
|------------|-------------|
| Tabella `sync_profiles` | Cronologia e preferiti sincronizzati tra dispositivi tramite codice a 8 caratteri |
| Funzione `tmdb` | Recupera locandine, Top 10 e consigli da TMDB senza esporre la chiave |

---

## 4. Compilare l'app iPhone senza Mac (Codemagic + TestFlight)

### Requisiti

- Account **Apple Developer Program** (99 USD/anno) — <https://developer.apple.com/programs/>
- Account **Codemagic** (piano gratuito sufficiente) — <https://codemagic.io>
- Il progetto caricato su GitHub (sezione 2)

### 4.1 Registrare l'app su Apple

1. <https://developer.apple.com/account/resources/identifiers> → **+** → **App IDs** → **App**.
2. Bundle ID **Explicit**: `tv.stellar.app`, descrizione `StellarTV`. Salva.
3. <https://appstoreconnect.apple.com> → **App** → **+** → **Nuova app**:
   - Piattaforma: iOS
   - Nome: `StellarTV` (se occupato, aggiungi una variante)
   - Lingua: Italiano
   - Bundle ID: `tv.stellar.app`
   - SKU: `stellartv`

### 4.2 Creare la chiave API per Codemagic

1. App Store Connect → **Utenti e accesso** → **Integrazioni** → **App Store Connect API**.
2. Genera una chiave con ruolo **App Manager**.
3. Annota **Issuer ID** e **Key ID**, scarica il file `.p8` (si può scaricare una sola volta).

### 4.3 Configurare Codemagic

1. Accedi a Codemagic con GitHub e aggiungi il repository `StellarTV` (tipo progetto: **Flutter App**, configurazione: **codemagic.yaml**).
2. **Team settings → Integrations → Developer Portal → Manage keys → Add key**:
   - Nome chiave: **`StellarTV`**.
   - Inserisci Issuer ID, Key ID e carica il file `.p8`.
3. **Team settings → codemagic.yaml settings → Code signing identities**:
   - Scheda **iOS certificates** → **Generate certificate** → tipo *Apple Distribution*, usando la chiave `StellarTV`.
   - Scheda **iOS provisioning profiles** → **Fetch profiles** → seleziona il profilo *App Store* per `tv.stellar.app`
     (se non esiste, crealo su developer.apple.com → Profiles → **+** → *App Store Connect*, poi ripeti il fetch).

### 4.4 Avviare la compilazione

1. Nel progetto Codemagic premi **Start new build**.
2. Scegli il ramo `main` e il workflow **StellarTV iOS (Unsigned - Sideloadly)**.
3. Al termine (circa 15–25 minuti):
   - il file `.ipa` è scaricabile nella sezione **Artifacts**;
   - la build viene inviata automaticamente a **TestFlight**.

### 4.5 Installare sull'iPhone

1. App Store Connect → la tua app → **TestFlight**. Attendi che la build passi da *In elaborazione* a *Pronta* (5–30 minuti).
2. **Test interni** → crea un gruppo e aggiungi il tuo indirizzo Apple ID.
3. Sull'iPhone installa **TestFlight** dall'App Store, apri l'invito ricevuto via email e premi **Installa**.

Per ogni nuova versione basta avviare un'altra build: il numero di build aumenta automaticamente.

---

## 5. Compilare l'app Android (facoltativo)

In Codemagic puoi creare una build Android senza firma per provarla direttamente:

```yaml
  android-apk:
    name: StellarTV Android (APK di prova)
    instance_type: linux_x2
    environment:
      flutter: stable
    scripts:
      - flutter pub get
      - flutter build apk --release
    artifacts:
      - build/app/outputs/flutter-apk/app-release.apk
```

Aggiungi il blocco sotto `workflows:` in `codemagic.yaml`, avvia la build, scarica il file `.apk` dagli Artifacts e aprilo sul telefono (consenti "Installa app sconosciute").

---

## 6. Sviluppo locale (facoltativo, con Mac o PC)

Requisiti: Flutter SDK stabile recente (compatibile con Dart 3.13 o successivo, come indicato nel file del progetto), Xcode per iOS (solo Mac), Android Studio per Android.

```bash
flutter pub get
flutter run            # avvia sul dispositivo o emulatore collegato
flutter build ipa      # solo Mac, richiede firma Apple
flutter build apk      # Android
```

Su Mac, per provare gratis sul proprio iPhone senza Developer Program: apri `ios/Runner.xcworkspace` in Xcode, in **Signing & Capabilities** seleziona il tuo Apple ID come Team, collega l'iPhone e premi Run (l'app resta valida 7 giorni).

---

## 7. Risoluzione dei problemi

| Problema | Soluzione |
|----------|-----------|
| Codemagic: "No matching profiles found" | Controlla che il Bundle ID sia `tv.stellar.app` e ripeti **Fetch profiles** (sezione 4.3). |
| Codemagic: integrazione non trovata | Verifica la chiave API Apple configurata in Codemagic. |
| TestFlight: build "Mancante conformità" | Già gestito nell'app (nessuna crittografia speciale dichiarata). |
| La cronologia non si aggiorna su un altro dispositivo | Accedi con la stessa email e password; poi apri Impostazioni → Account e sincronizzazione → Scarica dal cloud. |
| Un canale non parte | Cambia motore di riproduzione dal player o da Impostazioni → Player. |
