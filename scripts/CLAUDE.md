# scripts/ — note di rilascio e strumenti di sessione

Regole d'area per Claude e Grok. Valgono anche il master `C:\Progetti\AGENTS.md`, l'`AGENTS.md` della radice e i `CLAUDE.md` delle cartelle superiori.

## Contenuto
- `release_notes.py`: legge `docs/release-current.md`, scarta le righe già presenti all'ultimo commit buildato con successo e pubblica solo le nuove. Rifiuta righe con termini bloccati (`BLOCKED`). Regole di contenuto in `AGENTS.md` §6.
- `avvio.py`: riepilogo di inizio sessione per app e sito (repository, handoff, CI, release, deploy, note di rilascio, TODO). Con `--hook` è l'hook SessionStart di Claude: tace fuori da `C:\Progetti` e dopo una compattazione.
- `revisione.py`: revisione prima del push sul repository corrente o `--repo`. `--esegui` lancia solo le verifiche delle aree toccate; `--pre-push` è l'hook git (solo regole bloccanti); `--installa-hook` lo installa nei due repository.
- `gemelle.py`: coerenza app↔sito. Costanti e coppie di file gemelli stanno in `CONSTANTS` e `PAIRS`.
- `db_salute.py`: salute di Supabase con `supabase inspect db` (sola lettura, master §8), lanciato nel sito.
- `ecosistema.py`: percorsi, lettura del diff, regole di lessico (master §4) e segreti (master §5) usate dagli altri.
- `*_test.py`: test `unittest`, eseguiti dal workflow di rilascio prima della pubblicazione.

## Regole
- La lista `BLOCKED` si può solo allargare, mai restringere senza richiesta. Lo stesso vale per `FORBIDDEN`, `STRONG_SECRETS` e `SECRET_FILES` di `ecosistema.py`.
- Lo script delle note non pubblica mai il testo dei commit.
- Ogni modifica a uno script porta un test: `release_notes_test.py` per le note, `strumenti_test.py` per gli altri.
- I test girano anche in CI su Linux senza il sito accanto: solo funzioni pure, niente rete, niente git, niente segreti veri nel testo (le chiavi finte si compongono a runtime, o l'hook pre-push le fermerebbe).
- Gli strumenti leggono e basta, salvo `avvio.py` (fetch, pull `--ff-only` su repository pulito) e `--installa-hook`. Mai scritture su Supabase, Vercel o GitHub.
- Output corto: chi li lancia è un'AI che paga ogni riga in token. Una sezione nuova deve stare in poche righe.

## Verifica
```bash
python -m unittest discover -s scripts -p "*_test.py"
```
