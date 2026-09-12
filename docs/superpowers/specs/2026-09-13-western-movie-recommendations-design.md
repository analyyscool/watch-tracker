# Western TV + Movie Recommendations — Design

## Purpose

Extend the existing Recommendations tab (currently Anime / Manga-Manhwa,
built 2026-09-12 and iterated on through 2026-09-13 — see that design doc
and `index.html`'s `computeRecommendations` for the current shipped
implementation, which has diverged from the original spec in several ways)
with two new sub-tabs: **Western** and **Movies**, backed by TMDB instead
of AniList. Same three-section layout (Because you liked / Matches your
overall taste / Peak stuff you haven't seen), same seed-tier weighting,
cross-section dedup, watchlist-flagging, caching, and dismissal
infrastructure — all of that is data-source-agnostic already. Books remain
out of scope (unchanged from the original spec's reasoning: no free API
provides "similar books").

## What's reused as-is

These are data-source-agnostic and need no changes:

- `SEED_TIER_WEIGHTS` (30% 5★ / 30% 4.5★ / 40% 4★) and
  `pickRecommendationSeeds`.
- Cross-section title dedup (`normalizeTitle`, `titleOverlapsAny`,
  `candidateMatchesAny`, `candidateTitleKeys`).
- Watchlist-vs-"already have" split and `findWatchlistMatch` (a
  `list_status: 'watchlist'` row can still surface as a recommendation,
  flagged with a disabled "On Watchlist" button and its `tags`, e.g.
  "Season 2", shown inline).
- `recommendations_cache` / `dismissed_recommendations` tables, the 7-day
  cache throttle, and the manual Refresh button
  (`REC_CACHE_MAX_AGE_MS`, `loadRecommendations`).
- `renderRecSectionGrid` and the per-show "Similar to this" modal
  (`openShowDetailModal`) — both already render generically from
  `{title, coverUrl, genres, score, reason, reasonDetail, alreadyOnWatchlist,
  watchlistTags}`, with no AniList-specific assumptions in the rendering
  layer itself.

**Verify before implementation**: `recommendations_cache.category` and
`dismissed_recommendations`'s scoping are `category text` per the original
schema — confirm there's no enum/check constraint limiting it to
`'anime'`/`'manga'` before relying on a drop-in `'western'`/`'movie'`
value. If there is one, add a migration to widen it.

## New TMDB fetch functions

Mirrors of the three AniList fetch functions, parallel naming:

- **`fetchTMDBRecommendationsFor(title, mediaType)`** (mediaType: `'movie'`
  | `'tv'`) — resolve `title` via `/search/{mediaType}`, picking the
  highest-`popularity` result among candidates (same disambiguation
  strategy already used for AniList and for the existing
  `searchTMDBCovers`/`checkWesternSeason` functions), then fetch
  `/{mediaType}/{id}/recommendations`.
- **`fetchTMDBGenreAffinityCandidates(genres, mediaType, count)`** —
  `/discover/{mediaType}` with `with_genres` (comma-joined, OR semantics —
  TMDB's `with_genres` is AND when comma-separated and OR when
  pipe-separated; use pipe-separated top genres in one call, unlike
  AniList's per-genre-separate-calls workaround, since TMDB doesn't have
  the AniList `genre_in`-is-AND problem), `sort_by=vote_average.desc`,
  and a `vote_count.gte` floor (see Peak-stuff below) so the affinity
  pass doesn't surface a 10/10-from-3-votes obscurity.
- **`fetchTMDBPeakUnseenCandidates(mediaType, count)`** — same
  `/discover/{mediaType}` endpoint, sorted by `vote_average.desc` with a
  `vote_count.gte` floor as the non-personalized "peak" signal (TMDB's
  analogue of AniList's `popularity` floor — TMDB doesn't expose a raw
  list-count metric the way AniList does, so vote count is the closest
  proxy). TMDB caps `/discover` at 20 results/page (vs. AniList's 50), so
  this paginates across multiple pages the same way
  `fetchPeakUnseenCandidates` was just fixed to for anime — don't repeat
  today's "silently capped at one page" bug.

`vote_count.gte` floor value needs a live spot-check against real
TMDB data (analogous to how `PEAK_MIN_POPULARITY = 15000` was picked by
spot-checking AniList's actual score distribution) before hardcoding a
number — do this during implementation, not guessed here.

## Franchise-tail check

- **Movies**: TMDB's movie detail response includes `belongs_to_collection`
  (`{id, name}`) when a movie is part of a franchise. For a candidate with
  a collection, fetch `/collection/{id}` (its `parts` array, sortable by
  `release_date`) and require at least one earlier-released part to
  already be tracked (via title dedup against "already have") — otherwise
  exclude, mirroring `isFreshFranchiseEntry`'s PREQUEL-based logic for
  anime, but with structured, reliable data (no relationType-ambiguity
  risk like the ALTERNATIVE-edge false positive hit and reverted for
  anime today).
- **TV**: TMDB has no equivalent structured relation for TV shows
  (verified live against a known real spin-off pair, Better Call Saul →
  Breaking Bad — no field on the show's detail response connects them,
  only generic, target-less keyword tags). Per explicit decision: any TV
  candidate whose `/tv/{id}/keywords` response includes `"spin off"` or
  `"prequel"` is unconditionally excluded, regardless of whether the
  parent show is tracked — a blunt rule, not a smart check, because the
  data to make it smart doesn't exist. To limit API calls, only run the
  keywords check on the small set of finalists that already survived
  every other filter (~10-15 titles per section), not the full raw
  candidate pool (30-50+) — keywords is a separate call per show, unlike
  AniList's relations field which came bundled into the main query.

## UI & category plumbing

Both `movie` and `western` categories already live in the `shows` table
(`category` column), so this extends `activeRecCategory`'s existing values
(`'anime'` | `'manga'`) with `'western'` and `'movie'`, each still backed
by `fetchShows(activeScope)` filtered by category — same pattern anime
uses today, just a different category value and a different set of fetch
functions dispatched on it. Two new sub-tab buttons ("Western", "Movies")
next to the existing "Anime" / "Manga / Manhwa", same `.sub-tab-btn`
pattern.

`runtime_minutes` (required for `category: 'western'`/`'movie'` rows,
per `CLAUDE.md`) isn't used by any recommendation logic and needs no
special handling — it's purely a Stats-tab field.

## Error handling

Same posture as the existing AniList pipeline: a failed fetch for one
section doesn't block the others (`becauseYouLikedFailed` /
`overallTasteFailed` / `peakUnseenFailed` pattern in
`computeRecommendations`), a total failure across all three sections
falls back to the last cache (`stale: true`), and there's no TMDB→
fallback-API story needed here since this project already has exactly one
TMDB integration path elsewhere (`checkWesternSeason`,
`searchTMDBCovers`) with no established fallback for TMDB outages — not
introducing one now.

## Testing approach

Same Playwright-driving-the-real-page pattern used throughout this
project (no test framework) — serve `index.html` locally, mock
`fetchShows` with a synthetic western/movie library, let real TMDB calls
run. Cases to cover:

- Tier-quota split holds for the Western/Movie seed pool the same way it
  was just verified for anime (3/3/4 of 10).
- A movie candidate belonging to an untracked collection is excluded
  ("Toy Story 3" not recommended without "Toy Story"/"Toy Story 2"
  tracked); a candidate in a collection where an earlier part IS tracked
  is not excluded.
- A TV candidate tagged "spin off" is excluded regardless of whether its
  (unidentifiable) parent is tracked.
- Peak-stuff pagination doesn't collapse to empty for an established
  Western/Movie library, the same regression just fixed for anime.
- A watchlisted movie/show surfaces with a disabled "On Watchlist" button
  instead of being excluded outright.
