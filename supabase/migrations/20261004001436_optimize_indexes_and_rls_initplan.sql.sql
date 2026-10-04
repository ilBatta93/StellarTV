/*
# Optimize database performance (indexes + faster security checks)

1. Indexes
- `user_profiles.sync_code`: the app lists profiles by sync code, now indexed.
- `watch_history (user_id, last_watched_at)`: the app reads a user's history
  sorted by recency, now served by a single covering index.
2. Security (no behavior change)
- Rewrote the ownership policies on `watch_history` and `user_sync_data` so the
  current user's ID is looked up once per query instead of once per row.
  Same access rules, just faster at scale.
3. Notes
- Idempotent: uses IF NOT EXISTS / DROP POLICY IF EXISTS, safe to re-run.
- No data is created, changed, or deleted.
*/

CREATE INDEX IF NOT EXISTS idx_user_profiles_sync_code
  ON user_profiles (sync_code);

CREATE INDEX IF NOT EXISTS idx_watch_history_user_recent
  ON watch_history (user_id, last_watched_at DESC);

DROP POLICY IF EXISTS "Users read own history" ON watch_history;
CREATE POLICY "Users read own history"
ON watch_history FOR SELECT
TO authenticated
USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users add own history" ON watch_history;
CREATE POLICY "Users add own history"
ON watch_history FOR INSERT
TO authenticated
WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users update own history" ON watch_history;
CREATE POLICY "Users update own history"
ON watch_history FOR UPDATE
TO authenticated
USING ((select auth.uid()) = user_id)
WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users delete own history" ON watch_history;
CREATE POLICY "Users delete own history"
ON watch_history FOR DELETE
TO authenticated
USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "users_read_own_sync" ON user_sync_data;
CREATE POLICY "users_read_own_sync"
ON user_sync_data FOR SELECT
TO authenticated
USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "users_insert_own_sync" ON user_sync_data;
CREATE POLICY "users_insert_own_sync"
ON user_sync_data FOR INSERT
TO authenticated
WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "users_update_own_sync" ON user_sync_data;
CREATE POLICY "users_update_own_sync"
ON user_sync_data FOR UPDATE
TO authenticated
USING ((select auth.uid()) = user_id)
WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "users_delete_own_sync" ON user_sync_data;
CREATE POLICY "users_delete_own_sync"
ON user_sync_data FOR DELETE
TO authenticated
USING ((select auth.uid()) = user_id);
