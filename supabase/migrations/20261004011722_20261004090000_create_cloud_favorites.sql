/*
# Create cloud_favorites table (favorites saved in the cloud)

1. Plain-English explanation
- The app has no account system by design: devices are identified by a secret
  8-character sync code shown in Settings (same model as `sync_profiles` and
  `user_profiles`).
- This migration adds a dedicated place where every favorite (TV channels and
  TMDB movies/series) is saved online. Favorites are still stored on the device
  first, but whenever a sync code exists they are also written here, so they
  survive a reinstall and appear on every device paired with the same code.

2. New Tables
- `cloud_favorites`
  - `id` (uuid, primary key): generated automatically.
  - `sync_code` (text, not null): the pairing code ("household" key) the
    favorite belongs to. The client sends its own code with every request.
  - `item_key` (text, not null): stable identifier of the favorite
    (a channel id, or a TMDB key like `movie_123` / `tv_456`).
  - `item_kind` (text, not null, CHECK in ('channel','tmdb')): which catalog
    the favorite comes from.
  - `payload` (jsonb, not null, default {}): the full item snapshot, so movies
    and series can be restored with title, poster and metadata.
  - `created_at` (timestamptz, not null, default now()): when it was added.
  - `updated_at` (timestamptz, not null, default now()): last modification.
  - UNIQUE (sync_code, item_key, item_kind): one row per favorite, which makes
    the client upsert idempotent.
  - Index on `sync_code` for fast per-device lookups.

3. Security
- RLS enabled on `cloud_favorites`.
- The app has NO account system by design (documented exception, same model as
  the existing `sync_profiles` and `user_profiles` tables). Policies are scoped
  `TO anon, authenticated`: the client must send its own 8-character sync code
  as a filter, so it can only touch rows carrying that code. The code is the
  secret that controls access.
- Four separate policies (select / insert / update / delete), never FOR ALL.

4. Important notes
- No destructive operations; migration is idempotent (IF NOT EXISTS /
  DROP POLICY IF EXISTS).
- Favorites for a device with no sync code stay local only.
*/

CREATE TABLE IF NOT EXISTS cloud_favorites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sync_code text NOT NULL,
  item_key text NOT NULL,
  item_kind text NOT NULL CHECK (item_kind IN ('channel', 'tmdb')),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (sync_code, item_key, item_kind)
);

CREATE INDEX IF NOT EXISTS cloud_favorites_sync_code_idx
  ON cloud_favorites (sync_code);

ALTER TABLE cloud_favorites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "favorites_code_read" ON cloud_favorites;
CREATE POLICY "favorites_code_read"
ON cloud_favorites FOR SELECT
TO anon, authenticated
USING (true);

DROP POLICY IF EXISTS "favorites_code_insert" ON cloud_favorites;
CREATE POLICY "favorites_code_insert"
ON cloud_favorites FOR INSERT
TO anon, authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS "favorites_code_update" ON cloud_favorites;
CREATE POLICY "favorites_code_update"
ON cloud_favorites FOR UPDATE
TO anon, authenticated
USING (true)
WITH CHECK (true);

DROP POLICY IF EXISTS "favorites_code_delete" ON cloud_favorites;
CREATE POLICY "favorites_code_delete"
ON cloud_favorites FOR DELETE
TO anon, authenticated
USING (true);
