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

-- Karl's existing shows
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'samurai-champloo', 'Samurai Champloo', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1370/135212l.jpg', 'Manglobe', array['Action','Adventure','Comedy'],
  26, 1, 26,
  26, 1, null,
  'watching', true,
  '2026-07-01'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'nge', 'Neon Genesis Evangelion', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1314/108941l.jpg', 'Gainax', array['Avant Garde','Award Winning','Drama','Sci-Fi','Suspense'],
  26, 1, 4,
  4, 1, null,
  'watching', false,
  '2026-07-01'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'record-of-ragnarok', 'Record of Ragnarok', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1456/115123l.jpg', 'Graphinica', array['Action','Drama','Fantasy'],
  42, 3, 16,
  4, 2, null,
  'watching', false,
  '2026-07-01'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'witch-hat-atelier', 'Witch Hat Atelier', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1726/155542l.jpg', 'BUG FILMS', array['Fantasy'],
  13, 1, 13,
  13, 1, null,
  'watching', true,
  '2026-07-01'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'fire-force', 'Fire Force', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1664/103275l.jpg', 'David Production', array['Action','Fantasy','Sci-Fi'],
  73, 3, 30,
  6, 2, null,
  'watching', false,
  '2026-07-01'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'shangri-la-frontier', 'Shangri-La Frontier', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1500/139931l.jpg', 'C2C', array['Action','Adventure','Fantasy'],
  50, 2, 11,
  11, 1, null,
  'watching', false,
  '2026-07-01'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'rezero', 'Re:ZERO', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1522/128039l.jpg', 'White Fox', array['Drama','Fantasy','Suspense'],
  66, 4, 3,
  3, 1, null,
  'watching', false,
  '2026-07-01'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'spy-x-family', 'SPY x FAMILY', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1441/122795l.jpg', 'Wit Studio', array['Action','Award Winning','Comedy'],
  50, 3, 28,
  3, 2, null,
  'watching', false,
  '2026-07-01'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'apothecary-diaries', 'The Apothecary Diaries', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1708/138033l.jpg', 'OLM', array['Drama','Mystery'],
  48, 2, 6,
  6, 1, null,
  'watching', false,
  '2026-07-01'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'mr-robot', 'Mr. Robot', 'western', 'karl',
  'https://media.themoviedb.org/t/p/w300_and_h450_face/kv1nRqgebSsREnd7vdC2pSGjpLo.jpg', 'USA Network', array['Crime','Drama'],
  45, 4, 13,
  3, 2, 47,
  'watching', false,
  '2026-07-01'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'kaiji', 'Kaiji', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/12/80032l.jpg', 'Madhouse', array['Suspense'],
  52, 2, 10,
  10, 1, null,
  'watching', false,
  '2026-07-01'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'dragon-ball', 'Dragon Ball (Fan Cut)', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1887/92364l.jpg', 'Toei Animation', array['Action','Adventure','Comedy','Fantasy'],
  82, 1, 82,
  82, 1, null,
  'watching', true,
  '2026-07-31'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'dragon-ball-z-kai-recut', 'Dragon Ball Z Kai (Recut) Part 1', 'anime', 'karl',
  'https://media.themoviedb.org/t/p/w300_and_h450_face/ojsPI8fNwcecKLhVC4rB4ZZhFMc.jpg', 'Toei Animation', array['Action','Adventure','Comedy','Fantasy'],
  47, 1, 17,
  17, 1, null,
  'watching', false,
  '2026-08-12'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'loki', 'Loki', 'western', 'karl',
  'https://media.themoviedb.org/t/p/w300_and_h450_face/rX1wQMTKFqF0gvZyS0DDQqgnQPB.jpg', 'Disney+', array['Drama','Sci-Fi & Fantasy'],
  12, 2, 12,
  6, 2, 48,
  'watching', true,
  '2026-08-12'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'moriarty-the-patriot', 'Moriarty the Patriot', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1464/108330l.jpg', 'Production I.G', array['Mystery','Suspense'],
  24, 2, 24,
  24, 2, null,
  'watching', true,
  '2026-07-23'
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'attack-on-titan', 'Attack on Titan', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/10/47347l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'vinland-saga', 'Vinland Saga', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1500/103005l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'cowboy-bebop', 'Cowboy Bebop', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/4/19644l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'steins-gate', 'Steins;Gate', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1935/127974l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'demon-slayer', 'Demon Slayer: Kimetsu no Yaiba', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1286/99889l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'avatar-last-airbender', 'Avatar: The Last Airbender', 'western', 'karl',
  'https://media.themoviedb.org/t/p/w300_and_h450_face/yaGt4GIutpbXHsv48tWceWg6s56.jpg', null, null,
  null, null, null,
  null, null, 23,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'cyberpunk-edgerunners', 'Cyberpunk: Edgerunners', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1818/126435l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'jujutsu-kaisen', 'Jujutsu Kaisen', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1171/109222l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'mob-psycho-100', 'Mob Psycho 100', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/8/80356l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'frieren', 'Frieren: Beyond Journey''s End', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1015/138006l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'eighty-six', '86', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1987/117507l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'oregairu-snafu', 'My Teen Romantic Comedy SNAFU', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1786/120117l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'hunter-x-hunter-2011', 'Hunter × Hunter (2011)', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1337/99013l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'haikyuu-dumpster-battle', 'Haikyu!! The Dumpster Battle', 'movie', 'karl',
  'https://cdn.myanimelist.net/images/anime/1665/140360l.jpg', null, null,
  null, null, null,
  null, null, 85,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'code-geass-resurrection', 'Code Geass: Lelouch of the Re;Surrection', 'movie', 'karl',
  'https://cdn.myanimelist.net/images/anime/1274/113436l.jpg', null, null,
  null, null, null,
  null, null, 112,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'cheat-skill-another-world', 'I Got a Cheat Skill in Another World and Became Unrivaled in the Real World, Too', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1316/134327l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'chainsaw-man', 'Chainsaw Man', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1806/126216l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'your-name', 'Your Name.', 'movie', 'karl',
  'https://cdn.myanimelist.net/images/anime/5/87048l.jpg', null, null,
  null, null, null,
  null, null, 106,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'haikyuu', 'Haikyuu!!', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/7/76014l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'solo-leveling', 'Solo Leveling', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1801/142390l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'one-punch-man', 'One Punch Man', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/12/76049l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'berserk-1997', 'Berserk (1997)', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1384/119988l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'trigun', 'Trigun', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1130/120002l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'death-note', 'Death Note', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1079/138100l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'code-geass-rebellion', 'Code Geass: Lelouch of the Rebellion', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1032/135088l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'jojo-bizarre-adventure', 'JoJo''s Bizarre Adventure', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/3/40409l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'blue-lock', 'Blue Lock', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1258/126929l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'one-piece', 'One Piece', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1244/138851l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'tokyo-ghoul', 'Tokyo Ghoul', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1498/134443l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'bleach', 'Bleach', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1541/147774l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'bleach-tybw', 'Bleach: Thousand-Year Blood War', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1908/135431l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'lazarus', 'Lazarus', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1098/150300l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'made-in-abyss', 'Made in Abyss', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/6/86733l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'a-silent-voice', 'A Silent Voice', 'movie', 'karl',
  'https://cdn.myanimelist.net/images/anime/1122/96435l.jpg', null, null,
  null, null, null,
  null, null, 130,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'sakamoto-days', 'Sakamoto Days', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1026/146459l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'grand-blue', 'Grand Blue Dreaming', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1302/94882l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'promised-neverland', 'The Promised Neverland', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1830/118780l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'gurren-lagann', 'Gurren Lagann', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/4/5123l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'made-in-abyss-dawn', 'Made in Abyss: Dawn of the Deep Soul', 'movie', 'karl',
  'https://cdn.myanimelist.net/images/anime/1803/117183l.jpg', null, null,
  null, null, null,
  null, null, 105,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'takopis-original-sin', 'Takopi''s Original Sin', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1182/149879l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'devilman-crybaby', 'Devilman: Crybaby', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/2/89973l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'the-fable', 'The Fable', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1254/141155l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'baccano', 'Baccano!', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/3/14547l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'pluto', 'Pluto', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1021/138568l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'flcl', 'FLCL', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/7/77356l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'to-be-hero-x', 'To Be Hero X', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1492/150628l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'fragrant-flower-dignity', 'The Fragrant Flower Blooms with Dignity', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1744/150433l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'dandadan', 'Dandadan', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1584/143719l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'kaiju-no-8', 'Kaiju No. 8', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1370/140362l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'demon-slayer-infinity-castle', 'Demon Slayer: Infinity Castle', 'movie', 'karl',
  'https://cdn.myanimelist.net/images/anime/1681/148216l.jpg', null, null,
  null, null, null,
  null, null, 155,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'odd-taxi', 'Odd Taxi', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1981/113348l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'suzume', 'Suzume', 'movie', 'karl',
  'https://cdn.myanimelist.net/images/anime/1598/128450l.jpg', null, null,
  null, null, null,
  null, null, 122,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'my-hero-academia', 'My Hero Academia', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/10/78745l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'kurokos-basketball', 'Kuroko''s Basketball', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/11/50453l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'kurokos-basketball-last-game', 'Kuroko''s Basketball: Last Game', 'movie', 'karl',
  'https://cdn.myanimelist.net/images/anime/2/83106l.jpg', null, null,
  null, null, null,
  null, null, 90,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'zom-100', 'Zom 100: Bucket List of the Dead', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1384/136408l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'cote', 'Classroom of the Elite', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/5/86830l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'chainsaw-man-reze-arc', 'Chainsaw Man – The Movie: Reze Arc', 'movie', 'karl',
  'https://cdn.myanimelist.net/images/anime/1763/150638l.jpg', null, null,
  null, null, null,
  null, null, 100,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'hyakuemu-100-meters', '100 Meters', 'movie', 'karl',
  'https://cdn.myanimelist.net/images/anime/1259/151080l.jpg', null, null,
  null, null, null,
  null, null, 106,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'mushoku-tensei', 'Mushoku Tensei: Jobless Reincarnation', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1530/117776l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'hells-paradise', 'Hell''s Paradise', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1075/131925l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'parasyte-the-maxim', 'Parasyte: The Maxim', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/3/73178l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'jujutsu-kaisen-0', 'Jujutsu Kaisen 0', 'movie', 'karl',
  'https://cdn.myanimelist.net/images/anime/1121/119044l.jpg', null, null,
  null, null, null,
  null, null, 105,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'great-pretender', 'Great Pretender', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1418/107954l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'redline', 'Redline', 'movie', 'karl',
  'https://cdn.myanimelist.net/images/anime/12/28553l.jpg', null, null,
  null, null, null,
  null, null, 102,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'naruto-shippuden', 'Naruto: Shippuden', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1565/111305l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'naruto', 'Naruto', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1141/142503l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'summer-time-rendering', 'Summer Time Rendering', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/1120/120796l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'golden-boy', 'Golden Boy', 'anime', 'karl',
  'https://cdn.myanimelist.net/images/anime/3/62867l.jpg', null, null,
  null, null, null,
  null, null, null,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'ghost-in-the-shell-1995', 'Ghost in the Shell (1995)', 'movie', 'karl',
  'https://cdn.myanimelist.net/images/anime/10/82594l.jpg', null, null,
  null, null, null,
  null, null, 82,
  null, true,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'fmab', 'Fullmetal Alchemist: Brotherhood', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'link-click', 'Link Click', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'kingdom', 'Kingdom', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'logh', 'Legend of the Galactic Heroes', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'monster', 'Monster', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'golden-kamuy', 'Golden Kamuy', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'orb', 'Orb: On the Movements of the Earth', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'nippon-sangoku', 'Nippon Sangoku', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'ranking-of-kings', 'Ranking of Kings', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'gachiakuta', 'Gachiakuta', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'dororo', 'Dororo', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'fate-zero', 'Fate/Zero', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'banana-fish', 'Banana Fish', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'psycho-pass', 'Psycho-Pass', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'rakugo', 'Showa Genroku Rakugo Shinju', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'sentenced-hero', 'Sentenced to Be a Hero', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'vampire-hunter-d', 'Vampire Hunter D', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);
insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  'march-lion', 'March Comes in Like a Lion', 'anime', 'karl',
  null, null, null,
  null, null, null,
  null, null, null,
  'watchlist', false,
  null
);

-- Profiles: replace the two UUIDs below with the real auth.users ids
-- from Supabase Dashboard -> Authentication -> Users, after creating the
-- two invited users there.
-- insert into profiles (id, display_name) values ('<karl-uuid>', 'Karl');
-- insert into profiles (id, display_name) values ('<liisa-uuid>', 'Liisa');
