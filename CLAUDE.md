# StellarTV (app) — istruzioni per Claude

Le regole comuni ai due progetti stanno in `C:\Progetti\CLAUDE.md` (master). Qui c'è solo ciò che è proprio dell'app.
Prima di ogni modifica leggi e segui @AGENTS.md (invarianti di prodotto) e @.cursorrules (regole cardinali).

## Indice
1. Avvio sessione
2. Mappa delle aree
3. Comandi
4. «fai build android»
5. Note di rilascio
6. Vincoli dell'app
7. Sito companion

## 1. Avvio sessione
- Branch di lavoro: `main`. Allinealo al remoto: `git fetch` e `git pull --ff-only`.
- Se esiste un handoff recente in `docs/handoff/` (non versionato), leggilo prima di ripartire.

## 2. Mappa delle aree
Ogni cartella elencata ha un proprio `CLAUDE.md` con le regole dell'area.

| Cartella | Contenuto |
| --- | --- |
| `lib/` | entrypoint, config, tema, rotte |
| `lib/player/` | motori di riproduzione (ExoPlayer, media_kit), sessione, salute del flusso |
| `lib/services/` | logica senza UI: catalogo, guida TV, sync, vault, diagnostica, policy |
| `lib/providers/` | stato condiviso (pacchetto `provider`) |
| `lib/models/` | modelli dati e policy pure |
| `lib/screens/` | schermate complete |
| `lib/widgets/` | componenti riusabili, varianti TV e player |
| `packages/video_player_android/` | fork del plugin video Android (ExoPlayer) |
| `android/` · `ios/` | progetti nativi, manifest, firma |
| `test/` | test Flutter e script di policy `*_check.dart` |
| `scripts/` | generatore delle note di rilascio |
| `docs/` | note di rilascio, analisi tecniche, SQL Supabase |
| `.github/` | workflow di verifica e rilascio |

## 3. Comandi
```bash
flutter pub get
flutter analyze --no-fatal-infos lib test
dart format --output=none --set-exit-if-changed lib test
flutter test
dart run test/<nome>_check.dart
```
- Sono gli stessi controlli di `verify.yml`. Prima di dire «fatto» falli passare per le aree toccate.
- `flutter build` e `gh workflow run` chiedono conferma: non usarli senza la frase della sezione 4.

## 4. «fai build android»
Solo su questa frase esplicita, una build alla volta:
1. Allinea `main` al remoto e verifica che il working tree sia pulito e spinto.
2. Aggiorna `docs/release-current.md` (sezione 5) e spingilo.
3. Avvia il workflow `StellarTV Android Release` (`build.yml`) con `gh workflow run`.
4. Seguilo con `gh run watch` fino al successo. Se fallisce, leggi il log, correggi, spingi e rilancia.
5. A fine run riporta versione, esito e link alla release.

La build iOS (`build-ios.yml`) parte solo su richiesta esplicita equivalente.

## 5. Note di rilascio
- Fonte: `docs/release-current.md`, elenco puntato. `scripts/release_notes.py` lo valida e pubblica solo le righe nuove rispetto all'ultima build riuscita.
- Descrivono le novità per l'utente dall'ultimo commit buildato con successo dallo stesso workflow, una volta sola, in linguaggio neutro.
- Non copiare il testo dei commit, niente nomi di classi o metodi.
- Lo script rifiuta anche parole come `film`, `serie`, `playlist`, `password`, `token`: riformula.

## 6. Vincoli dell'app
- UI progettata prima per il telecomando: focus visibile, D-Pad fluido, tasto Indietro coerente. La presentazione TV dipende dalla modalità di interfaccia Android; il layout touch resta quello attuale.
- Identità nativa: StellarTV su ogni piattaforma (pacchetto Android `tv.stellar.app`). I nomi Dart e i bridge nativi del player cambiano insieme.
- Lingua dell'interfaccia: italiano.

## 7. Sito companion
In `../stellartv-ae76efd2`, con le sue regole (`CLAUDE.md` e `AGENTS.md` di quel repository): seguile quando lavori lì.
Le API che l'app chiama stanno in `src/routes/api/public/` del sito.
