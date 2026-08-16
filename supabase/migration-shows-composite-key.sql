-- supabase/migration-shows-composite-key.sql
-- Run once in the Supabase SQL Editor.
--
-- Fixes shows.id being a bare `text primary key`, which collides if the
-- same title (same slug) is logged under two scopes (e.g. Karl already has
-- `suzume` personally and later wants to log it again under Together).
-- Makes the primary key (id, scope) instead. Since ratings.show_id has a
-- real FK into shows(id), and a compound PK requires a compound FK,
-- ratings needs a scope column added and its FK/uniqueness constraint
-- updated to match.

-- 1. Add scope to ratings, backfilled from the still-globally-unique
--    shows.id (this must run BEFORE the primary key changes below).
alter table ratings add column scope show_scope;
update ratings r set scope = s.scope from shows s where r.show_id = s.id;

-- 2. Drop the old single-column FK and uniqueness constraint on ratings.
alter table ratings drop constraint if exists ratings_show_id_fkey;
alter table ratings drop constraint if exists ratings_show_user_uniq;

-- 3. Change shows' primary key from (id) to (id, scope).
alter table shows drop constraint shows_pkey;
alter table shows add primary key (id, scope);

-- 4. Re-add ratings' FK/uniqueness as compound. FK is automatically
--    satisfied when either referencing column is null, which is exactly
--    the case for written-media-only ratings (show_id and scope both
--    null) — no explicit null handling needed.
alter table ratings add constraint ratings_show_scope_fkey
  foreign key (show_id, scope) references shows(id, scope) on delete cascade;
alter table ratings add constraint ratings_show_scope_user_uniq
  unique (show_id, scope, user_id);
