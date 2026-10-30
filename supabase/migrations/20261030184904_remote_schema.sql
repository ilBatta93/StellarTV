SET local check_function_bodies = off;

CREATE EXTENSION "pg_cron";

CREATE TABLE "public"."cloud_favorites" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "sync_code"  text                     NOT NULL,
  "item_key"   text                     NOT NULL,
  "item_kind"  text                     NOT NULL,
  "payload"    jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "cloud_favorites_item_kind_check" CHECK ((item_kind = ANY (ARRAY['channel'::text, 'tmdb'::text]))),
  CONSTRAINT "cloud_favorites_pkey" PRIMARY KEY (id),
  CONSTRAINT "cloud_favorites_sync_code_item_key_item_kind_key" UNIQUE (sync_code, item_key, item_kind)
);

ALTER TABLE "public"."cloud_favorites"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."iptv_playlists" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "user_id"    uuid                     NOT NULL,
  "name"       text                     NOT NULL,
  "kind"       text                     NOT NULL DEFAULT 'xtream'::text,
  "server_url" text                     NOT NULL DEFAULT ''::text,
  "username"   text                     NOT NULL DEFAULT ''::text,
  "password"   text                     NOT NULL DEFAULT ''::text,
  "m3u_url"    text                     NOT NULL DEFAULT ''::text,
  "epg_url"    text                     NOT NULL DEFAULT ''::text,
  "is_active"  boolean                  NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "iptv_playlists_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."iptv_playlists"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."key_handoffs" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "code"         text                     NOT NULL,
  "receiver_key" text                     NOT NULL,
  "sender_key"   text,
  "nonce"        text,
  "ciphertext"   text,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "expires_at"   timestamp with time zone NOT NULL DEFAULT (now() + '00:10:00'::interval),
  CONSTRAINT "key_handoffs_code_key" UNIQUE (code),
  CONSTRAINT "key_handoffs_pkey" PRIMARY KEY (id),
  "user_id"      uuid                     NOT NULL DEFAULT auth.uid()
);

ALTER TABLE "public"."key_handoffs"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."kids_ratings" (
  "key"           text                     NOT NULL,
  "is_kids"       boolean                  NOT NULL,
  "certification" text                     NOT NULL DEFAULT ''::text,
  "tmdb_id"       integer,
  "updated_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "genre_ids"     integer[],
  CONSTRAINT "kids_ratings_pkey" PRIMARY KEY (key)
);

ALTER TABLE "public"."kids_ratings"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."kids_ratings" FROM "anon", "authenticated";

CREATE TABLE "public"."live_diagnostic_reports" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "user_id"    uuid                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "report"     jsonb                    NOT NULL,
  CONSTRAINT "diagnostic_report_shape"
    CHECK (((jsonb_typeof(report) = 'object'::text) AND ((report ->> 'app'::text) = 'StellarTV'::text) AND (jsonb_typeof((report -> 'events'::text)) = 'array'::text))),
  CONSTRAINT "diagnostic_report_size" CHECK ((octet_length((report)::text) <= 524288)),
  CONSTRAINT "live_diagnostic_reports_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."live_diagnostic_reports"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."personal_vaults" (
  "user_id"    uuid                     NOT NULL,
  "envelope"   jsonb                    NOT NULL,
  "revision"   bigint                   NOT NULL DEFAULT 1,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "personal_vault_envelope"
    CHECK
    (((jsonb_typeof(envelope) = 'object'::text) AND ((envelope ->> 'v'::text) = '1'::text) AND ((envelope ->> 'alg'::text) = 'A256GCM'::text) AND ((envelope ->> 'keyId'::text) ~
    '^[a-f0-9]{64}$'::text) AND ((envelope ->> 'nonce'::text) ~ '^[A-Za-z0-9+/]{16}$'::text) AND ((envelope ->> 'ciphertext'::text) ~ '^[A-Za-z0-9+/]+={0,2}$'::text) AND
    (length((envelope ->> 'ciphertext'::text)) >= 24) AND (length((envelope ->> 'ciphertext'::text)) <= 12000000) AND
    ((envelope - ARRAY['v'::text, 'alg'::text, 'keyId'::text, 'nonce'::text, 'ciphertext'::text]) = '{}'::jsonb))),
  CONSTRAINT "personal_vaults_pkey" PRIMARY KEY (user_id)
);

