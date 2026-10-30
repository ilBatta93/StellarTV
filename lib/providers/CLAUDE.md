# lib/providers/ — stato condiviso

Regole comuni: master, radice e `lib/CLAUDE.md`.
Qui «provider» è il pacchetto Flutter di stato, non un termine di dominio: il divieto lessicale (master §4) non si applica a questa cartella.

## Contenuto
Un `ChangeNotifier` per dominio: `app_provider` (sorgente, catalogo, stato globale), `epg_provider`, `history_provider`, `profile_provider`, `reactions_provider`, `sync_provider`, `discover_provider`, `ui_settings`.

## Regole
- Il provider orchestra, il servizio lavora: I/O, parsing e policy stanno in `services/`.
- `notifyListeners` solo quando lo stato visibile cambia davvero; niente notifiche in cicli stretti (la TV ridisegna righe intere).
- Un nuovo provider si registra in `main.dart`.
- Cronologia e preferiti passano dal vault cifrato quando vanno in cloud; la diretta non entra in cronologia.

## Verifica
`flutter test` sui test del provider toccato (`test/*history*`, `test/*profile*`, `test/*sync*`…).
