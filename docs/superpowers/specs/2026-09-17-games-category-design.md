# Video Games Category — Design Spec

Date: 2026-09-17
Status: Approved by Karl, pending implementation plan

## Context

The app currently tracks two content types — `shows` (anime/western/movies)
and `written_media` (books/manga/manhwa/webnovels) — each with its own table,
its own scope model (karl/liisa/together), progress tracking, a Ratings tab,
and (for shows only) a drag-and-drop Tier List. Karl wants a third content
type for video games, with equivalent features.

Games don't have a natural progress counter the way episodes/chapters do, so
this spec adapts the progress model rather than reusing episode/chapter
fields verbatim. Everything else (scope model, ratings, tier list, the
Together→Personal mirror from the companion spec written the same day —
`2026-09-17-together-personal-rating-mirror-design.md`) is a direct reuse of
existing patterns.

## Goals

- A new `games` table, scoped like `shows` (karl/liisa/together), with a
  composite `(id, scope)` primary key sharing one slug `id` across a title's
  scope copies — same shape as `shows`, and the precondition for the
  Together→Personal rating mirror to extend to games with no new mechanism.
- Status-based progress (Backlog / Playing / Completed / Dropped) plus an
  optional, manually-updated `hours_played` number.
- A new top-level **Games** tab: Backlog / Playing / Completed sub-views,
  full parity with shows' Tier List and Ratings tabs.
- Cover art / metadata lookup via RAWG.io on add, with manual entry as a
  fallback, matching the existing Open Library/AniList add-flow pattern.
- A Games section on the Stats tab: total hours played, completed count,
  backlog size.

## Non-goals

- No multi-platform tracking — one `platform` text field per entry, same
  granularity as `runtime_minutes`/`studio` elsewhere (describes *your copy*
  of it, not every platform the game ships on).
- No IGDB integration in this pass — noted as a possible future upgrade if
  RAWG's data proves too thin for a given title, not built now.
- No achievement/completion-percentage tracking beyond hours played.

## Schema

```sql
create table games (
  id text not null,
  scope text not null check (scope in ('karl', 'liisa', 'together')),
  title text not null,
  platform text,
  developer text,
  genres text[],
  cover_url text,
  release_year int,
  list_status text check (list_status in ('backlog', 'playing', 'completed', 'dropped')),
  hours_played numeric,
  tier text,
  rank int,
  in_tier_pool boolean not null default false,
  pinned boolean not null default false,
  tags text[],
  last_updated date,
  created_at timestamptz not null default now(),
  primary key (id, scope)
);
```

Same RLS shape as `shows`: each personal scope is writable only by its owner,
readable by both; `together` is writable by either.

### Ratings

Reuse the existing `ratings` table rather than a new one — add a nullable
`game_id` column alongside the existing `show_id`/`written_media_id`, with a
unique constraint on `(game_id, scope, user_id)` mirroring `shows`' own
`(show_id, scope, user_id)`. `setRating`/`setNote`/`renderStars`/tier-list
drag logic all already branch on a `kind` parameter (`'show'` vs `'media'`);
this adds a third kind, `'game'`, following the exact same branches — no new
rating UI component.

`syncRatingToSiblingScope` and the two Together↔Personal mirror functions
from the companion spec both extend to games by adding a `games` branch
alongside their existing `shows`/`written_media` handling, matched by shared
`id` (like shows, not by title like written_media, since games share the
composite-key model).

## UI

New top-level **Games** tab, structured like the Watch tab:
- **Backlog** / **Playing** / **Completed** sub-views, filtered by
  `list_status`, same list-item card style as shows' In Progress/Watchlist.
- **Tier List** sub-tab — same drag-and-drop S/A/B/C/D component as shows',
  parameterized to `kind: 'game'`.
- **Ratings** sub-tab — same star-rating grid as shows'/reading's Ratings
  tabs, parameterized to `kind: 'game'`.

Each game card shows title, cover art, platform, hours played (when set),
and status — no episode/chapter-style progress bar, since there's nothing
numeric to bar-fill.

## Adding a game

New "+ Add Game" modal, same shape as the existing "+ Add Show"/"+ Add
Reading" modals:
1. Title search against RAWG.io (`https://api.rawg.io/api/games?key=<key>&search=<title>`)
   — free API key, no OAuth. Candidate picker shows cover art, platforms,
   release year; selecting one fills in title, cover_url, genres, platform
   (first/primary platform from RAWG's list — user can edit), developer,
   release_year.
2. No RAWG match / lookup failure: manual entry fallback, same as the
   existing "no-lookup" modals — the modal hint says as much, matching
   CLAUDE.md's existing note about the manual "+ Add" modals.
3. `list_status` defaults to `backlog`; `hours_played` starts null.

CLAUDE.md gets a new "Adding a game" section documenting the RAWG lookup call
and its fallback, matching the existing "Adding a new show" / "Adding a
book..." sections' structure.

## Stats tab

New Games section: total `hours_played` summed across `completed`/`playing`
entries, count of `completed`, count of `backlog`. Same card style as the
existing watch-time stat.

## Testing

- Add a game via RAWG lookup; confirm cover/genres/platform/developer/year
  populate and the row lands in Backlog.
- Add a game with no RAWG match; confirm the manual-entry fallback works and
  saves correctly.
- Move a game through Backlog → Playing → Completed; set hours_played at each
  step; confirm Stats reflects it.
- Rate a game under Together; confirm the Together→Personal mirror (companion
  spec) creates the sibling personal row and copies the rating, same as it
  does for shows today.
- Drag a game between tiers on the Games Tier List; confirm it persists and
  matches the shows Tier List's existing drag behavior.
