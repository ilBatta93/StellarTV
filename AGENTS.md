# StellarTV (app) — manuale per Claude e Grok

Prima di tutto leggi il master `../AGENTS.md` (regole comuni ai due progetti, collaborazione fra AI, glossario).
Qui ci sono solo comandi, flussi e invarianti dell'app. Prima di modificare un file leggi anche il `CLAUDE.md` della sua cartella: vale per entrambe le AI.

## Indice
1. Regole cardinali
2. Avvio sessione
3. Mappa delle aree
4. Comandi
5. «fai build android»
6. Note di rilascio
7. Invarianti di prodotto
8. Sito companion

## 1. Regole cardinali
Sintesi delle sezioni non derogabili del master, valide anche se il master non fosse disponibile:
- Lessico neutro: niente termini da sorgente di contenuti a pagamento o protetti (elenco nel master §4). Usa sorgente, flusso TV, catalogo.
- Credenziali e indirizzi dei flussi restano sul dispositivo; in cloud solo dati cifrati nel vault.
- Nessuna funzione esistente si rimuove o degrada senza richiesta esplicita.
- Mai chiavi di firma, password o `.env` nel repository.

## 2. Avvio sessione
- Branch `main`: `git fetch`, `git pull --ff-only`, `git status`.
- Leggi l'handoff più recente in `docs/handoff/` (non versionato) se esiste.

## 3. Mappa delle aree
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
| `docs/` | note di rilascio, analisi tecniche, SQL Supabase, handoff |
| `.github/` | workflow di verifica e rilascio |

## 4. Comandi
```bash
flutter pub get
flutter analyze --no-fatal-infos lib test
dart format --output=none --set-exit-if-changed lib test
flutter test
dart run test/<nome>_check.dart
python -m unittest discover -s scripts -p "*_test.py"
```
Sono gli stessi controlli di `verify.yml`: falli passare per le aree toccate prima di dire «fatto».

## 5. «fai build android»
Solo su questa frase esplicita, una build alla volta:
1. Allinea `main` al remoto; working tree pulito e spinto.
2. Aggiorna `docs/release-current.md` (sezione 6) e spingilo.
3. Avvia `StellarTV Android Release` (`build.yml`) con `gh workflow run`.
4. Seguilo con `gh run watch` fino al successo. Se fallisce: leggi il log, correggi, spingi, rilancia.
5. Riporta versione, esito e link alla release.

La build iOS (`build-ios.yml`) parte solo su richiesta esplicita equivalente.

## 6. Note di rilascio
- Fonte: `docs/release-current.md`, elenco puntato. `scripts/release_notes.py` pubblica solo le righe assenti dal file al commit dell'ultima build riuscita dello stesso workflow.
- Quindi: dopo una build riuscita, la volta successiva **sostituisci** l'elenco con le sole novità nuove. Una riga già pubblicata e poi riformulata verrebbe pubblicata di nuovo.
- Novità per l'utente dall'ultima build riuscita, una volta sola, in linguaggio neutro. Niente testo dei commit, niente nomi di classi, metodi o file.
- Se cambia codice in `lib/` o `packages/` serve almeno una riga nuova, altrimenti lo script ferma la build. Per sola manutenzione basta una riga che lo dica.
- Lo script rifiuta anche parole come `film`, `serie`, `playlist`, `password`, `token`: riformula.

## 7. Invarianti di prodotto
- UI pensata prima per il telecomando: focus visibile, D-Pad fluido, tasto Indietro coerente. La presentazione TV dipende dalla modalità di interfaccia Android; il layout touch resta quello attuale.
- Identità nativa StellarTV su ogni piattaforma (`tv.stellar.app`). I nomi Dart e i bridge nativi del player cambiano insieme.
- Le cache bambino sul dispositivo includono le certificazioni. I verdetti in cloud si rivalutano. Un consenso vecchio basato solo sul rating non basta. Un verdetto sconosciuto resta nascosto.
- La sincronizzazione usa l'id dell'account autenticato.
- Le righe legacy del vault non si cancellano da sole. Un preferito rimosso resta un tombstone nella corsia riservata.
- Con una sola connessione ammessa il rilascio del player nativo precede il flusso successivo. Con più connessioni il successivo può aprirsi prima della chiusura, e `released` attende comunque lo smaltimento reale.
- La diretta non entra nella cronologia di visione né nel cloud.
- Un episodio non eredita il voto della serie ma ha il suo. Un voto IMDb non ancora arrivato non si mostra.
- Supabase: progetto `dzojklhnwdjcrmkbepft`, schema solo via SQL incollato a mano (master §8).

## 8. Sito companion
In `../stellartv-ae76efd2`, con il suo `AGENTS.md`. Le API che l'app chiama stanno in `src/routes/api/public/` del sito; la guida per l'utente in `src/lib/guideContent.ts`.
