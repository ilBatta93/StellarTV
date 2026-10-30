# lib/models/ — modelli dati e policy pure

Regole comuni: master, radice e `lib/CLAUDE.md`.

## Regole
- I modelli non fanno I/O e non chiamano servizi. Serializzazione JSON con `fromJson`/`toJson` scritti a mano, come nei file esistenti.
- Un campo nuovo serializzato deve leggere i dati vecchi senza errori (default espliciti): sul dispositivo ci sono cache e backup di versioni precedenti.
- Le preferenze che vanno in cloud seguono l'allowlist chiusa del sito: player, codec e dispositivo restano locali.
- `watch_completion_policy.dart` è la soglia di completamento condivisa col sito: se la cambi, cambia anche la gemella nel sito.
- `rating_policy.dart`: un episodio ha il suo voto, non quello della serie.

## Verifica
`flutter test` sui test che importano il modello (`grep -l <modello> test/`), più `dart run test/title_rating_policy_check.dart` per i voti.
