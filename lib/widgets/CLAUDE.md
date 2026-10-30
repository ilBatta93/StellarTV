# lib/widgets/ — componenti riusabili

Regole d'area per Claude e Grok. Valgono anche il master `C:\Progetti\AGENTS.md`, l'`AGENTS.md` della radice e i `CLAUDE.md` delle cartelle superiori.

## Contenuto
- `tv_*`: componenti per telecomando (focus, righe home, pannelli, campo testo, navigazione a griglia).
- `player/`: controlli, gesti, sottotitoli, superficie video, fogli rapidi; varianti `tv_*` per la TV.
- Il resto: card, righe, dialoghi e scaffold condivisi tra TV e touch.

## Telecomando e focus
- Ogni elemento interattivo è raggiungibile col D-Pad e mostra un focus visibile: usa `TvFocusable` invece di reinventarlo.
- Lo spostamento del focus è prevedibile: frecce lungo righe e colonne, nessun salto a elementi fuori schermo, nessuna trappola di focus.
- Indietro chiude il livello più interno. Le scorciatoie a controlli nascosti stanno in `player/tv_playback_shortcuts.dart`, non nei widget.
- Righe e griglie lunghe sono lazy: la TV ha poca memoria e decoder limitati (`tv_render_policy`).
- `UiScale` impagina su un viewport logico e scala insieme layout e hit test. Lo usano solo i contenitori di presentazione: le superfici del player nativo non vanno mai avvolte.
- Le etichette di debug dei ruoli di focus non arrivano in release.

## Touch
Il layout touch resta quello attuale. Una correzione TV non deve cambiare il comportamento touch, e viceversa.

## Verifica
`flutter test test/tv_navigation_test.dart test/tv_navigation_rules_test.dart test/tv_home_rows_stress_test.dart` e i test del widget toccato.