ALTER TABLE "public"."personal_vaults"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."subtitle_cache" (
  "cache_key"  text                     NOT NULL,
  "imdb_id"    text                     NOT NULL,
  "season"     integer,
  "episode"    integer,
  "language"   text                     NOT NULL DEFAULT 'it'::text,
  "source"     text                     NOT NULL,
  "content"    text                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "subtitle_cache_pkey" PRIMARY KEY (cache_key)
);

ALTER TABLE "public"."subtitle_cache"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."subtitle_cache" FROM "anon", "authenticated";

CREATE TABLE "public"."sync_profiles" (
  "code"       text                     NOT NULL,
  "payload"    jsonb                    NOT NULL,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "sync_profiles_pkey" PRIMARY KEY (code)
);

ALTER TABLE "public"."sync_profiles"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."tmdb_artwork" (
  "key"           text                     NOT NULL,
  "tmdb_id"       integer,
  "poster_path"   text,
  "backdrop_path" text,
  "logo_path"     text,
  "updated_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "tmdb_artwork_pkey" PRIMARY KEY (key)
);

ALTER TABLE "public"."tmdb_artwork"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."tmdb_artwork" FROM "anon", "authenticated";

CREATE TABLE "public"."tmdb_metadata_cache" (
  "key"        text                     NOT NULL,
  "payload"    jsonb                    NOT NULL,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "tmdb_metadata_cache_key_check"
    CHECK
    (((key ~ '^v1:(movie|tv)/[1-9][0-9]{0,8}(/(credits|videos|watch/providers))?:[a-z]{2}-[A-Z]{2}$'::text) OR (key ~ '^v1:imdb:(movie|tv)/[1-9][0-9]{0,8}$'::text) OR (key ~
    '^v1:imdb:tv/[1-9][0-9]{0,8}/season/[0-9]{1,3}/episode/[1-9][0-9]{0,3}$'::text) OR (key ~ '^v1:segments:movie/tt[0-9]{5,10}$'::text) OR
    (key ~ '^v1:segments:tv/tt[0-9]{5,10}/season/[0-9]{1,3}/episode/[1-9][0-9]{0,3}$'::text))),
  CONSTRAINT "tmdb_metadata_cache_payload_check" CHECK (((jsonb_typeof(payload) = 'object'::text) AND (octet_length((payload)::text) <= 262144))),
  CONSTRAINT "tmdb_metadata_cache_pkey" PRIMARY KEY (key)
);

ALTER TABLE "public"."tmdb_metadata_cache"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."tmdb_platform_catalogs" (
  "key"        text                     NOT NULL,
  "results"    jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "tmdb_platform_catalogs_pkey" PRIMARY KEY (key)
);

ALTER TABLE "public"."tmdb_platform_catalogs"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."tmdb_platform_catalogs" FROM "anon", "authenticated";

CREATE TABLE "public"."tmdb_ratings" (
  "key"         text                     NOT NULL,
  "rating"      real                     NOT NULL DEFAULT 0,
  "tmdb_id"     integer,
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "poster_path" text,
  CONSTRAINT "tmdb_ratings_pkey" PRIMARY KEY (key)
);

ALTER TABLE "public"."tmdb_ratings"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."tmdb_ratings" FROM "anon", "authenticated";

CREATE TABLE "public"."tv_pairings" (
  "code"               text                     NOT NULL,
  "device_secret_hash" text                     NOT NULL,
  "device_name"        text                     NOT NULL DEFAULT 'TV'::text,
  "status"             text                     NOT NULL DEFAULT 'pending'::text,
  "user_id"            uuid,
  "token_hash"         text,
  "created_at"         timestamp with time zone NOT NULL DEFAULT now(),
  "expires_at"         timestamp with time zone NOT NULL DEFAULT (now() + '00:10:00'::interval),
  CONSTRAINT "tv_pairings_pkey" PRIMARY KEY (code)
);

