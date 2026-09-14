-- supabase/migration-calendar-cache.sql
-- Run once in the Supabase SQL Editor.
--
-- Backs the Calendar tab with a cross-device cache, same shape/pattern as
-- recommendations_cache (migration-recommendations.sql). Fixes a real bug:
-- the calendar previously cached each show's next-airing-episode result in
-- per-DEVICE localStorage only (`calendarShowCache`), so a device with no
-- prior local cache (a tablet opened for the first time, or after clearing
-- site data) would silently show FEWER entries than a device that already
-- had per-show data to fall back on when an individual AniList/TMDB call
-- failed -- no error, no indication anything was missing, just a quieter
-- calendar. Moving the final assembled entry list to a shared table means
-- every device reads the same last-known-good result instead of each one
-- independently reconstructing it from scratch with its own gaps.

create table calendar_cache (
  scope show_scope not null primary key,
  entries jsonb not null,
  updated_at timestamptz not null default now()
);

alter table calendar_cache enable row level security;

create policy "calendar_cache readable by authenticated" on calendar_cache
  for select using (auth.role() = 'authenticated');
create policy "calendar_cache writable by owner or together" on calendar_cache
  for all using (
    auth.role() = 'authenticated'
    and (scope = 'together' or scope::text = (select lower(display_name) from profiles where id = auth.uid()))
  );

grant select, insert, update, delete on public.calendar_cache to service_role, authenticated, anon;
