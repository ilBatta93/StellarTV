# scripts/ — note di rilascio

Regole comuni: master e `CLAUDE.md` della radice (sezione 5).

## Contenuto
- `release_notes.py`: legge `docs/release-current.md`, scarta le righe già presenti all'ultimo commit buildato con successo e pubblica solo le nuove. Rifiuta righe con termini bloccati (`BLOCKED`).
- `release_notes_test.py`: test `unittest`, eseguiti dal workflow di rilascio prima della pubblicazione.

## Regole
- La lista `BLOCKED` si può solo allargare, mai restringere senza richiesta.
- Lo script non pubblica mai il testo dei commit.
- Ogni modifica allo script porta un test in `release_notes_test.py`.

## Verifica
```bash
python -m unittest discover -s scripts -p "*_test.py"
```