ALTER TABLE "public"."tv_pairings"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."tv_pairings" FROM "anon", "authenticated";

CREATE TABLE "public"."user_profiles" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "sync_code"    text                     NOT NULL,
  "name"         text                     NOT NULL,
  "avatar_key"   text                     NOT NULL DEFAULT 'rocket'::text,
  "avatar_color" text                     NOT NULL DEFAULT 'arancio'::text,
  "is_kids"      boolean                  NOT NULL DEFAULT false,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "user_profiles_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."user_profiles"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."user_sync_data" (
  "user_id"    uuid                     NOT NULL,
  "payload"    jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "user_sync_data_pkey" PRIMARY KEY (user_id)
);

ALTER TABLE "public"."user_sync_data"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."watch_history" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "content_id"       text                     NOT NULL,
  "content_type"     text                     NOT NULL,
  "title"            text                     NOT NULL DEFAULT ''::text,
  "poster_url"       text                     NOT NULL DEFAULT ''::text,
  "group_name"       text                     NOT NULL DEFAULT ''::text,
  "position_seconds" integer                  NOT NULL DEFAULT 0,
  "duration_seconds" integer                  NOT NULL DEFAULT 0,
  "last_watched_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "created_at"       timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "watch_history_content_id_check" CHECK (((char_length(content_id) >= 1) AND (char_length(content_id) <= 512))),
  CONSTRAINT "watch_history_content_type_check" CHECK ((content_type = ANY (ARRAY['live'::text, 'movie'::text, 'series'::text]))),
  CONSTRAINT "watch_history_duration_seconds_check" CHECK ((duration_seconds >= 0)),
  CONSTRAINT "watch_history_group_name_check" CHECK ((char_length(group_name) <= 300)),
  CONSTRAINT "watch_history_pkey" PRIMARY KEY (id),
  CONSTRAINT "watch_history_position_seconds_check" CHECK ((position_seconds >= 0)),
  CONSTRAINT "watch_history_poster_url_check" CHECK ((char_length(poster_url) <= 2048)),
  CONSTRAINT "watch_history_title_check" CHECK ((char_length(title) <= 500)),
  "user_id"          uuid                     NOT NULL DEFAULT auth.uid(),
  CONSTRAINT "watch_history_user_id_content_id_key" UNIQUE (user_id, content_id)
);

