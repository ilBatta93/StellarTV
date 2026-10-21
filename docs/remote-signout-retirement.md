# Riduzione richieste: disconnessione remota rimossa

- Rimossi il controllo all’avvio e il timer ogni 60 secondi per `session_signout_requests`.
- Nessuna richiesta remota sostitutiva su ripresa, pausa, player o eventi account.
- Esci dalle Impostazioni resta disponibile con il telecomando; il rinnovo normale dell’accesso resta invariato.
- Companion: dispositivi caricati su apertura e Aggiorna, senza timer; nessuna nuova richiesta singola o storico in attesa.
- Nessuna modifica a preferiti, cronologia, chiavi, Filtro Bambino, CAS del vault, backoff, playlist o EPG.
- SQL manuale `remove-remote-signout.sql`: elimina solo la tabella richieste remote e i suoi oggetti interni. Conserva elenco dispositivi e normale uscita account. Le vecchie installazioni riceveranno errore finché non aggiornate/arrestare: eliminare la tabella non ferma i loro tentativi di rete.

## Verifica

`dart run test/no_remote_signout_check.dart` controlla l’assenza dei percorsi di richiesta remota e la conservazione di Esci.
Dopo una futura build autorizzata, installare sui dispositivi e controllare l’assenza di richieste periodiche a `session_signout_requests` nei log API.
Le vecchie installazioni continueranno a controllare fino ad aggiornamento o arresto: questa modifica non le ferma a distanza.
Altre richieste legittime (rinnovo token, sincronizzazione già prevista, cache) non sono eliminate: non promette traffico zero né una CPU specifica.
Il cambio password non garantisce revoca istantanea dei token; la disconnessione generale non annulla i token di accesso già emessi prima della loro scadenza.
