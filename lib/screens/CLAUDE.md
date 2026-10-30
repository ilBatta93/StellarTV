# lib/screens/ — schermate complete

Regole d'area per Claude e Grok. Valgono anche il master `C:\Progetti\AGENTS.md`, l'`AGENTS.md` della radice e i `CLAUDE.md` delle cartelle superiori. Le regole di focus e telecomando sono in `widgets/CLAUDE.md` e valgono anche qui.

## Regole
- Una schermata compone widget e legge provider; la logica sta in `services/`.
- TV prima di tutto: ogni schermata ha un primo focus esplicito, nessun elemento interattivo irraggiungibile col D-Pad, tasto Indietro che chiude prima il livello più interno (pannello, foglio, dialogo) e poi la schermata.
- Il ramo TV si sceglie con `DeviceTypeService.isTv` (modalità di interfaccia Android). Il layout touch resta quello attuale: non cambiarlo mentre sistemi la TV.
- Testi visibili in italiano e neutri (master §4). Le schermate legacy con nomi tecnici nel file non si rinominano senza richiesta.
- Player e dettagli si aprono da `navigation/app_routes.dart`.
- Schermate di diagnostica: mostrano dati locali e inviano solo su azione esplicita.
- Una funzione visibile nuova o cambiata va descritta nella guida del sito (`src/lib/guideContent.ts`) e, se rilasciata, in `docs/release-current.md`.

## Verifica
- `flutter test` sui test della schermata (`test/tv_*`, `test/*screen*`), `dart run test/tv_render_policy_check.dart` se tocchi il rendering TV.
- Navigazione reale col telecomando non verificabile in CI: dichiaralo.