ALTER TABLE "public"."watch_history"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.clean_legacy_snapshot (
  value jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO 'public'
  AS $function$
 SELECT public.strip_legacy_source_fields(value) || jsonb_build_object('settings',public.media_private_snapshot(value)->'settings')
$function$;

CREATE OR REPLACE FUNCTION public.complete_personal_vault_migration (
  _revision bigint,
  _key_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$ BEGIN RETURN false; END $function$;

CREATE OR REPLACE FUNCTION public.guard_media_snapshot()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
BEGIN
 IF TG_OP='UPDATE' AND NEW.payload=public.clean_legacy_snapshot(OLD.payload) THEN RETURN NEW; END IF;
 RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION public.key_handoffs_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
BEGIN
  DELETE FROM public.key_handoffs WHERE expires_at < now() - interval '1 minute';
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := now();
    NEW.expires_at := now() + interval '10 minutes';
    NEW.sender_key := NULL; NEW.nonce := NULL; NEW.ciphertext := NULL;
    IF NEW.code !~ '^[A-HJ-NP-Z2-9]{6}$' OR length(NEW.receiver_key) > 64 THEN
      RAISE EXCEPTION 'invalid handoff';
    END IF;
  ELSE
    IF NEW.code <> OLD.code OR NEW.receiver_key <> OLD.receiver_key OR NEW.user_id <> OLD.user_id
       OR NEW.expires_at <> OLD.expires_at OR NEW.created_at <> OLD.created_at THEN
      RAISE EXCEPTION 'immutable handoff';
    END IF;
    IF length(coalesce(NEW.ciphertext,'')) > 2048 OR length(coalesce(NEW.sender_key,'')) > 64 OR length(coalesce(NEW.nonce,'')) > 32 THEN
      RAISE EXCEPTION 'invalid handoff';
    END IF;
  END IF;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.list_account_sessions()
  RETURNS TABLE (
    id             uuid,
    created_at     timestamp with time zone,
    last_active_at timestamp with time zone,
    user_agent     text,
    is_current     boolean
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  SELECT s.id, s.created_at,
    greatest(s.created_at, s.updated_at, s.refreshed_at AT TIME ZONE 'UTC'),
    s.user_agent,
    s.id::text = coalesce(auth.jwt()->>'session_id', '')
  FROM auth.sessions s
  WHERE s.user_id = auth.uid()
    AND (s.not_after IS NULL OR s.not_after > now())
  ORDER BY greatest(s.created_at, s.updated_at, s.refreshed_at AT TIME ZONE 'UTC') DESC, s.id
$function$;

CREATE OR REPLACE FUNCTION public.media_private_snapshot (
  value jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO 'public'
  AS $function$
DECLARE settings jsonb := '{}'::jsonb; k text; v jsonb; cleaned jsonb;
BEGIN
 IF jsonb_typeof(value->'settings') = 'object' THEN
  FOR k,v IN SELECT * FROM jsonb_each(value->'settings') LOOP
   IF k = ANY(ARRAY['theme_mode','ui_accent','ui_text_scale','ui_grid_size','ui_glow','ui_focus_glow','ui_animations','ui_show_posters','ui_show_ratings','ui_show_quality','ui_show_titles','ui_compact','ui_catalog_view','ui_section_order','ui_start_section','ui_multiview_layout','show_adult_content','ui_home_shape','ui_home_recent_shape','ui_home_density','ui_home_recent_density','ui_home_recommendation_limit','ui_home_recent_limit','ui_home_banner_size','ui_home_overview','ui_scale','ui_watched_percent','ui_home_titles','ui_home_recent_titles']) THEN
    cleaned := public.media_safe_preference(v);
    IF cleaned <> 'null'::jsonb THEN settings := settings || jsonb_build_object(k,cleaned); END IF;
   END IF;
  END LOOP;
 END IF;
 RETURN jsonb_build_object('v',4,'settings',settings,'history','{}'::jsonb,'profile_histories','{}'::jsonb,'favorite_ids','[]'::jsonb,'tmdb_favorites','[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.media_safe_preference (
  value jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO 'public'
  AS $function$
DECLARE result jsonb; k text; v jsonb; cleaned jsonb; parsed jsonb;
BEGIN
 IF jsonb_typeof(value) IN ('boolean','number') THEN RETURN value; END IF;
 IF jsonb_typeof(value) = 'string' THEN
  IF (value #>> '{}') ~ '^[a-zA-Z0-9_-]{1,40}$' THEN RETURN value; END IF;
  BEGIN parsed := (value #>> '{}')::jsonb; EXCEPTION WHEN others THEN RETURN 'null'::jsonb; END;
  IF jsonb_typeof(parsed) NOT IN ('object','array') THEN RETURN 'null'::jsonb; END IF;
  RETURN to_jsonb(public.media_safe_preference(parsed)::text);
 END IF;
 IF jsonb_typeof(value) = 'array' THEN
  result := '[]'::jsonb;
  FOR v IN SELECT x FROM jsonb_array_elements(value) x LOOP
   cleaned := public.media_safe_preference(v);
   IF cleaned <> 'null'::jsonb THEN result := result || jsonb_build_array(cleaned); END IF;
  END LOOP;
  RETURN result;
 END IF;
 IF jsonb_typeof(value) = 'object' THEN
  result := '{}'::jsonb;
  FOR k,v IN SELECT * FROM jsonb_each(value) LOOP
   IF k ~ '^[a-zA-Z0-9_-]{1,40}$' AND k !~* '(url|server|user|pass|token|secret|source|stream|channel|title|name|path|key|credential)' THEN
    cleaned := public.media_safe_preference(v);
    IF cleaned <> 'null'::jsonb THEN result := result || jsonb_build_object(k,cleaned); END IF;
   END IF;
  END LOOP;
  RETURN result;
 END IF;
 RETURN 'null'::jsonb;
END $function$;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
  RETURNS event_trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'pg_catalog'
  AS $function$
DECLARE
  cmd record;
  tbl name;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        SELECT c.relname INTO tbl FROM pg_catalog.pg_class c WHERE c.oid = cmd.objid;
        EXECUTE format('alter table if exists %I.%I enable row level security', cmd.schema_name, tbl);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_personal_vault (
  _envelope          jsonb,
  _expected_revision bigint
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
  AS $function$
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
    $function$;

REVOKE ALL ON FUNCTION "public"."save_personal_vault"(jsonb, bigint) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.stellar_save_personal_vault_original (
  _envelope          jsonb,
  _expected_revision bigint
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_current_rev bigint;
  v_new_rev bigint;
  v_ua text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Non autenticato' USING ERRCODE = '42501';
  END IF;

  -- Rilevamento versione app da User-Agent
  BEGIN
    v_ua := current_setting('request.headers', true)::json->>'user-agent';
  EXCEPTION WHEN OTHERS THEN
    v_ua := NULL;
  END;

  -- Se la richiesta proviene dalle vecchie versioni con il bug del loop (3.4.x o 3.5.0..3.5.2),
  -- restituisce la revisione attuale senza sollevare errori, interrompendo immediatamente il loop.
  IF v_ua ~* 'StellarTV/(3\.[0-4]\.|3\.5\.[0-2]\b)' THEN
    SELECT revision INTO v_current_rev FROM personal_vaults WHERE user_id = v_user_id;
    RETURN COALESCE(v_current_rev, 0);
  END IF;

  -- Flusso standard protetto per tutte le versioni stabili (3.5.3+)
  SELECT revision INTO v_current_rev
  FROM personal_vaults
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_current_rev IS NOT NULL AND v_current_rev <> _expected_revision THEN
    RAISE EXCEPTION 'Vault revision conflict: expected %, found %', _expected_revision, v_current_rev
      USING ERRCODE = '40001';
  END IF;

  IF v_current_rev IS NULL AND _expected_revision <> 0 THEN
    RAISE EXCEPTION 'Vault revision conflict: expected %, row missing', _expected_revision
      USING ERRCODE = '40001';
  END IF;

  v_new_rev := COALESCE(v_current_rev, 0) + 1;

  INSERT INTO personal_vaults (user_id, envelope, revision, updated_at)
  VALUES (v_user_id, _envelope, v_new_rev, now())
  ON CONFLICT (user_id) DO UPDATE
    SET envelope = EXCLUDED.envelope,
        revision = v_new_rev,
        updated_at = now();

  RETURN v_new_rev;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."stellar_save_personal_vault_original"(jsonb, bigint) FROM PUBLIC, "anon", "authenticated";

CREATE OR REPLACE FUNCTION public.stellar_skip_unchanged_kids_rating()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
BEGIN
  IF NEW.key IS NOT DISTINCT FROM OLD.key
     AND NEW.is_kids IS NOT DISTINCT FROM OLD.is_kids
     AND NEW.certification IS NOT DISTINCT FROM OLD.certification
     AND NEW.tmdb_id IS NOT DISTINCT FROM OLD.tmdb_id
     AND NEW.genre_ids IS NOT DISTINCT FROM OLD.genre_ids THEN
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.stellartv_cleanup()
  RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  delete from public.tv_pairings where expires_at < now() - interval '1 day';
  delete from public.key_handoffs where expires_at < now() - interval '1 day';
  delete from public.session_signout_requests where created_at < now() - interval '30 days';
  delete from public.live_diagnostic_reports where created_at < now() - interval '60 days';
$function$;

REVOKE ALL ON FUNCTION "public"."stellartv_cleanup"() FROM PUBLIC, "anon", "authenticated";

CREATE OR REPLACE FUNCTION public.strip_legacy_source_fields (
  value jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO 'public'
  AS $function$
DECLARE result jsonb; k text; v jsonb;
BEGIN
 IF jsonb_typeof(value)='object' THEN
  result:='{}'::jsonb;
  FOR k,v IN SELECT * FROM jsonb_each(value) LOOP
   IF k !~* '(url|uri|server|username|password|token|secret|credential|playlist|source|epg|poster|logo|backdrop|api_key|auth_method|kids_pin)' THEN
     result:=result || jsonb_build_object(k,public.strip_legacy_source_fields(v));
   END IF;
  END LOOP;
  RETURN result;
 ELSIF jsonb_typeof(value)='array' THEN
  result:='[]'::jsonb;
  FOR v IN SELECT x FROM jsonb_array_elements(value) x LOOP
    result:=result || jsonb_build_array(public.strip_legacy_source_fields(v));
  END LOOP;
  RETURN result;
 ELSIF jsonb_typeof(value)='string' AND value#>>'{}' ~* '(https?://|ftp://|file://|www\.|[?&](password|username|token)=)' THEN
  RETURN '""'::jsonb;
 END IF;
 RETURN value;
END $function$;

CREATE OR REPLACE FUNCTION public.suppress_retired_media_write()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
BEGIN
 IF TG_TABLE_NAME='cloud_favorites' AND TG_OP='UPDATE' AND NEW.payload=public.strip_legacy_source_fields(OLD.payload) THEN RETURN NEW; END IF;
 RETURN NULL;
END $function$;

ALTER TABLE "public"."user_sync_data"
  ADD CONSTRAINT "user_sync_data_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX cloud_favorites_sync_code_idx ON public.cloud_favorites USING btree (sync_code);

CREATE INDEX idx_user_profiles_sync_code ON public.user_profiles USING btree (sync_code);

CREATE INDEX live_diagnostic_reports_owner_date ON public.live_diagnostic_reports USING btree (user_id, created_at DESC);

CREATE INDEX tmdb_metadata_cache_updated_at_idx ON public.tmdb_metadata_cache USING btree (updated_at);

CREATE TRIGGER media_favorites_storage_retired
  BEFORE INSERT OR UPDATE ON public.cloud_favorites
  FOR EACH ROW
  EXECUTE FUNCTION public.suppress_retired_media_write();

CREATE TRIGGER media_source_storage_retired
  BEFORE INSERT OR UPDATE ON public.iptv_playlists
  FOR EACH ROW
  EXECUTE FUNCTION public.suppress_retired_media_write();

CREATE TRIGGER key_handoffs_guard
  BEFORE INSERT OR UPDATE ON public.key_handoffs
  FOR EACH ROW
  EXECUTE FUNCTION public.key_handoffs_guard();

CREATE TRIGGER stellar_skip_unchanged_kids_rating
  BEFORE UPDATE ON public.kids_ratings
  FOR EACH ROW
  EXECUTE FUNCTION public.stellar_skip_unchanged_kids_rating();

CREATE TRIGGER media_snapshot_privacy
  BEFORE INSERT OR UPDATE ON public.sync_profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_media_snapshot();

CREATE TRIGGER media_user_snapshot_privacy
  BEFORE INSERT OR UPDATE ON public.user_sync_data
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_media_snapshot();

CREATE TRIGGER media_history_storage_retired
  BEFORE INSERT OR UPDATE ON public.watch_history
  FOR EACH ROW
  EXECUTE FUNCTION public.suppress_retired_media_write();

CREATE POLICY "favorites_own" ON "public"."cloud_favorites"
  FOR ALL
  TO "authenticated"
  USING ((sync_code = (( SELECT auth.uid() AS uid))::text))
  WITH CHECK ((sync_code = (( SELECT auth.uid() AS uid))::text));

CREATE POLICY "playlists_own" ON "public"."iptv_playlists"
  FOR ALL
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Owners delete reports" ON "public"."live_diagnostic_reports"
  FOR DELETE
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Owners read reports" ON "public"."live_diagnostic_reports"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Owners submit reports" ON "public"."live_diagnostic_reports"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "personal_vault_owner_write" ON "public"."personal_vaults"
  FOR ALL
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "sync_own" ON "public"."sync_profiles"
  FOR ALL
  TO "authenticated"
  USING ((code = (( SELECT auth.uid() AS uid))::text))
  WITH CHECK ((code = (( SELECT auth.uid() AS uid))::text));

CREATE POLICY "Public TMDB metadata read" ON "public"."tmdb_metadata_cache"
  FOR SELECT
  TO "anon", "authenticated"
  USING (true);

CREATE POLICY "profiles_own" ON "public"."user_profiles"
  FOR ALL
  TO "authenticated"
  USING ((sync_code = (( SELECT auth.uid() AS uid))::text))
  WITH CHECK ((sync_code = (( SELECT auth.uid() AS uid))::text));

CREATE POLICY "users_delete_own_sync" ON "public"."user_sync_data"
  FOR DELETE
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "users_insert_own_sync" ON "public"."user_sync_data"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "users_read_own_sync" ON "public"."user_sync_data"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "users_update_own_sync" ON "public"."user_sync_data"
  FOR UPDATE
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

CREATE EVENT TRIGGER "ensure_rls"
  ON ddl_command_end
  WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  EXECUTE FUNCTION "public"."rls_auto_enable"();

COMMENT ON EXTENSION "pg_cron" IS 'Job scheduler for PostgreSQL';

GRANT EXECUTE ON FUNCTION "public"."clean_legacy_snapshot"(jsonb) TO PUBLIC, "anon", "authenticated";

REVOKE ALL ON FUNCTION "public"."clean_legacy_snapshot"(jsonb) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."clean_legacy_snapshot"(jsonb) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."clean_legacy_snapshot"(jsonb) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."complete_personal_vault_migration"(bigint, text) TO PUBLIC, "anon", "authenticated";

REVOKE ALL ON FUNCTION "public"."complete_personal_vault_migration"(bigint, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."complete_personal_vault_migration"(bigint, text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."complete_personal_vault_migration"(bigint, text) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."guard_media_snapshot"() TO PUBLIC, "anon", "authenticated";

REVOKE ALL ON FUNCTION "public"."guard_media_snapshot"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."guard_media_snapshot"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."guard_media_snapshot"() TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."key_handoffs_guard"() TO PUBLIC, "anon", "authenticated";

REVOKE ALL ON FUNCTION "public"."key_handoffs_guard"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."key_handoffs_guard"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."key_handoffs_guard"() TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."list_account_sessions"() TO PUBLIC, "anon", "authenticated";

REVOKE ALL ON FUNCTION "public"."list_account_sessions"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."list_account_sessions"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."list_account_sessions"() TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."media_private_snapshot"(jsonb) TO PUBLIC, "anon", "authenticated";

REVOKE ALL ON FUNCTION "public"."media_private_snapshot"(jsonb) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."media_private_snapshot"(jsonb) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."media_private_snapshot"(jsonb) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."media_safe_preference"(jsonb) TO PUBLIC, "anon", "authenticated";

REVOKE ALL ON FUNCTION "public"."media_safe_preference"(jsonb) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."media_safe_preference"(jsonb) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."media_safe_preference"(jsonb) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."rls_auto_enable"() TO PUBLIC, "anon", "authenticated";

REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."rls_auto_enable"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."rls_auto_enable"() TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."save_personal_vault"(jsonb, bigint) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."save_personal_vault"(jsonb, bigint) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."save_personal_vault"(jsonb, bigint) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."save_personal_vault"(jsonb, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "public"."stellar_save_personal_vault_original"(jsonb, bigint) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."stellar_save_personal_vault_original"(jsonb, bigint) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."stellar_save_personal_vault_original"(jsonb, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "public"."stellar_skip_unchanged_kids_rating"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."stellar_skip_unchanged_kids_rating"() TO "anon", "authenticated";

REVOKE ALL ON FUNCTION "public"."stellar_skip_unchanged_kids_rating"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."stellar_skip_unchanged_kids_rating"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."stellar_skip_unchanged_kids_rating"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."stellartv_cleanup"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."stellartv_cleanup"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."stellartv_cleanup"() TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."strip_legacy_source_fields"(jsonb) TO PUBLIC, "anon", "authenticated";

REVOKE ALL ON FUNCTION "public"."strip_legacy_source_fields"(jsonb) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."strip_legacy_source_fields"(jsonb) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."strip_legacy_source_fields"(jsonb) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."suppress_retired_media_write"() TO PUBLIC, "anon", "authenticated";

REVOKE ALL ON FUNCTION "public"."suppress_retired_media_write"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."suppress_retired_media_write"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."suppress_retired_media_write"() TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."cloud_favorites" TO "anon", "authenticated";

REVOKE ALL ON TABLE "public"."cloud_favorites" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."cloud_favorites" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."cloud_favorites" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."iptv_playlists" TO "anon", "authenticated";

REVOKE ALL ON TABLE "public"."iptv_playlists" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."iptv_playlists" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."iptv_playlists" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."key_handoffs" TO "anon", "authenticated";

REVOKE ALL ON TABLE "public"."key_handoffs" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."key_handoffs" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."key_handoffs" TO "service_role";

REVOKE ALL ON TABLE "public"."kids_ratings" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."kids_ratings" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."kids_ratings" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."live_diagnostic_reports" TO "anon", "authenticated";

REVOKE ALL ON TABLE "public"."live_diagnostic_reports" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."live_diagnostic_reports" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."live_diagnostic_reports" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."personal_vaults" TO "anon", "authenticated";

REVOKE ALL ON TABLE "public"."personal_vaults" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."personal_vaults" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."personal_vaults" TO "service_role";

REVOKE ALL ON TABLE "public"."subtitle_cache" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."subtitle_cache" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."subtitle_cache" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."sync_profiles" TO "anon", "authenticated";

REVOKE ALL ON TABLE "public"."sync_profiles" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."sync_profiles" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."sync_profiles" TO "service_role";

REVOKE ALL ON TABLE "public"."tmdb_artwork" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tmdb_artwork" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tmdb_artwork" TO "service_role";

REVOKE ALL ON TABLE "public"."tmdb_metadata_cache" FROM "anon";

GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE "public"."tmdb_metadata_cache" TO "anon";

REVOKE ALL ON TABLE "public"."tmdb_metadata_cache" FROM "authenticated";

GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE ON TABLE "public"."tmdb_metadata_cache" TO "authenticated";

REVOKE ALL ON TABLE "public"."tmdb_metadata_cache" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tmdb_metadata_cache" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tmdb_metadata_cache" TO "service_role";

REVOKE ALL ON TABLE "public"."tmdb_platform_catalogs" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tmdb_platform_catalogs" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tmdb_platform_catalogs" TO "service_role";

REVOKE ALL ON TABLE "public"."tmdb_ratings" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tmdb_ratings" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tmdb_ratings" TO "service_role";

REVOKE ALL ON TABLE "public"."tv_pairings" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tv_pairings" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tv_pairings" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."user_profiles" TO "anon", "authenticated";

REVOKE ALL ON TABLE "public"."user_profiles" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."user_profiles" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."user_profiles" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."user_sync_data" TO "anon", "authenticated";

REVOKE ALL ON TABLE "public"."user_sync_data" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."user_sync_data" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."user_sync_data" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."watch_history" TO "anon", "authenticated";

REVOKE ALL ON TABLE "public"."watch_history" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."watch_history" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."watch_history" TO "service_role";

SELECT cron.schedule_in_database('stellartv-cleanup', '0 1 * * *', 'select public.stellartv_cleanup();', 'postgres', NULL, true);

CREATE POLICY "own handoffs delete" ON "public"."key_handoffs"
  FOR DELETE
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "own handoffs insert" ON "public"."key_handoffs"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "own handoffs select" ON "public"."key_handoffs"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND (expires_at > now())));

CREATE POLICY "own handoffs update" ON "public"."key_handoffs"
  FOR UPDATE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND (expires_at > now()) AND (ciphertext IS NULL)))
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

ALTER TABLE "public"."watch_history"
  ADD CONSTRAINT "watch_history_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX idx_watch_history_user_recent ON public.watch_history USING btree (user_id, last_watched_at DESC);

CREATE POLICY "Users add own history" ON "public"."watch_history"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Users delete own history" ON "public"."watch_history"
  FOR DELETE
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Users read own history" ON "public"."watch_history"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Users update own history" ON "public"."watch_history"
  FOR UPDATE
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

