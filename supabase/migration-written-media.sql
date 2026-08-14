-- supabase/migration-written-media.sql
-- Run once in the Supabase SQL Editor.

create type written_media_category as enum ('book', 'manga', 'manhwa', 'webnovel');
create type written_media_status as enum ('reading', 'completed', 'plan_to_read');

create table written_media (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category written_media_category not null,
  scope show_scope not null,
  author text,
  cover_url text,
  genres text[],
  total_chapters int,
  current_chapter int,
  total_volumes int,
  current_volume int,
  total_pages int,
  current_page int,
  list_status written_media_status not null default 'plan_to_read',
  pinned boolean not null default false,
  tags text[],
  last_updated date,
  created_at timestamptz not null default now()
);

alter table written_media enable row level security;

create policy "written_media readable by authenticated" on written_media
  for select using (auth.role() = 'authenticated');

create policy "written_media writable by owner or together" on written_media
  for all using (
    auth.role() = 'authenticated'
    and (
      scope = 'together'
      or scope::text = (select lower(display_name) from profiles where id = auth.uid())
    )
  );

grant select, insert, update, delete on public.written_media to service_role, authenticated, anon;

-- Extend ratings to point at either a show or a written_media row.
alter table ratings add column id uuid default gen_random_uuid();
alter table ratings add column written_media_id uuid references written_media(id) on delete cascade;

alter table ratings drop constraint ratings_pkey;
alter table ratings alter column show_id drop not null;
update ratings set id = gen_random_uuid() where id is null;
alter table ratings alter column id set not null;
alter table ratings add primary key (id);

create unique index ratings_show_user_uniq
  on ratings (show_id, user_id) where show_id is not null;
create unique index ratings_written_media_user_uniq
  on ratings (written_media_id, user_id) where written_media_id is not null;

alter table ratings add constraint ratings_exactly_one_target
  check ((show_id is not null) <> (written_media_id is not null));
