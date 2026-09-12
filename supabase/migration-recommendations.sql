-- supabase/migration-recommendations.sql
-- Run once in the Supabase SQL Editor.
--
-- Backs the Recommendations tab: caches computed anime/manga
-- recommendation lists per scope+category (cross-device, refreshed on a
-- throttle by the client) and tracks per-scope dismissals so a dismissed
-- title doesn't resurface on the next refresh.

create table recommendations_cache (
  scope show_scope not null,
  -- 'anime' caches against `shows` (category='anime'); 'manga' caches
  -- against `written_media` rows of EITHER category='manga' OR
  -- category='manhwa' -- both use AniList type MANGA, so they share one
  -- cache bucket and seed pool.
  category text not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (scope, category)
);

create table dismissed_recommendations (
  scope show_scope not null,
  -- AniList media id when available; falls back to "mal:<id>" or
  -- "title:<normalized title>" when a recommendation came from the Jikan
  -- fallback path (Jikan has no AniList id) -- see externalIdFor() in
  -- index.html, added in Task 5.
  external_id text not null,
  primary key (scope, external_id)
);

alter table recommendations_cache enable row level security;
alter table dismissed_recommendations enable row level security;

create policy "recommendations_cache readable by authenticated" on recommendations_cache
  for select using (auth.role() = 'authenticated');
create policy "recommendations_cache writable by owner or together" on recommendations_cache
  for all using (
    auth.role() = 'authenticated'
    and (scope = 'together' or scope::text = (select lower(display_name) from profiles where id = auth.uid()))
  );

create policy "dismissed_recommendations readable by authenticated" on dismissed_recommendations
  for select using (auth.role() = 'authenticated');
create policy "dismissed_recommendations writable by owner or together" on dismissed_recommendations
  for all using (
    auth.role() = 'authenticated'
    and (scope = 'together' or scope::text = (select lower(display_name) from profiles where id = auth.uid()))
  );

grant select, insert, update, delete on public.recommendations_cache, public.dismissed_recommendations
  to service_role, authenticated, anon;
