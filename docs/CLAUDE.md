# docs/ — documenti dell'app

Regole comuni: master e `CLAUDE.md` della radice.

## Contenuto
- `release-current.md`: fonte delle note di rilascio (radice §5). Solo elenco puntato di novità per l'utente, neutre, senza nomi di classi o metodi.
- `*.md` tecnici: analisi e decisioni (player, primo piano, diagnostica, privacy, migrazioni). Si aggiornano quando cambia il comportamento che descrivono.
- `*.sql`: script Supabase da incollare a mano (master §8): transazionali e idempotenti.
- `handoff/`: file di ripresa fra sessioni, ignorati da git. Si scrivono con la skill `handoff`.

## Regole
- Un documento descrive lo stato attuale, non la cronaca: aggiorna la frase esistente invece di accodare.
- Lessico neutro anche qui (master §4): i documenti finiscono nei commit pubblici.
- La guida per l'utente non sta qui ma nel sito (`src/lib/guideContent.ts`). `guide-functions.md` è una copia vecchia: non usarla come fonte.
