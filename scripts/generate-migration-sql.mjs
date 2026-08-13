// scripts/generate-migration-sql.mjs
import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync(new URL('../data.json', import.meta.url)));

function sqlStr(v) {
  if (v === null || v === undefined) return 'null';
  return `'${String(v).replace(/'/g, "''")}'`;
}
function sqlArr(v) {
  if (!v || !v.length) return 'null';
  return `array[${v.map(sqlStr).join(',')}]`;
}
function sqlNum(v) {
  return v === null || v === undefined ? 'null' : String(v);
}
function sqlBool(v) {
  return v ? 'true' : 'false';
}

const schema = `
create type show_scope as enum ('karl', 'liisa', 'together');
create type list_status as enum ('watching', 'watchlist');

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null
);

create table shows (
  id text primary key,
  title text not null,
  category text not null,
  scope show_scope not null,
  poster_url text,
  studio text,
  genres text[],
  total_episodes int,
  total_seasons int,
  current_episode int,
  season_episode int,
  current_season int,
  runtime_minutes int,
  list_status list_status,
  in_tier_pool boolean not null default false,
  pinned boolean not null default false,
  tags text[],
  last_updated date,
  created_at timestamptz not null default now()
);

create table ratings (
  show_id text not null references shows(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  rating numeric(2,1),
  note text,
  updated_at timestamptz not null default now(),
  primary key (show_id, user_id)
);

alter table profiles enable row level security;
alter table shows enable row level security;
alter table ratings enable row level security;

create policy "profiles readable by authenticated" on profiles
  for select using (auth.role() = 'authenticated');

create policy "shows readable by authenticated" on shows
  for select using (auth.role() = 'authenticated');

create policy "shows writable by owner or together" on shows
  for all using (
    scope = 'together'
    or scope::text = (select lower(display_name) from profiles where id = auth.uid())
  );

create policy "ratings readable by authenticated" on ratings
  for select using (auth.role() = 'authenticated');

create policy "ratings writable by owner" on ratings
  for insert, update, delete using (user_id = auth.uid());
`.trim();

// Merge watching + watched + watchlist into one row set, keyed by id,
// mirroring the app's existing merge logic (a finished `watching` entry and
// its `watched` counterpart are the same show).
const rows = new Map();

function upsert(id, patch) {
  rows.set(id, { ...(rows.get(id) || {}), ...patch });
}

for (const s of data.watching ?? []) {
  upsert(s.id, {
    id: s.id, title: s.title, category: s.category ?? 'anime',
    poster_url: s.posterUrl, studio: s.studio, genres: s.genres,
    total_episodes: s.totalEpisodes, total_seasons: s.totalSeasons,
    current_episode: s.currentEpisode, season_episode: s.seasonEpisode,
    current_season: s.currentSeason, runtime_minutes: s.runtimeMinutes,
    list_status: 'watching', last_updated: s.lastUpdated,
  });
}
for (const s of data.watched ?? []) {
  upsert(s.id, {
    id: s.id, title: s.title, category: s.category ?? 'anime',
    poster_url: s.posterUrl, in_tier_pool: true,
    runtime_minutes: rows.get(s.id)?.runtime_minutes ?? s.runtimeMinutes,
  });
}
for (const s of data.watchlist ?? []) {
  upsert(s.id, { id: s.id, title: s.title, category: s.category ?? 'anime', list_status: 'watchlist' });
}

const inserts = [...rows.values()].map(r => `insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  ${sqlStr(r.id)}, ${sqlStr(r.title)}, ${sqlStr(r.category)}, 'karl',
  ${sqlStr(r.poster_url)}, ${sqlStr(r.studio)}, ${sqlArr(r.genres)},
  ${sqlNum(r.total_episodes)}, ${sqlNum(r.total_seasons)}, ${sqlNum(r.current_episode)},
  ${sqlNum(r.season_episode)}, ${sqlNum(r.current_season)}, ${sqlNum(r.runtime_minutes)},
  ${r.list_status ? sqlStr(r.list_status) : 'null'}, ${sqlBool(r.in_tier_pool ?? false)},
  ${sqlStr(r.last_updated)}
);`).join('\n');

console.log(schema + '\n\n-- Karl\'s existing shows\n' + inserts + '\n');
console.log(`-- Profiles: replace the two UUIDs below with the real auth.users ids
-- from Supabase Dashboard -> Authentication -> Users, after creating the
-- two invited users there.
-- insert into profiles (id, display_name) values ('<karl-uuid>', 'Karl');
-- insert into profiles (id, display_name) values ('<liisa-uuid>', 'Liisa');`);
