# Ibernazione automatica — Opzione A

- Attività cloud nuove sospese con lifecycle diverso da resumed o segnale Android schermo/HDMI non disponibile. Nessuna esclusiva account, tabella aggiuntiva o heartbeat.
- Timer cronologia, retry cloud, EPG e playlist sospesi; ritorno con una sola pianificazione, throttle cronologia e cooldown dei fallimenti conservati. Dati locali e sessione account mantenuti.
- Le code cataloghi e Filtro Bambino si fermano prima di nuovi gruppi; controlli sicurezza restano fail-closed. Richieste Auth/PostgREST/storage condividono un trasporto bloccato quando nascosta; il SDK continua a gestire correttamente la sessione.
- Una richiesta già partita può terminare; non promettiamo annullamento di ogni operazione in corso. Gli stream video restano gestiti dalle protezioni esistenti, compreso audio in background su telefono se scelto.
- Il segnale HDMI è best-effort: alcune TV/chiavette non notificano spegnimento TV o cambio ingresso; in quei casi il lifecycle non cambia e non è possibile garantire il rilevamento. Nessuna nuova richiesta periodica per tentare di indovinarlo.

## Verifiche prima del rilascio

Controlli Dart: `dart run test/foreground_policy_check.dart`, `dart run test/foreground_http_check.dart`, regressioni `test/playback_work_policy_check.dart`. Nessuna build avviata per questa modifica.

1. Cambiare preferito/progresso con app visibile, andare Home del sistema: nessuna nuova chiamata automatica dopo il completamento di quelle in corso.
2. Rientrare: dati locali presenti, cloud riparte; rapidi Home/rientro non producono salvataggi sovrapposti né annullano il backoff.
3. Spegnere/riaccendere schermo Android; provare TV/HDMI Fire TV e Chromecast: verificare se il dispositivo trasmette un segnale disponibile. Ripresa solo quando display disponibile e app resumed.
4. Aprire un video e cambiare visibilità: nessun aggiornamento playlist/EPG durante il player; controlli video e chiusura stream rimangono quelli esistenti.
5. Lasciare due dispositivi in background: entrambi sospesi; due app davvero visibili restano autorizzate (nessun proprietario esclusivo dell’account).
6. QR account e chiave: polling si sospende quando nascosta; il codice può scadere normalmente, senza perdere dati locali.

Compilazione Flutter/native e misura rete su hardware richiedono prossima build esplicitamente autorizzata e dispositivi reali. Il sito Companion non è modificato.
