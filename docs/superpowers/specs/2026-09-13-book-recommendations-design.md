# Book Recommendations — Design

## Purpose

Extend the existing Recommendations tab (Anime / Manga-Manhwa / Western /
Movies — see `2026-09-12-recommendations-design.md` and
`2026-09-13-western-movie-recommendations-design.md`) with a **Books**
sub-tab. Manga/Manhwa already gets full AniList-powered recommendations
today (AniList's `type: MANGA` covers both), so this closes the one
remaining gap: `written_media` rows with `category: 'book'`.

Webnovels are explicitly **out of scope** — there's no free catalog for
web-serial fiction (Open Library only indexes published books), so there's
no candidate pool to recommend from. Webnovels stay trackable/ratable as
they are today; they just don't get a "discover" tab.

## Why this can't reuse `computeRecommendations` as-is

Anime/Manga/Western/Movie recommendations are all built around a shared
shape: per-title "similar to X" API results (AniList `recommendations`
field / TMDB `/recommendations`), seed-tier weighting across your
highest-rated titles, and a non-personalized "peak/popular" fallback.
**Open Library has neither a per-title similarity endpoint nor a general
popularity ranking** — only:

- `search.json?author=<name>` — other works by a given author.
- `subjects/{genre_slug}.json` — works tagged with a genre/subject.

That rules out a "Because you liked X" section (no per-title seed) and a
"Peak stuff you haven't seen" section (no popularity signal independent of
genre). So Books gets a new, smaller orchestration function,
`computeBookRecommendations`, with two sections instead of three:

- **More from authors you love** — seeded from your top-rated books'
  authors, via `search.json?author=<name>`.
- **Matches your taste** — your top 3-5 genres by rating average (reusing
  `computeAffinity`), via `subjects/{genre_slug}.json` per genre.

Both sections are gated behind the same `MIN_RATED_FOR_AFFINITY` (5)
threshold the other tabs use — neither signal means much with fewer than 5
rated books.

## What's reused as-is

- `recommendations_cache` / `dismissed_recommendations` tables, the 7-day
  cache throttle, manual Refresh button (`REC_CACHE_MAX_AGE_MS`,
  `loadRecommendations` — gets one new branch, see below).
- `getDismissedRecommendationIds`, `dismissRecommendation`.
- `computeAffinity` for genre-average ranking (already category-agnostic —
  called with the book-filtered `rows`, same as manga's call today).
- `renderRecSectionGrid`, `addRecommendationItemToWatchlist`,
  `startRecommendationItemNow` — all already render/act generically off
  `{title, coverUrl, genres, reason, reasonDetail, sourceRating,
  alreadyOnWatchlist, watchlistTags}`. Two small fixes needed (see below),
  not a rewrite.
- Title-based dedup helpers (`normalizeTitle`, `candidateMatchesAny`,
  `candidateTitleKeys`, `buildAlreadyHaveTitles`) — reused for
  author-search and subject-search results the same way the other tabs use
  them for AniList/TMDB results.

## Fixes needed in shared code

Two hardcoded assumptions in the shared render/action layer currently
assume "non-shows category" always means manga:

- `addRecommendationItemToWatchlist` / `startRecommendationItemNow` insert
  into `written_media` with a hardcoded `category: 'manga'`. Change to use
  the passed-in `category` param so a book candidate writes
  `category: 'book'` instead of silently mis-filing as manga.
- Neither function currently sets `author` on the `written_media` insert
  (manga candidates have no author field from AniList, so this was never
  needed). Open Library candidates do have a reliable `author_name` — add
  `author: item.author` to both inserts, harmless no-op for
  manga (`item.author` is `undefined` there → column stays null).
- `filterDismissedSections` currently hardcodes the three section keys
  (`becauseYouLiked`, `overallTaste`, `peakUnseen`). Generalize to iterate
  `Object.keys(sections)` so it works for both the 3-key shows/manga shape
  and the 2-key book shape without a parallel function.
- `loadRecommendations` calls `computeRecommendations(scope, category,
  rows, allRows)` unconditionally. Add a branch: `category === 'book' ?
  computeBookRecommendations(scope, rows, allRows) :
  computeRecommendations(...)`.
- `externalIdFor` needs one more case for Open Library results: an
  OLID/work-key based id (e.g. `olid:${item.olid}`), checked alongside
  the existing `anilistId`/`tmdbId`/`malId` cases.

**Verify before implementation**: confirm `recommendations_cache.category`
and `dismissed_recommendations.category` have no enum/check constraint
excluding `'book'` (same caveat already flagged in the western/movie spec
for those two values — same column, so if it was widened for those it
likely already accepts `'book'` too, but confirm).

## New Open Library fetch functions

- **`fetchOpenLibraryAuthorCandidates(authorNames, count)`** — for each
  seed author (from your top-rated books, same seed-tier concept as
  `pickRecommendationSeeds` but simpler: just dedupe author names from
  your 4/4.5/5-star books), call
  `search.json?author=<name>&limit=10&fields=title,author_name,cover_i,subject,key`.
  Map each result to `{title, author: result.author_name?.[0], coverUrl,
  genres: (result.subject||[]).slice(0,5), olid: result.key, reason:
  'by_author', reasonDetail: <seed author name>}`.
- **`fetchOpenLibrarySubjectCandidates(genres, count)`** — for each of the
  top genres, call `subjects/{slug}.json?limit=20` (slug = lowercase,
  spaces → underscores, e.g. "Science Fiction" → `science_fiction`). Map
  each `works[]` entry to the same candidate shape, `reason: 'affinity'`.
  Over-fetch (same `REC_SECTION_CAP + dedup-buffer` pattern as the other
  tabs) since dedup against your library and against the author section
  will remove some.

Both functions dedupe against `alreadyHave` (title-based, same helper as
every other tab) before returning, and against each other inside
`computeBookRecommendations` the same way `overallTaste` dedupes against
`becauseYouLiked`'s `usedTitles` today.

## `renderRecSectionGrid` reason text

Add one branch to the existing `reason` → text mapping:

```
} else if (item.reason === 'by_author') {
  reasonHTML = `More by <strong>${escapeHTML(item.reasonDetail)}</strong>`;
}
```

(`'affinity'` already renders "Matches your X taste" — reused as-is for
the genre section.)

## UI & category plumbing

New `'book'` value for `activeRecCategory`, alongside `'anime'` | `'manga'`
| `'western'` | `'movie'`. `renderRecommendationsTab`'s `isShowsCategory`
check already routes anything not anime/western/movie to
`fetchWrittenMedia` — extend the written-media row filter (currently
`m.category === 'manga' || m.category === 'manhwa'`) with a
category-specific branch: `'book'` filters to `m.category === 'book'`.

New "Books" sub-tab button next to the existing four. When
`activeRecCategory === 'book'`, render exactly two section grids ("More
from authors you love", "Matches your taste") instead of three — the
`belowThreshold` gate (already used to hide `because`/`overall` and show
only `peak` for the other tabs) becomes "hide both sections" for books,
since there's no ungated third section to fall back to. Show the existing
"Rate a few more books to unlock recommendations" message in that case.

## Error handling

Same posture as every other tab: a failed section doesn't block the other
(`byAuthorFailed` / `overallTasteFailed` pattern, mirroring
`becauseYouLikedFailed` / `overallTasteFailed` / `peakUnseenFailed`), total
failure across both sections falls back to last cache (`stale: true`), no
retry/backoff beyond what already exists. Open Library has no documented
rate limit as aggressive as AniList/Jikan's, but requests should still go
through the same sequential (not `Promise.all`) pattern as every other
fetch loop in this file, for consistency and to avoid being the one
concurrent-burst exception.

## Testing approach

Same Playwright-driving-the-real-page pattern used throughout this project
— serve `index.html` locally, mock `fetchWrittenMedia` with a synthetic
book library (a handful of rated books across 2-3 authors and genres), let
real Open Library calls run. Cases to cover:

- Below the 5-rated-books threshold: both sections hidden, gating message
  shown.
- At/above threshold: "More from authors you love" surfaces an untracked
  book by an author already in the library; a book already tracked by
  that author is excluded.
- "Matches your taste" surfaces a book tagged with the library's top
  genre; a book already in the library (any category, per the existing
  cross-category "already have" rule) is excluded.
- Dismissing a book recommendation persists across a forced refresh
  (`dismissed_recommendations` round-trip).
- "+ Watchlist" on a book candidate inserts into `written_media` with
  `category: 'book'` (not `'manga'`) and a populated `author` field.
- Open Library request failure on both sections falls back to stale cache
  with the existing "couldn't refresh" notice, same as other tabs.
