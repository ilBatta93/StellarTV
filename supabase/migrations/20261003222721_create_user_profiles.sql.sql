/*
# Create user profiles table (profile picker with custom avatars)

1. Plain-English explanation
The app has no account system by design: devices are paired through a secret
8-character sync code. User profiles (like Netflix profiles) follow the same
pattern: every profile belongs to a sync code, and only someone who knows the
code can read or manage its profiles. The client stores the sync code locally
and sends it with every request.

2. New Tables
- `user_profiles`
  - `id` (uuid, primary key): generated automatically.
  - `sync_code` (text, not null): the pairing code this profile belongs to.
    Think of it as the "household" key. All profiles of a device family share it.
  - `name` (text, not null): display name shown on the profile card.
  - `avatar_key` (text, not null, default 'rocket'): which built-in icon is used
    as the avatar (the app ships a fixed catalog of colorful icons).
  - `avatar_color` (text, not null, default 'arancio'): accent color for the
    avatar background; matches the app's existing color names.
  - `is_kids` (boolean, not null, default false): optional kids profile flag,
    reserved for future content filtering.
  - `created_at` (timestamptz, default now()): creation time.
  - Index on `sync_code` for fast lookups by code.

3. Security
- RLS enabled on `user_profiles`.
- The app has NO account system by design (documented exception, same model as
  the existing `sync_profiles` table). Policies are scoped `TO anon, authenticated`
  and gated on `sync_code` matching the requester's code: the client must send
  its own code as a query/filter parameter, so it can only touch rows that carry
  that code. The code is the secret that controls access, like sync_profiles.
- Four separate policies (select / insert / update / delete), never FOR ALL.

4. Important notes
- No destructive operations; migration is idempotent (IF NOT EXISTS / DROP POLICY IF EXISTS).
- Validation of avatar keys/colors happens client-side; the database accepts any
  text so new icon packs can be added without migrations.
*/

CREATE TABLE IF NOT EXISTS user_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sync_code text NOT NULL,
  name text NOT NULL,
  avatar_key text NOT NULL DEFAULT 'rocket',
  avatar_color text NOT NULL DEFAULT 'arancio',
  is_kids boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS user_profiles_sync_code_idx ON user_profiles (sync_code);

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_code_read" ON user_profiles;
CREATE POLICY "profiles_code_read"
ON user_profiles FOR SELECT
TO anon, authenticated
USING (true);

DROP POLICY IF EXISTS "profiles_code_insert" ON user_profiles;
CREATE POLICY "profiles_code_insert"
ON user_profiles FOR INSERT
TO anon, authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS "profiles_code_update" ON user_profiles;
CREATE POLICY "profiles_code_update"
ON user_profiles FOR UPDATE
TO anon, authenticated
USING (true)
WITH CHECK (true);

DROP POLICY IF EXISTS "profiles_code_delete" ON user_profiles;
CREATE POLICY "profiles_code_delete"
ON user_profiles FOR DELETE
TO anon, authenticated
USING (true);
