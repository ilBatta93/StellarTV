# lib/ — codice Dart dell'app

Regole comuni: master `C:\Progetti\CLAUDE.md` e `CLAUDE.md` della radice. Qui le regole valide per tutto `lib/`.

## Struttura
- `main.dart`: avvio, provider di stato, servizi in primo piano.
- `config/`: configurazione Supabase (solo URL e chiave pubblica, mai segreti).
- `theme/app_theme.dart`: unico tema; colori e tipografia passano da qui.
- `navigation/app_routes.dart`: punti d'ingresso condivisi verso player e dettagli (`playChannel` e simili) e traccia delle rotte attive. Apri player e dettagli da qui, non con `Navigator.push` sparsi.
- Sottocartelle con regole proprie: `player/`, `services/`, `providers/`, `models/`, `screens/`, `widgets/`.

## Dipendenze fra livelli
`screens` → `widgets` → `providers` → `services` → `models`. `player/` è usato da schermate e servizi di riproduzione.
- I servizi non dipendono da schermate né da widget. L'unica eccezione esistente (`app_update_service.dart` usa `tv_focusable`) non va estesa.
- I modelli non fanno I/O.

## Stile
- Commenti in inglese, brevi, sul perché. Stringhe dell'interfaccia in italiano.
- `dart format` è obbligatorio: la CI lo controlla.
- Log con `debugPrint` o il `Logger` già presente nel file, mai `print`. Nessun dato sensibile nei log (master §5).

## Trappole note
- Il pacchetto Dart è `stellar_tv`. I canali nativi usano il prefisso `stellartv/` (`stellartv/player`, `stellartv/device`): un nome cambiato in Dart va cambiato anche in Kotlin.
- Ogni schermata deve funzionare col telecomando e col tocco: vedi `widgets/CLAUDE.md`.
