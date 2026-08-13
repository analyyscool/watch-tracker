# Multi-User Supabase Backend — Design Spec

Date: 2026-08-14
Status: Approved by Karl, pending implementation plan

## Context

Watch Tracker is currently a single static `index.html` + `data.json`, with all
writes (progress bumps, marking shows finished, adding new shows) mediated by
Claude editing `data.json` and committing. Ratings/notes live in
`localStorage` and sync to `data.json` only via a manual "export → paste to
Claude → merge" flow.

This was originally scoped as a narrow backend migration (move progress-bump
and mark-finished to real in-page Supabase writes, optionally also ratings/
notes) for a single user (Karl). Mid-design, Karl's partner Liisa reviewed the
app and asked for her own space in it — her own watching list/tier
list/ratings/stats, a shared "watched together" list, a mood-tagged shared
watchlist, and a Letterboxd ratings import. This spec supersedes the
single-user version and covers the full multi-user shape.

## Goals

- Real accounts for Karl and Liisa (room to add a third later), gated by
  Supabase Auth magic-link sign-in — no public sign-up.
- Each person gets their own personal Watching/Tier List/Ratings/Stats,
  private to them (viewable by the other, writable only by the owner).
- A shared **Together** scope — a joint watched/watching list, tier list,
  ratings, and stats, writable by either account.
- A mood-tagged shared watchlist (freeform tags like "brainrot", applied
  mainly to the Together watchlist).
- A one-time (repeatable) Letterboxd CSV import so Liisa can bring in her
  existing ratings.
- Progress bump, mark-finished, and add-show all become real writes instead
  of Claude editing `data.json` — "add a new show" stays Claude-mediated (it
  benefits from judgment: remake/sequel disambiguation, right poster) but
  writes directly to Supabase instead of to a file.
- Retire `data.json` and the ratings/notes export-and-paste flow entirely
  once migration is verified.

## Non-goals

- No public/anonymous access — this is not a multi-tenant SaaS product, just
  two (soon maybe three) named people.
- No real-time collaboration/live cursors — a manual refresh (or the existing
  refresh-on-focus behavior) after the other person edits is fine.
- No mobile app, no push notifications.

## Accounts & Auth

- Supabase Auth, **magic link** (passwordless OTP email) sign-in.
- Public sign-up disabled in the Supabase dashboard. Karl manually creates
  exactly the auth users needed (starting with Karl + Liisa) via the
  dashboard's "Invite user" flow.
- A `profiles` table mirrors `auth.users` 1:1, holding just a display name:

```sql
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null
);
```

