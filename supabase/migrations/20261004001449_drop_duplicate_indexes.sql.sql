/*
# Remove duplicate indexes

1. Changes
- `user_profiles`: dropped `user_profiles_sync_code_idx`, kept
  `idx_user_profiles_sync_code` (identical copies; one is enough).
- `watch_history`: dropped `watch_history_user_recent_idx`, kept
  `idx_watch_history_user_recent` (identical copies; one is enough).
2. Notes
- Dropping an index never touches table data; queries use the remaining copy.
- Idempotent: uses IF EXISTS, safe to re-run.
*/

DROP INDEX IF EXISTS user_profiles_sync_code_idx;
DROP INDEX IF EXISTS watch_history_user_recent_idx;
