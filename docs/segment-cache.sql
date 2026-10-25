-- Execute manually in the external StellarTV SQL Editor.
-- Keeps every key already allowed and adds shared skip-time rows.
-- Existing rows are preserved. No account or playback data.
BEGIN;
ALTER TABLE public.tmdb_metadata_cache DROP CONSTRAINT IF EXISTS tmdb_metadata_cache_key_check;
ALTER TABLE public.tmdb_metadata_cache ADD CONSTRAINT tmdb_metadata_cache_key_check CHECK (
  key ~ '^v1:(movie|tv)/[1-9][0-9]{0,8}(/(credits|videos|watch/providers))?:[a-z]{2}-[A-Z]{2}$'
  OR key ~ '^v1:imdb:(movie|tv)/[1-9][0-9]{0,8}$'
  OR key ~ '^v1:imdb:tv/[1-9][0-9]{0,8}/season/[0-9]{1,3}/episode/[1-9][0-9]{0,3}$'
  OR key ~ '^v1:segments:movie/tt[0-9]{5,10}$'
  OR key ~ '^v1:segments:tv/tt[0-9]{5,10}/season/[0-9]{1,3}/episode/[1-9][0-9]{0,3}$'
);
COMMIT;
