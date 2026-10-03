/*
# Cloud watch history

1. New Tables
- `watch_history`: one row per user per watched item (live channel, movie or series).
  - `id` (uuid, primary key)
  - `user_id` (uuid, owner, defaults to the signed-in user, removed with the account)
  - `content_id` (text, channel/film id from the user's IPTV playlist)
  - `content_type` (text, one of live, movie, series)
  - `title` (text, display title)
  - `poster_url` (text, poster/logo image)
  - `group_name` (text, playlist category shown as subtitle)
  - `position_seconds` (integer, last playback position in seconds)
  - `duration_seconds` (integer, total length in seconds when known)
  - `last_watched_at` (timestamptz, last time the item was started or played)
  - `created_at` (timestamptz)
  - Unique on (`user_id`, `content_id`) so re-watching updates the same row.

2. Security
- RLS enabled. Four owner-only policies (select/insert/update/delete) for authenticated users: everyone sees and changes only their own history.

3. Notes
1. Stream URLs are intentionally NOT stored: Xtream links embed the provider's username and password. The app replays items by matching `content_id` against the loaded playlist.
2. Index on (`user_id`, `last_watched_at` desc) for the "most recent first" list.
*/

CREATE TABLE IF NOT EXISTS watch_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  content_id text NOT NULL CHECK (char_length(content_id) BETWEEN 1 AND 512),
  content_type text NOT NULL CHECK (content_type IN ('live', 'movie', 'series')),
  title text NOT NULL DEFAULT '' CHECK (char_length(title) <= 500),
  poster_url text NOT NULL DEFAULT '' CHECK (char_length(poster_url) <= 2048),
  group_name text NOT NULL DEFAULT '' CHECK (char_length(group_name) <= 300),
  position_seconds integer NOT NULL DEFAULT 0 CHECK (position_seconds >= 0),
  duration_seconds integer NOT NULL DEFAULT 0 CHECK (duration_seconds >= 0),
  last_watched_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, content_id)
);

CREATE INDEX IF NOT EXISTS watch_history_user_recent_idx
  ON watch_history (user_id, last_watched_at DESC);

ALTER TABLE watch_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own history" ON watch_history;
CREATE POLICY "Users read own history" ON watch_history FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users add own history" ON watch_history;
CREATE POLICY "Users add own history" ON watch_history FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users update own history" ON watch_history;
CREATE POLICY "Users update own history" ON watch_history FOR UPDATE
  TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users delete own history" ON watch_history;
CREATE POLICY "Users delete own history" ON watch_history FOR DELETE
  TO authenticated USING (auth.uid() = user_id);
