# Stabilità riproduzione e cloud — 21 ottobre 2026

## Modifiche
- Comandi nascosti all'avvio; OK li apre, tranne quando attiva Salta sigla o il riquadro successivo. All'ingresso nella sigla i comandi si chiudono, il telecomando seleziona Salta sigla e il salto non riapre le barre. Touch e pannelli esistenti restano disponibili.
- Registro delle sessioni condiviso fra player, anteprime e MultiView: playlist e guida aspettano la chiusura di tutte le sessioni; invii cloud aspettano pausa esplicita, fine o chiusura. Buffering non equivale a pausa. Salvataggi locali immediati; ripresa cloud attraverso la coda esistente.
- Download EPG interrotto se comincia una sessione. Parser XMLTV già esistente in isolate invariato; un parse già avviato può finire, ma il risultato non viene applicato durante la visione. Un lavoro già partito non può essere retroattivamente annullato in ogni fase.
- Conflitti: massimo quattro tentativi con attesa casuale 250–400 ms tra tentativi, nuova lettura e merge; mantenuto backoff automatico 5 s–10 min. Nessuna falsa conferma o rimozione del controllo revisione.

## Protezione opzionale database esterno
`cloud-compatibility-guard.sql` è da eseguire personalmente **dopo aver installato la nuova app**: non applicato dall'assistente. Fa da barriera prima del corpo della RPC, anche quando il conflitto avverrebbe prima di una scrittura. Mantiene la funzione originale e verifica firma e risultato attesi; se diversi annulla la modifica.

Una sola installazione: il marcatore di compatibilità cloud=2 resta uguale per aggiornamenti compatibili, non serve SQL a ogni release. Rifiuta con errore esplicito 55000, non 40001, gli invii delle vecchie app con User-Agent StellarTV prive del marcatore. Il sito usa il suo User-Agent e non viene bloccato.

Non è un confine di sicurezza: l'identificazione è dichiarata dal client; versioni senza User-Agent identificabile non sono riconoscibili. Non impedisce richieste HTTP, letture, accesso, né tutte le altre tabelle. Vecchie app possono ancora riprovare; il loro backoff esterno e il messaggio mostrato dipendono da quella versione. Dati locali conservati ma nuovi cambiamenti non sincronizzati fino all'aggiornamento. Una riduzione CPU non è ancora misurata. Nessuna rotazione chiavi.

## Controlli dopo una futura build richiesta
1. Film/episodio: partenza senza comandi; OK li apre; frecce seek non li aprono.
2. Con comandi aperti entrare nella sigla: si chiudono; OK salta senza barre.
3. Durante visione prolungata: niente aggiornamenti playlist/guida né nuovi invii vault; locale continua a salvare.
4. Pausa: cloud può inviare; ripresa blocca nuovi invii. Chiudere il player: invio pendente e guida/playlist riprendono quando sicuro.
5. MultiView: chiudere un riquadro non sblocca lavori mentre un altro è attivo.
6. Due dispositivi: preferiti, cronologia e stati manuali conservati; conflitti distanziati e nessun loop rapido.
7. Dopo SQL opzionale: nuova app salva, vecchia identificabile riceve invito ad aggiornare; sito salva. Confrontare richieste/CPU a uso equivalente.

## Verifiche qui
Sette controlli eseguibili Dart superati e analisi senza errori sulla policy condivisa. Test Flutter player/focus e policy aggiornati, inclusi nel workflow già manuale, ma non eseguiti: SDK Flutter assente e risoluzione pacchetti bloccata da errore TLS pub.dev. Nessuna build Android/iOS e nessuna modifica database avviata. Prova reale cloud e telecomando ancora necessaria.
