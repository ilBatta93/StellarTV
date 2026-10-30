# test/ — test e script di policy

Regole d'area per Claude e Grok. Valgono anche il master `C:\Progetti\AGENTS.md`, l'`AGENTS.md` della radice e i `CLAUDE.md` delle cartelle superiori.

## Due tipi di file
- `*_test.dart`: test Flutter, eseguiti con `flutter test` (anche singolarmente: `flutter test test/<nome>_test.dart`).
- `*_check.dart`: script di policy eseguiti con `dart run test/<nome>_check.dart`. Usano `check(condizione, 'regola')` e falliscono con `StateError`. La CI li esegue tutti, uno per uno.
- `fixtures/`: dati finti. Mai credenziali, indirizzi o dati reali di un utente.

## Regole
- Una correzione di bug porta un test che fallisce senza la correzione.
- Un test o un check non si indebolisce né si cancella per farlo passare: si corregge il codice, o si chiede.
- I check proteggono regole di prodotto (privacy, primo piano, rendering TV, voti, scorciatoie). Se la regola cambia per richiesta dell'utente, aggiorna il check nello stesso commit.
- Niente rete reale nei test: usa fake o fixture.
- Nomi e stringhe dei test seguono il lessico neutro (master §4).

## Comandi
```bash
flutter test
for f in test/*_check.dart; do dart run "$f" || echo "FAIL $f"; done
```
