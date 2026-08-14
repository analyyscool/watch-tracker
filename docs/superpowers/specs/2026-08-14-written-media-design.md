# Written Media Tracking (Books/Manga/Manhwa/Webnovels) — Design Spec

Date: 2026-08-14
Status: Approved by Karl, pending implementation plan

## Context

Watch Tracker currently tracks only episodic video content (`shows`: anime,
western, movie) across four tabs — Watching, Tier List, Ratings, Stats — all
backed by the multi-user Supabase setup (see
`2026-08-14-multiuser-supabase-backend-design.md`). Karl wants to add a
parallel section for reading: books, manga, manhwa, and webnovels. This was
flagged in `todo.md` as needing its own design pass rather than a quick
bolt-on, because reading content's natural progress unit (pages/chapters,
optionally volumes) doesn't map cleanly onto `shows`' episode/season columns.

## Goals

- Track reading progress (currently-reading, completed, plan-to-read) for
  books, manga, manhwa, and webnovels, per the same Karl/Liisa/Together scope
  model already in place for shows.
- A new "Reading" tab, structurally parallel to Watching: currently-reading
  list with progress controls, a completed list, and a to-read quick-add list.
- Progress controls that fit the actual unit — a chapter stepper for
  manga/manhwa/webnovels (mirrors the anime episode stepper), a direct
  page-number input for books (a stepper doesn't make sense for books).
- Pinning parity with Watching (max 5 pinned, sorts to top), same mechanism.
- Ratings/notes support from day one, even without a dedicated UI tab for it
  yet — reusing the existing `ratings` table so the data model doesn't need
  to change again once a Reading sub-tab is added to Ratings/Tier List later.
- Add-entry stays Claude-mediated, same rationale as Add Show (judgment call
  on edition/volume-count disambiguation) — manga/manhwa looked up via Jikan
  when available (same API already used for anime), books/webnovels/
  manhwa-not-on-MAL entered manually.

## Non-goals (explicitly deferred)

- No Tier List sub-tab, no Ratings-tab UI, no Stats-tab breakdown for reading
  content this round. The `ratings` table changes support this later without
  another migration, but the UI for it is a follow-up.
- No self-serve add-entry form (matches the existing decision to keep Add
  Show Claude-mediated — extended to written media for the same reason).
- No changes to the two already-deferred schema gaps on `shows`
  (`id`/scope collision, Together tier list not cross-device-shared) — out of
  scope for this feature.

## Data model

A new `written_media` table, separate from `shows` — different content
family, different progress units, kept clean rather than bolting nullable
page/chapter columns onto the episode-shaped `shows` table.

```sql
create type written_media_category as enum ('book', 'manga', 'manhwa', 'webnovel');
create type written_media_status as enum ('reading', 'completed', 'plan_to_read');

create table written_media (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category written_media_category not null,
  scope show_scope not null,              -- reuses the existing karl/liisa/together enum
  author text,
  cover_url text,
  genres text[],
  total_chapters int,                     -- manga/manhwa/webnovel
  current_chapter int,
  total_volumes int,                      -- manga/manhwa only, nullable
  current_volume int,
  total_pages int,                        -- books
  current_page int,
  list_status written_media_status not null default 'plan_to_read',
  pinned boolean not null default false,
  tags text[],                            -- mirrors shows.tags (mood tags on to-read list)
  last_updated date,
  created_at timestamptz not null default now()
);
```

`ratings` is extended to cover both content types via a nullable second FK
rather than a parallel ratings table, since a duplicate table would just mean
duplicating every UI/query path that touches ratings later:

```sql
alter table ratings
  add column id uuid default gen_random_uuid(),
  add column written_media_id uuid references written_media(id) on delete cascade;

-- Drop the old (show_id, user_id) primary key before dropping NOT NULL on
-- show_id — Postgres won't allow dropping NOT NULL on a column that's still
-- part of the primary key. Then make id the primary key instead, replacing
-- the old one with two partial unique indexes so each user has at most one
-- rating per show OR per written_media item, never both null/both set.
alter table ratings drop constraint ratings_pkey;
alter table ratings alter column show_id drop not null;
alter table ratings add primary key (id);

alter table ratings add constraint ratings_show_user_uniq unique (show_id, user_id);
alter table ratings add constraint ratings_written_media_user_uniq unique (written_media_id, user_id);

alter table ratings add constraint ratings_exactly_one_target
  check ((show_id is not null) <> (written_media_id is not null));
```

Notes on the mapping:

- `list_status = 'reading'` drives the Currently Reading section;
  `'completed'` drives the Completed section; `'plan_to_read'` drives the
  to-read quick-add list — same three-state shape as `shows.list_status`
  today (`watching`/`watchlist`, plus the implicit completed state derived
  from progress).
- Unlike `shows`, "completed" here is a first-class status rather than
  derived from `current_episode >= total_episodes`, since page/chapter counts
  are sometimes unknown up front for ongoing manga/webnovels — completion
  should be an explicit action (a "Mark Finished" click), not inferred.
- `total_volumes`/`current_volume` stay null for books and most webnovels
  (chapter-only works); `total_pages`/`current_page` stay null for
  manga/manhwa/webnovels.

## Row Level Security

Mirrors `shows` exactly:

```sql
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
```

`ratings` policies are unchanged — they already gate on `user_id = auth.uid()`
regardless of which FK (show or written_media) the row points to.

## UI changes

- **New "Reading" tab**, 5th tab alongside Watching/Tier List/Ratings/Stats.
  Same scope switcher above it, same sort/filter bar shape (genre, category,
  last-updated) as Watching.
- **Currently Reading section**: cards showing title, author, category badge,
  cover, and progress —
  - Manga/manhwa/webnovel: `−`/`+` chapter stepper (same component as the
    anime episode stepper), writes `current_chapter`, `last_updated`.
  - Books: a direct numeric input for `current_page` (type a number, save on
    blur/Enter) — no stepper, since nobody bumps a 300-page book one page at
    a time.
  - "Mark Finished" button sets progress to the total and `list_status =
    'completed'`.
  - Pin/unpin button, same 5-max-pinned logic already built for Watching,
    reused against `written_media.pinned`.
- **Completed section**: same card shape as Watching's Completed, no
  progress controls, note-icon affordance (writes to `ratings` via
  `written_media_id`).
- **To Read section**: quick-add list mirroring today's watchlist pattern —
  title + optional tags, click to move into Currently Reading
  (`list_status: 'plan_to_read' → 'reading'`).
- **Add entry**: a "+ Add Book/Manga" button opens a modal with the same
  copy pattern as "+ Add Show" — tells the user to ask Claude, which scope,
  Claude looks up the data and inserts directly.

## Claude-mediated writes (Add Book/Manga)

- Reuses `scripts/supabase-write.mjs` unchanged — it's already generic on
  table name, so `node scripts/supabase-write.mjs written_media '[...]'`
  works with no script changes.
- `CLAUDE.md` gets a new "Adding a book/manga/manhwa/webnovel" section:
  manga (and manhwa, when present on MAL) looked up via Jikan the same way
  as anime; manhwa not on MAL, webnovels, and books are manual entry — Claude
  asks the user for author, chapter/page count, and cover art if it can't be
  found some other way (e.g. Google Books for books, if that turns out to be
  useful — not committed to here, manual entry is the guaranteed fallback).

## Migration plan

1. Generate and run one SQL migration: create the two new enums, the
   `written_media` table, RLS policies, and the `ratings` table alteration
   above.
2. Add the Reading tab UI to `index.html`: tab button, currently-reading/
   completed/to-read sections, chapter stepper + page input components,
   pin logic reuse, add-entry modal.
3. Update `CLAUDE.md` with the new add-flow section.
4. Verify live: add a manga (Jikan lookup), add a book (manual entry), bump
   chapter progress, set page progress directly, mark one finished, pin/
   unpin, rate + note an entry, switch scopes (Karl/Liisa/Together) and
   confirm the write-permission gate matches the shows behavior.

## Open risks / things to watch

- The `ratings` table's primary-key change (composite → surrogate `id` with
  two partial unique indexes) touches existing data and existing query
  patterns (`fetchShows`'s `s.ratings.find(r => r.user_id === ...)` join)
  — needs care in the implementation plan to confirm nothing that reads
  `ratings` by the old assumptions breaks.
- Jikan's manga coverage is solid for manga but spotty for manhwa (Korean
  webtoons often aren't cleanly indexed under MAL's "manga" type) — expect
  manual entry to be the common path for manhwa in practice, not just a
  fallback.
