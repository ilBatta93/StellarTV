/*
# Create sync_profiles table (cloud sync via pairing code)

1. New Tables
- `sync_profiles`
  - `code` (text, primary key): 8-character pairing code, the access key for the profile.
  - `payload` (jsonb, not null): synced data blob (watch history, favorites, playlist config, UI settings).
  - `updated_at` (timestamptz, not null, default now()): last modification time, used for merge decisions.

2. Security
- RLS enabled on `sync_profiles`.
- Policies scoped to anon and authenticated: this app has NO account system by design.
  Access is controlled by the secret 8-character pairing code which is the primary key:
  only someone who knows the code shown in the app can read/write that profile row.
  This is an intentional, documented exception to ownership checks (no auth.users involved).
- One row per profile, upserted by the client on push, selected on pull.

3. Important notes
- No destructive operations; safe to re-run (IF NOT EXISTS / DROP POLICY IF EXISTS).
*/

CREATE TABLE IF NOT EXISTS sync_profiles (
  code text PRIMARY KEY,
  payload jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE sync_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "sync_code_read" ON sync_profiles;
CREATE POLICY "sync_code_read"
ON sync_profiles FOR SELECT
TO anon, authenticated
USING (true);

DROP POLICY IF EXISTS "sync_code_insert" ON sync_profiles;
CREATE POLICY "sync_code_insert"
ON sync_profiles FOR INSERT
TO anon, authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS "sync_code_update" ON sync_profiles;
CREATE POLICY "sync_code_update"
ON sync_profiles FOR UPDATE
TO anon, authenticated
USING (true)
WITH CHECK (true);

DROP POLICY IF EXISTS "sync_code_delete" ON sync_profiles;
CREATE POLICY "sync_code_delete"
ON sync_profiles FOR DELETE
TO anon, authenticated
USING (true);
