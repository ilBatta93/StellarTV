/*
# Enable realtime sync for watch history

1. Changes
- Adds `watch_history` to the `supabase_realtime` publication so every device signed in
  with the same account receives inserts, updates and deletes instantly.
- Sets REPLICA IDENTITY FULL on `watch_history` so delete events carry the removed row's
  `user_id` and `content_id`, allowing per-user filtering and removal on other devices.

2. Security
- No policy changes. Realtime respects the existing owner-only SELECT policy, so a user only
  receives changes for their own rows.

3. Notes
1. Idempotent: the table is only added to the publication if not already present.
2. No data is modified.
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'watch_history'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.watch_history;
  END IF;
END $$;

ALTER TABLE public.watch_history REPLICA IDENTITY FULL;