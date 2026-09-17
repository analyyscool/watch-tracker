# Together → Personal Rating Mirror — Design Spec

Date: 2026-09-17
Status: Approved by Karl, pending implementation plan

## Context

Liisa rated a batch of movies/anime under the `together` scope. She expected
those ratings to also show up on her own personal list, and to stay in sync
if she changes them in either place.

The codebase already has half of this: `syncRatingToSiblingScope` (index.html
~3107) mirrors a rating/note between a personal-scope row and its Together
sibling whenever BOTH already exist, keyed by matching `shows.id` (the
composite `(id, scope)` primary key means the same title shares one `id`
across its scope copies). There's also `syncTogetherFromPersonalRatings`
(index.html ~9170), which runs on every Together-scope Ratings-tab render and
does the *reverse*: once both Karl and Liisa have independently rated the same
title under their own personal rows, it auto-creates the Together row and
copies the ratings in.

The gap: these Together entries were added directly under `scope: 'together'`
with no personal-scope row for either person ever created. Neither sync
function has anything to mirror into/from, since both require a sibling row
to already exist. Confirmed live: Liisa's personal `shows` scope currently
has no real rows at all.

The established pattern in this app is personal-scope-first, Together-derived
— not the other way around. This spec closes the gap by making sure a
personal-scope sibling always exists, so the *existing* sync machinery just
works, rather than inventing a new sync direction.

## Goals

- Whenever a `together`-scoped `shows` or `written_media` row exists without a
  matching personal-scope row for a given person, create one automatically —
  so `syncRatingToSiblingScope` has something to mirror into/from and ratings
  behave identically whichever side they're changed from.
- Self-healing: fixes every already-existing Together-only item retroactively,
  the first time the affected person opens their own Ratings or Reading
  Ratings tab — no manual migration step, no schema change.
- Covers both `shows` and `written_media`.

## Non-goals

- No merge of Together items into any other personal-scope tab (In Progress,
  Watchlist, Reading list, Stats) — scoped to Ratings/Reading Ratings only,
  per discussion.
- No change to how new items get added (the add-show/add-reading modals, or
  the Claude-mediated `supabase-write.mjs` flow in CLAUDE.md) — the mirror
  pass covers gaps from any of those paths uniformly, so none of them need to
  change.
- Progress/`list_status` stays independent per scope, same as everywhere else
  in the app — only rating and note get mirrored.

## Design

### Shows

New function `mirrorTogetherShowsIntoPersonal()`, called from
`renderRatingsTab()` whenever `activeScope` is `karl` or `liisa` (the mirror
image of the existing call to `syncTogetherFromPersonalRatings()` when
`activeScope === 'together'`).

For each `together`-scoped row:
1. Look for a `shows` row with the same `id` under `scope: myScope`. If found,
   nothing to do (the existing sibling sync already keeps it current).
2. If missing, insert one, copying the same field set
   `syncTogetherFromPersonalRatings` already uses when it creates a Together
   row from a personal one (title, category, poster_url, studio, genres,
   total_episodes/seasons, current_episode/season_episode/current_season set
   to the totals — i.e. "already watched", matching how the reverse function
   treats a rated show — runtime_minutes, list_status: null, in_tier_pool:
   true).
3. If the current user already has a rating recorded against the Together
   row (`ratings` table, `scope: 'together', user_id: currentProfile.id`),
   upsert that same rating/note onto the new personal-scope sibling
   (`scope: myScope`). Uses the existing `ratings` upsert shape and
   `onConflict: 'show_id,scope,user_id'` key — no schema change.

RLS-safe by construction: everything is written under the current user's own
scope/`user_id`, never the other person's — same constraint the existing
`syncTogetherFromPersonalRatings` already works within.

### Written media

Same shape, `mirrorTogetherMediaIntoPersonal()`, called from
`renderReadingRatingsTab()`.

Matching can't use `id` — `written_media` rows get an independent generated
UUID per row (see CLAUDE.md's "not idempotent" note), so the Together copy
and a personal copy of the same title never share one. Match instead on
normalized title (case-insensitive, trimmed) + `category` within the target
personal scope.

1. If a personal-scope row with the same normalized title+category exists,
   nothing to do.
2. If missing, insert one, copying title/category/author/cover_url/genres/
   total_chapters/total_volumes/total_pages/series_status, with
   current_chapter/volume/page set to the totals and `list_status:
   'completed'` (mirrors the shows side's "already consumed" treatment).
3. If the current user has an existing rating tied to the Together row's
   `written_media_id`, upsert the same rating/note onto the new row's own
   `written_media_id` (media ratings have no `scope` column — the conflict
   key is `written_media_id, user_id` — so this is a second, independent
   rating row tied to the new id, not a shared one; that matches how media
   ratings already work everywhere else).

### Idempotency & cost

Both functions only ever insert when a lookup finds nothing, so re-running on
every tab visit is a no-op once caught up. Cost is one extra read (existing
Together rows compared against existing personal rows, both already fetched
via `fetchShows`/`fetchWrittenMedia`) plus at most one insert + one rating
upsert per previously-unmirrored item — no external API calls, no per-item
network round trip.

### Error handling

Same as the existing sync functions: log and skip on a per-row Supabase
error (`console.error`, `continue`) rather than aborting the whole pass, so
one bad row doesn't block mirroring the rest. Cache invalidation
(`invalidateShowsCache()` / `invalidateWrittenMediaCache()`) once at the end
if anything changed, matching `syncTogetherFromPersonalRatings`'s pattern.

## Testing

- Manual: as Liisa, open the Ratings tab under her own scope with at least
  one Together-only rated title present; confirm a personal-scope row and
  matching rating appear, and that the Together card's rating is unchanged.
- Change the rating from the personal side afterward; confirm it mirrors back
  to Together via the existing `syncRatingToSiblingScope` (no new code, just
  confirming the two functions now hand off cleanly).
- Repeat for a Together-only manga/book on the Reading Ratings tab.
- Re-open the tab a second time with nothing new to mirror; confirm no
  duplicate rows or unnecessary writes (idempotency).
