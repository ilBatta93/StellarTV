# docs/ — documenti dell'app

Regole d'area per Claude e Grok. Valgono anche il master `C:\Progetti\AGENTS.md`, l'`AGENTS.md` della radice e i `CLAUDE.md` delle cartelle superiori.

## Contenuto
- `release-current.md`: fonte delle note di rilascio (`AGENTS.md` §6). Solo elenco puntato di novità per l'utente, neutre, senza nomi di classi o metodi.
- `*.md` tecnici: analisi e decisioni (player, primo piano, diagnostica, privacy, migrazioni). Si aggiornano quando cambia il comportamento che descrivono.
- `*.sql`: script Supabase da incollare a mano (master §8): transazionali e idempotenti.
- `handoff/`: file di ripresa fra sessioni, ignorati da git. Formato comune a Claude e Grok nel master §12.

## Regole
- Un documento descrive lo stato attuale, non la cronaca: aggiorna la frase esistente invece di accodare.
- Lessico neutro anche qui (master §4): i documenti finiscono nei commit pubblici.
- La guida per l'utente non sta qui ma nel sito (`src/lib/guideContent.ts`).
