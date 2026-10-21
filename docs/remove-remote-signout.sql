-- StellarTV: eliminazione della sola disconnessione remota singola.
-- Eseguire personalmente sul database ESTERNO dopo aver aggiornato/arrestato
-- le vecchie app. Queste possono ancora tentare richieste (404 dopo rimozione).
-- Elimina definitivamente gli ordini di disconnessione in attesa.
-- Non tocca utenti, sessioni Auth, vault, preferiti, cronologia o chiavi.
-- Conserva list_account_sessions ed Esci / disconnessione generale Auth.
-- Nessun CASCADE: dipendenze esterne inattese fermano tutto senza rimuoverle.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '15s';
DROP TABLE IF EXISTS public.session_signout_requests;
COMMIT;

-- Verifica: deve restituire true.
SELECT to_regclass('public.session_signout_requests') IS NULL
  AS richieste_disconnessione_remota_eliminate;
