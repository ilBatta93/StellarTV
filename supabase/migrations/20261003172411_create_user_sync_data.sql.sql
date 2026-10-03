/*
# Create user_sync_data table (per-account cloud sync)

1. Plain-English explanation
- The app already syncs via an 8-character pairing code (sync_profiles).
- This migration adds per-ACCOUNT sync: when the user signs in with Google,
  all their data (playlist credentials, watch history, favorites, settings)
  is stored under their user id and restored on any device they sign in on.

2. New Tables
- `user_sync_data`
  - `user_id` (uuid, primary key): the authenticated user owning this data.
  - `payload` (jsonb, not null): full data snapshot (xtream/m3u credentials,
    watch history, favorite ids, tmdb favorites, player + UI settings).
  - `updated_at` (timestamptz, not null, default now()): last modification,
    used to pick the newest snapshot when merging.

3. Security
- RLS enabled. All policies scoped TO authenticated with strict
  `auth.uid() = user_id` ownership checks: a user can read and write ONLY
  their own row. No anon access.

4. Important notes
- Idempotent (IF NOT EXISTS / DROP POLICY IF EXISTS).
- No destructive operations.
*/

CREATE TABLE IF NOT EXISTS user_sync_data (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE user_sync_data ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_read_own_sync" ON user_sync_data;
CREATE POLICY "users_read_own_sync"
ON user_sync_data FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "users_insert_own_sync" ON user_sync_data;
CREATE POLICY "users_insert_own_sync"
ON user_sync_data FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "users_update_own_sync" ON user_sync_data;
CREATE POLICY "users_update_own_sync"
ON user_sync_data FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "users_delete_own_sync" ON user_sync_data;
CREATE POLICY "users_delete_own_sync"
ON user_sync_data FOR DELETE
TO authenticated
USING (auth.uid() = user_id);