- The app's UI needs a signed-in session to do anything — `SELECT` on data
  tables requires `authenticated` role (not public), since personal data
  (Liisa's list) is visible to the other account, not the whole internet.
- Session persists in the browser via `supabase-js`'s default localStorage
  persistence + auto token refresh — sign-in should be a rare event per
  device, not a per-visit hassle.

## Data model

One flat `shows` table (as originally designed for the single-user version),
plus a `scope` column and a separate `ratings` table.

```sql
create type show_scope as enum ('karl', 'liisa', 'together');
create type list_status as enum ('watching', 'watchlist');

create table shows (
  id text primary key,                    -- slug, e.g. 'samurai-champloo'
  title text not null,
  category text not null,                 -- 'anime' | 'western' | 'movie'
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
  list_status list_status,                -- null = watched-only / tier-pool-only
  in_tier_pool boolean not null default false,
  pinned boolean not null default false,
  tags text[],                            -- mood tags, mainly for together watchlist
  last_updated date,
  created_at timestamptz not null default now()
);

create table ratings (
  show_id text not null references shows(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  rating numeric(2,1),                    -- 0.0–5.0, 0.5 steps
  note text,
  updated_at timestamptz not null default now(),
  primary key (show_id, user_id)
);
```

Notes on the mapping from today's behavior:

- `list_status = 'watching'` + `current_episode >= total_episodes` → today's
  "Completed" section (same rule as now, per scope).
- `in_tier_pool = true` → appears in that scope's Tier List / Ratings tab
  (today's `watched` array membership), independent of `list_status` — matches
  how older watched-only entries with no episode data behave today.
- `pinned` moves server-side (was `localStorage` before) since it's now
  meaningful per-scope data, not just a device-local UI preference — this is
  a deliberate small change from the original single-user plan, where pin
  state was going to stay local. Worth flagging: this means unpinning/pinning
  needs a write, gated by the same ownership rule as everything else.
- Sort/filter *selections* (which dropdown option is currently chosen) stay
  in `localStorage` — those are per-device UI state, not data.
- `ratings.rating`/`ratings.note` are keyed by `(show_id, user_id)`, so a
  Together show can carry two independent ratings (Karl's and Liisa's) side
  by side, while a personal show only ever has one row (its owner's).

## Row Level Security

```sql
alter table shows enable row level security;
alter table ratings enable row level security;
alter table profiles enable row level security;

-- profiles: any authenticated user can read all profiles (for display names);
-- no one writes to it from the client (Karl adds rows manually via SQL editor
-- when a new person joins).
create policy "profiles readable by authenticated" on profiles
  for select using (auth.role() = 'authenticated');

-- shows: any authenticated user can read everything (Karl can see Liisa's
-- personal list and vice versa, plus Together).
create policy "shows readable by authenticated" on shows
  for select using (auth.role() = 'authenticated');

-- shows: writable if it's a Together row, or if it's your own scope.
-- Scope-to-user mapping is by profiles.display_name matching the enum label
-- (lowercase) — simplest option for exactly two-three fixed people; revisit
-- if this ever needs to generalize beyond a handful of named accounts.
create policy "shows writable by owner or together" on shows
  for all using (
    scope = 'together'
    or scope::text = (select lower(display_name) from profiles where id = auth.uid())
  );

-- ratings: readable by any authenticated user (so you can see each other's
-- ratings on Together shows); writable only for your own rows.
create policy "ratings readable by authenticated" on ratings
  for select using (auth.role() = 'authenticated');

create policy "ratings writable by owner" on ratings
  for insert, update, delete using (user_id = auth.uid());
```

## UI changes

- **Scope switcher**: a persistent Karl / Liisa / Together control (styled
  like the existing category-toggle pattern) sitting above the four main tabs
  (Watching, Tier List, Ratings, Stats). Changing it re-scopes all four tabs'
  queries — `WHERE scope = :selected`. Defaults to your own scope after sign-in.
- Existing category sub-tabs (Anime/Western/Movies) inside Tier List and
  Ratings stay as a second-level filter, unchanged in behavior — just now
  filtering an already scope-filtered list.
- **Sign-in**: a small header control. Signed out → "Sign in" opens an email
  prompt, calls `supabase.auth.signInWithOtp`, shows "check your email."
  Signed in → shows the display name + "Sign out."
- **Progress bump / mark-finished**: real controls on Watching cards — an
  episode-number stepper (or direct input) that writes `current_episode`,
  `season_episode`, `current_season`, `last_updated` on change, and a "Mark
  Finished" button that sets `current_episode = total_episodes` (and
  `current_season = total_seasons`) plus `in_tier_pool = true`. Both disabled
  when viewing a scope you can't write to (i.e., someone else's personal list).
- **Ratings/notes**: star clicks and note-modal saves become direct
  `upsert` calls against `ratings` keyed to the signed-in user — no more
  "Copy Ratings & Notes" button, no more unsynced-count badge.
- **Watchlist mood tags**: a tag-pill filter bar above the watchlist section;
  adding a show to the watchlist gets an optional freeform tag input.
- **Add Show**: stays Claude-mediated. The existing "+ Add Show" modal's copy
  updates to say Claude will ask which scope (yours / Liisa's / Together)
  before adding it — Claude then inserts the row directly into Supabase via
  the service-role key (see below), no `data.json` edit, no commit needed for
  that action specifically.

## Claude-mediated writes (Add Show)

- A `service_role` key (bypasses RLS entirely) is generated in the Supabase
  dashboard and stored in a **gitignored local file** on this machine (e.g.
  `.supabase-service-key`, added to `.gitignore`) — never embedded in
  `index.html`, never committed.
- Adding a show: Claude looks up episode/poster/genre data as today (Jikan/
  TMDB), asks which scope it belongs to if not obvious from context, then
  inserts the row via a `curl` call to the Supabase REST endpoint using the
  service-role key.

## Letterboxd import (phase 1)

- Liisa exports her Letterboxd data via **Settings → Import & Export →
  Export** (a zip containing `ratings.csv`, `watched.csv`, etc.).
- One-time import path: Liisa sends Claude the exported CSV(s); Claude
  matches each entry to an existing `shows` row by title (fuzzy match,
  flagging ambiguous matches for Liisa to confirm) or creates a new `movie`-
  category row if it doesn't exist yet (Letterboxd is predominantly movies),
  then upserts a `ratings` row scoped to Liisa's `user_id` via the
  service-role key — same mechanism as Add Show. Ratings are on Letterboxd's
  0.5–5 star scale, matching this app's rating scale exactly, so no
  conversion needed.
- This is a manual, Claude-run one-off script (not a button in the UI) —
  re-run whenever Liisa wants to bring in more Letterboxd history.

## Migration plan

1. Karl creates the Supabase project (done) and the two auth users
   (Karl, Liisa) via the dashboard.
2. Run one SQL script (generated by Claude from the current `data.json`) in
   the Supabase SQL Editor: creates the enums/tables, enables RLS, adds the
   policies above, inserts the `profiles` rows, and inserts Karl's ~90
   existing shows as `scope = 'karl'`. Liisa's and Together's scopes start
   empty.
3. Wire `index.html` to `supabase-js` (loaded via CDN script tag — no build
   step needed), replacing the three `fetch('data.json')` call sites with
   Supabase queries, adding the scope switcher, sign-in control, and the
   direct-write UI described above.
4. Verify the full flow live (sign in as Karl, confirm all ~90 shows render
   correctly across Watching/Tier List/Ratings/Stats, bump progress, mark a
   show finished, rate/note a show, add a show via Claude, switch to Liisa's
   empty scope, switch to Together).
5. Once verified, delete `data.json` from the repo and gut the now-obsolete
   `CLAUDE.md` sections (auto-commit-after-data.json-edit, the ratings-export-
   paste rule), replacing them with the new direct-write / scope-aware rules.

## Open risks / things to watch

- The `display_name`-to-`scope` matching in the write RLS policy
  (`lower(display_name) = scope::text`) is a simple hack that works for
  exactly the "karl"/"liisa" pair — if a third person joins with a scope
  that isn't just their own name (unlikely, but noting it), this policy
  needs a real mapping table instead of a name match.
- Fuzzy title-matching for the Letterboxd import can misfire on shows with
  multiple adaptations/versions (same class of bug hit during the MAL-score
  season, per project history) — Claude should flag uncertain matches for
  Liisa to confirm rather than guessing silently.
