-- Execute manually in the external StellarTV SQL Editor. No playlist/user data.
BEGIN;
CREATE TABLE IF NOT EXISTS public.tmdb_metadata_cache (
  key text PRIMARY KEY CHECK (key ~ '^v1:(movie|tv)/[1-9][0-9]{0,8}(/(credits|videos))?:[a-z]{2}-[A-Z]{2}$'),
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object' AND octet_length(payload::text) <= 262144),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.tmdb_metadata_cache TO anon, authenticated;
GRANT ALL ON public.tmdb_metadata_cache TO service_role;
REVOKE INSERT, UPDATE, DELETE ON public.tmdb_metadata_cache FROM anon, authenticated;
ALTER TABLE public.tmdb_metadata_cache ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public TMDB metadata read" ON public.tmdb_metadata_cache;
CREATE POLICY "Public TMDB metadata read" ON public.tmdb_metadata_cache
  FOR SELECT TO anon, authenticated USING (true);
CREATE INDEX IF NOT EXISTS tmdb_metadata_cache_updated_at_idx
  ON public.tmdb_metadata_cache(updated_at);
COMMIT;