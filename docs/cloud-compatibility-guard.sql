-- StellarTV — DATABASE ESTERNO: eseguire personalmente, NON automaticamente.
-- Installare prima la nuova app con il marcatore cloud=2; poi applicare questo blocco.
-- Blocca solo la RPC di salvataggio delle vecchie app identificabili, non tutto il DB.
-- Preserva il corpo originale, revisioni, cifratura e controlli account.
BEGIN;
DO $install$
DECLARE
  original_oid oid;
  signature text;
  arguments text;
  result_type text;
BEGIN
  IF to_regprocedure('public.stellar_save_personal_vault_original(jsonb,bigint)') IS NOT NULL THEN
    RAISE NOTICE 'Protezione già installata; nessuna modifica';
    RETURN;
  END IF;
  original_oid := to_regprocedure('public.save_personal_vault(jsonb,bigint)');
  IF original_oid IS NULL THEN RAISE EXCEPTION 'RPC attesa non trovata: interrompere e fornire la definizione reale'; END IF;
  SELECT pg_get_function_identity_arguments(oid), pg_get_function_arguments(oid),
         pg_get_function_result(oid)
    INTO signature, arguments, result_type FROM pg_proc WHERE oid = original_oid;
  IF (SELECT proargnames[1:2] FROM pg_proc WHERE oid = original_oid)
       IS DISTINCT FROM ARRAY['_envelope','_expected_revision']::text[]
       OR result_type <> 'bigint' THEN
    RAISE EXCEPTION 'Firma RPC diversa da quella prevista: nessuna modifica applicata';
  END IF;
  EXECUTE 'ALTER FUNCTION public.save_personal_vault(jsonb,bigint) RENAME TO stellar_save_personal_vault_original';
  EXECUTE format($create$
    CREATE FUNCTION public.save_personal_vault(%s) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $body$
    DECLARE
      headers jsonb := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb;
      agent text;
    BEGIN
      agent := coalesce(headers->>'user-agent', '');
      IF agent ~* '^StellarTV([/ (]|$)'
         AND agent !~ '(^|[; (])cloud=2([; )]|$)' THEN
        RAISE EXCEPTION USING ERRCODE = '55000',
          MESSAGE = 'STELLAR_CLOUD_UPGRADE_REQUIRED: aggiornare StellarTV; dati locali conservati';
      END IF;
      -- L'originale conserva autenticazione, validazione e controllo revisione.
      RETURN public.stellar_save_personal_vault_original(_envelope, _expected_revision);
    END;
    $body$;
  $create$, arguments);
  REVOKE ALL ON FUNCTION public.stellar_save_personal_vault_original(jsonb,bigint)
    FROM PUBLIC, anon, authenticated;
  REVOKE ALL ON FUNCTION public.save_personal_vault(jsonb,bigint) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION public.save_personal_vault(jsonb,bigint) TO authenticated, service_role;
END;
$install$;
NOTIFY pgrst, 'reload schema';
COMMIT;

-- Verifica di sola lettura: devono risultare entrambe le funzioni.
SELECT proname, pg_get_function_arguments(oid) AS arguments,
       pg_get_function_result(oid) AS result_type
FROM pg_proc WHERE pronamespace = 'public'::regnamespace
AND proname IN ('save_personal_vault', 'stellar_save_personal_vault_original');

-- RIPRISTINO: selezionare ed eseguire solo se necessario, separatamente.
-- BEGIN;
-- DROP FUNCTION public.save_personal_vault(jsonb,bigint);
-- ALTER FUNCTION public.stellar_save_personal_vault_original(jsonb,bigint) RENAME TO save_personal_vault;
-- GRANT EXECUTE ON FUNCTION public.save_personal_vault(jsonb,bigint) TO authenticated, service_role;
-- NOTIFY pgrst, 'reload schema';
-- COMMIT;
