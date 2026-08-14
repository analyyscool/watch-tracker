-- supabase/migration-written-media-fix-indexes.sql
-- Run once in the Supabase SQL Editor, AFTER supabase/migration-written-media.sql
-- has already been applied live.
--
-- The original migration created ratings_show_user_uniq / ratings_written_media_user_uniq
-- as PARTIAL unique indexes (with a WHERE clause). Postgres's ON CONFLICT (col1, col2)
-- (no WHERE predicate) can't use a partial index as its arbiter, and PostgREST's
-- on_conflict query param has no way to express a predicate -- so every upsert from
-- setRating/setNote via the REST API (?on_conflict=show_id,user_id) failed with
-- 42P10. This replaces both partial indexes with full unique constraints, which are
-- valid ON CONFLICT arbiters and behave identically for this schema: Postgres treats
-- NULL as never-equal-to-NULL for uniqueness purposes, so unique (show_id, user_id)
-- is a no-op for written_media rating rows (where show_id is always NULL), exactly
-- matching the partial index's original intent.

drop index if exists ratings_show_user_uniq;
drop index if exists ratings_written_media_user_uniq;

alter table ratings add constraint ratings_show_user_uniq unique (show_id, user_id);
alter table ratings add constraint ratings_written_media_user_uniq unique (written_media_id, user_id);
