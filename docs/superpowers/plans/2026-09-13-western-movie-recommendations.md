# Western TV + Movie Recommendations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add "Western" and "Movies" sub-tabs to the existing Recommendations tab, backed by TMDB, reusing all the data-source-agnostic infrastructure (tier-seeding, dedup, watchlist-flagging, caching, dismissal) already built for the AniList-backed Anime/Manga version.

**Architecture:** Introduce three new TMDB fetch functions parallel to the existing AniList ones, plus a small per-category dispatch table (`RECOMMENDATION_SOURCES`) inside `computeRecommendations` so the shared orchestration logic (tier quotas, cross-section dedup, watchlist flagging, caching) doesn't need to know which API backs a given category. Franchise-tail checking differs sharply by category: movies get a real check via TMDB's `belongs_to_collection`, TV gets a blunt post-filter blanket-excluding "spin off"/"prequel"-keyword-tagged shows (no way to do better — verified live that TMDB has no structured relation for TV).

**Tech Stack:** Vanilla JS in `index.html` (no build step), TMDB API (`TMDB_API_KEY` already defined), Supabase (`recommendations_cache`, `dismissed_recommendations` — already `category text`, no enum constraint, verified live).

**Spec:** `docs/superpowers/specs/2026-09-13-western-movie-recommendations-design.md`

## Global Constraints

- No test framework in this project — verification is Playwright driving the real `index.html` (served via `python -m http.server`) with `fetchShows` mocked to a synthetic library, and REAL network calls to TMDB (no TMDB mocking) — same pattern used throughout this session (see `docs/superpowers/specs/2026-09-13-western-movie-recommendations-design.md`'s Testing approach, and the anime Recommendations work earlier this session for the established mock pattern: mock `currentProfile`/`activeScope`/`fetchShows`, leave `supabase.from` alone unless testing a write).
- `TMDB_API_KEY` is the existing constant at `index.html:3467` — reuse it, don't hardcode a second copy.
- Sequential (not `Promise.all`) network calls in any loop over multiple seeds/candidates — matches the existing rate-limit discipline for both AniList and TMDB calls elsewhere in this file (`checkNewSeasons`, `computeRecommendations`'s own seed loop).
- `category` values: `'western'` and `'movie'` (already used elsewhere in this codebase for the `shows` table — do not invent new category strings).
- Every new function gets a one-line JSDoc-style comment only if the WHY isn't obvious from the name + existing surrounding comments — follow this file's existing comment density, don't under- or over-comment.

---

### Task 1: TMDB seed-recommendation fetch (`fetchTMDBRecommendationsFor`)

**Files:**
- Modify: `index.html` — add new function immediately after `fetchJikanRecommendationsFor` (search for `// ── Recommendations: AniList + Jikan fetch ──`, the new TMDB functions get their own `// ── Recommendations: TMDB fetch ──` section directly after that block, before `// ── Recommendations: orchestration, cache, dismissal ──`).

**Interfaces:**
- Consumes: `TMDB_API_KEY` (existing constant, `index.html:3467`).
- Produces: `async function fetchTMDBRecommendationsFor(title, mediaType)` — `mediaType` is `'movie'` or `'tv'`. Returns an array of candidate objects shaped `{ tmdbId, title, genres, coverUrl, score, collectionId, isTV }` on success, `[]` if the title resolves but has no recommendations, or `null` if the fetch itself failed (search 0 results, or a network/HTTP error) — same three-way contract as `fetchAniListRecommendationsFor`/`fetchRecommendationsForSeed`. **Note (ruled during Task 3's execution):** `collectionId` will always be `null` here in practice — `belongs_to_collection` isn't present on list-endpoint responses, only on `/movie/{id}` detail. The field stays in the shape for consistency but Task 3 does its own detail-endpoint lookup rather than relying on it. See Task 3's "PLAN CORRECTION" note.

- [ ] **Step 1: Write the function**

```javascript
  // ── Recommendations: TMDB fetch ──
  // Same "seed a specific title, fetch what TMDB recommends alongside it"
  // idea as fetchAniListRecommendationsFor, but for Western TV/movies.
  // TMDB's /search endpoint can return multiple same-named results (a
  // remake, an unrelated foreign film with the same title) -- picking the
  // highest-`popularity` hit is the same disambiguation strategy already
  // used for AniList seeds and for this file's existing TMDB lookups
  // (searchTMDBCovers, checkWesternSeason).
  async function fetchTMDBRecommendationsFor(title, mediaType) {
    try {
      const searchRes = await fetch(`https://api.themoviedb.org/3/search/${mediaType}?api_key=${TMDB_API_KEY}&query=${encodeURIComponent(title)}`);
      const searchJson = await searchRes.json();
      const results = searchJson.results || [];
      if (!results.length) return null;
      const best = results.reduce((a, b) => (b.popularity > a.popularity ? b : a));
      const recRes = await fetch(`https://api.themoviedb.org/3/${mediaType}/${best.id}/recommendations?api_key=${TMDB_API_KEY}`);
      const recJson = await recRes.json();
      const recResults = recJson.results || [];
      return recResults.map(r => tmdbResultToCandidate(r, mediaType));
    } catch (e) {
      console.warn('TMDB recommendation search failed for', title, e);
      return null;
    }
  }

  // Shared TMDB result -> candidate shape across all three TMDB fetch
  // functions (seed-based, genre-affinity, peak-unseen), mirroring how
  // fetchAniListRecommendationsFor/fetchGenreAffinityCandidates/
  // fetchPeakUnseenCandidates all build the same candidate shape for
  // AniList. `title`/`name` differs between /movie and /tv responses;
  // `belongs_to_collection` only exists on /movie responses (used by the
  // Task 2 franchise check, ignored for TV).
  function tmdbResultToCandidate(r, mediaType) {
    return {
      tmdbId: r.id,
      title: mediaType === 'movie' ? r.title : r.name,
      genres: (r.genre_ids || []).map(id => TMDB_GENRE_NAMES[id]).filter(Boolean),
      coverUrl: r.poster_path ? `https://image.tmdb.org/t/p/w342${r.poster_path}` : null,
      score: r.vote_average != null ? Math.round(r.vote_average * 10) : null,
      collectionId: r.belongs_to_collection?.id ?? null,
      isTV: mediaType === 'tv',
    };
  }

  // TMDB's /search and /discover responses only give genre IDs, not
  // names (unlike AniList, which returns genre strings directly) --
  // this is TMDB's own official, stable ID->name mapping (documented at
  // https://developer.themoviedb.org/reference/genre-movie-list and
  // .../genre-tv-list), merged into one lookup since a handful of ids
  // (e.g. 10759 "Action & Adventure") are TV-only and don't collide with
  // movie ids in practice.
  const TMDB_GENRE_NAMES = {
    28: 'Action', 12: 'Adventure', 16: 'Animation', 35: 'Comedy', 80: 'Crime',
    99: 'Documentary', 18: 'Drama', 10751: 'Family', 14: 'Fantasy', 36: 'History',
    27: 'Horror', 10402: 'Music', 9648: 'Mystery', 10749: 'Romance',
    878: 'Science Fiction', 10770: 'TV Movie', 53: 'Thriller', 10752: 'War',
    37: 'Western', 10759: 'Action & Adventure', 10762: 'Kids', 10763: 'News',
    10764: 'Reality', 10765: 'Sci-Fi & Fantasy', 10766: 'Soap', 10767: 'Talk',
    10768: 'War & Politics',
  };
```

- [ ] **Step 2: Verify live against real TMDB data**

Serve the file locally and check the function directly in a browser console (no test framework in this project):

```bash
cd /path/to/watch-tracker && python -m http.server 8791 &
```

Then in a Playwright/browser console against `http://localhost:8791/index.html`:

```javascript
await fetchTMDBRecommendationsFor('Breaking Bad', 'tv')
// Expect: an array of candidate objects, each with tmdbId/title/genres/coverUrl/score, isTV: true
await fetchTMDBRecommendationsFor('Toy Story 3', 'movie')
// Expect: an array of candidate objects, each with tmdbId/title/genres/coverUrl/score.
// collectionId will be null on every entry here -- confirmed live (ruled during
// Task 3's execution) that belongs_to_collection isn't present on this list
// endpoint's response shape, only on /movie/{id} detail. Not a bug in this task.
await fetchTMDBRecommendationsFor('zzzznonexistentshow12345', 'tv')
// Expect: null (search resolves to 0 results)
```

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat: add fetchTMDBRecommendationsFor for Western/Movie recommendations"
```

---

### Task 2: TMDB genre-affinity + peak-unseen fetch

**Files:**
- Modify: `index.html` — add directly after Task 1's functions, before the orchestration section comment.

**Interfaces:**
- Consumes: `TMDB_GENRE_NAMES`, `tmdbResultToCandidate` (Task 1).
- Produces: `async function fetchTMDBGenreAffinityCandidates(genreNames, mediaType, count)` and `async function fetchTMDBPeakUnseenCandidates(mediaType, count)` — same `null`-means-failed / `[]`-means-succeeded-but-empty contract as their AniList counterparts. Both return arrays of the same candidate shape as Task 1.

- [ ] **Step 1: Write the genre-affinity function**

TMDB's `with_genres` uses comma for AND and pipe (`|`) for OR — unlike AniList's `genre_in`, which is AND-only and required the per-genre-separate-calls workaround documented at `index.html`'s `fetchGenreAffinityCandidates` comment. TMDB doesn't have that problem, so this is a single call:

```javascript
  const TMDB_GENRE_IDS = Object.fromEntries(Object.entries(TMDB_GENRE_NAMES).map(([id, name]) => [name, id]));

  async function fetchTMDBGenreAffinityCandidates(genreNames, mediaType, count) {
    const genreIds = genreNames.map(g => TMDB_GENRE_IDS[g]).filter(Boolean);
    if (!genreIds.length || count <= 0) return [];
    const results = [];
    let anySucceeded = false;
    // TMDB caps /discover at 20 results/page -- paginate the same way
    // fetchTMDBPeakUnseenCandidates does (see below), stopping once
    // there's a healthy buffer (2x count) for the caller's own filtering.
    for (let page = 1; page <= 4 && results.length < count * 2; page++) {
      try {
        const res = await fetch(`https://api.themoviedb.org/3/discover/${mediaType}?api_key=${TMDB_API_KEY}&with_genres=${genreIds.join('|')}&sort_by=vote_average.desc&vote_count.gte=200&page=${page}`);
        const json = await res.json();
        if (!res.ok) { console.warn('TMDB genre-affinity search failed', res.status); break; }
        anySucceeded = true;
        const pageResults = json.results || [];
        pageResults.forEach(r => results.push(tmdbResultToCandidate(r, mediaType)));
        if (page >= (json.total_pages || 1)) break;
      } catch (e) {
        console.warn('TMDB genre-affinity search failed', e);
        break;
      }
    }
    return anySucceeded ? results : null;
  }
```

- [ ] **Step 2: Write the peak-unseen function**

Mirrors the just-fixed (2026-09-13) `fetchPeakUnseenCandidates` pagination pattern for AniList -- paginate, don't pre-slice before the caller's own already-have/franchise/dismissed filtering runs:

```javascript
  // TMDB's vote_count is the closest analogue to AniList's `popularity`
  // floor (PEAK_MIN_POPULARITY) -- 200 is a starting point, NOT verified
  // against TMDB's real vote-count distribution the way 15000 was
  // spot-checked live for AniList. Spot-check this during Task 6's
  // end-to-end verification (e.g. fetch the top 50 by vote_average with
  // no floor and eyeball where genuinely-obscure titles start
  // outnumbering broadly-known ones) and adjust before shipping.
  const TMDB_MIN_VOTE_COUNT = 200;

  async function fetchTMDBPeakUnseenCandidates(mediaType, count) {
    if (count <= 0) return [];
    const results = [];
    let anySucceeded = false;
    for (let page = 1; page <= 4 && results.length < count * 2; page++) {
      try {
        const res = await fetch(`https://api.themoviedb.org/3/discover/${mediaType}?api_key=${TMDB_API_KEY}&sort_by=vote_average.desc&vote_count.gte=${TMDB_MIN_VOTE_COUNT}&page=${page}`);
        const json = await res.json();
        if (!res.ok) { console.warn('TMDB peak-unseen search failed', res.status); break; }
        anySucceeded = true;
        const pageResults = json.results || [];
        pageResults.forEach(r => results.push(tmdbResultToCandidate(r, mediaType)));
        if (page >= (json.total_pages || 1)) break;
      } catch (e) {
        console.warn('TMDB peak-unseen search failed', e);
        break;
      }
    }
    // Deliberately NOT sliced to `count` -- see the identical comment on
    // fetchPeakUnseenCandidates for why (the caller's own already-have/
    // franchise/dismissed filtering needs real headroom to work with).
    return anySucceeded ? results : null;
  }
```

- [ ] **Step 3: Verify live**

```javascript
const genreCands = await fetchTMDBGenreAffinityCandidates(['Drama', 'Crime'], 'tv', 20);
// Expect: array of 20+ candidates, all with genres including Drama or Crime
const peakCands = await fetchTMDBPeakUnseenCandidates('movie', 20);
// Expect: array of 40+ candidates (2+ pages), sorted roughly by score descending
```

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: add TMDB genre-affinity and peak-unseen fetch functions"
```

---

### Task 3: Movie franchise-tail check (collection-based)

**PLAN CORRECTION (ruled during execution, 2026-09-13):** the original version of this task assumed `candidate.collectionId` (populated by Task 1's `tmdbResultToCandidate` from `r.belongs_to_collection?.id`) would be usable directly. Verified live against real TMDB responses during Task 1's review that this is wrong: `belongs_to_collection` is **only present on the `/movie/{id}` detail endpoint**, never on `/movie/{id}/recommendations`, `/discover/movie`, or `/search/movie` list responses (confirmed: Toy Story 3's own recommendations-list entry and its /discover entries both omit the field entirely, while `/movie/10193` — the detail endpoint — has it). Task 1's code is UNCHANGED (already reviewed and committed) — its `collectionId` field stays in `tmdbResultToCandidate` but will always be `null` in practice; simply don't rely on it. Instead, `isFreshMovieEntry` below fetches the candidate's own detail endpoint first to get `belongs_to_collection`, then proceeds to the collection lookup — two calls instead of one, only for the small set of finalists (per Task 5's "check only after quotas fill" pattern, same cost-control philosophy as Task 4's TV keyword check), never per-raw-candidate.

**Files:**
- Modify: `index.html` — add after Task 2's functions.

**Interfaces:**
- Consumes: `candidate.tmdbId` (Task 1's `tmdbResultToCandidate` — `collectionId` is NOT used, see correction above), `buildAlreadyHaveTitles`/`titleOverlapsAny`/`normalizeTitle` (existing, shared dedup helpers).
- Produces: `async function isFreshMovieEntry(candidate, alreadyHave)` — returns `true` if the candidate has no collection, or if at least one earlier-released (by `release_date`) collection part is in `alreadyHave`; `false` otherwise. Used only for `category === 'movie'`.

- [ ] **Step 1: Write the function**

```javascript
  // Movie equivalent of isFreshFranchiseEntry, but using TMDB's
  // belongs_to_collection -- structured, reliable data (unlike AniList's
  // relationType, whose ALTERNATIVE-edge extension was tried and reverted
  // today after it wrongly gated Fullmetal Alchemist: Brotherhood -- see
  // extractPrequelTitles' comment).
  //
  // belongs_to_collection only exists on TMDB's /movie/{id} DETAIL
  // endpoint, never on the /recommendations, /discover, or /search LIST
  // endpoints a candidate was built from (verified live) -- so this always
  // fetches the candidate's own detail endpoint first. A collection's
  // `parts` array isn't guaranteed to arrive pre-sorted, so this sorts by
  // release_date itself before deciding what counts as "earlier".
  async function isFreshMovieEntry(candidate, alreadyHave) {
    try {
      const detailRes = await fetch(`https://api.themoviedb.org/3/movie/${candidate.tmdbId}?api_key=${TMDB_API_KEY}`);
      const detail = await detailRes.json();
      const collectionId = detail.belongs_to_collection?.id;
      if (!collectionId) return true;
      const res = await fetch(`https://api.themoviedb.org/3/collection/${collectionId}?api_key=${TMDB_API_KEY}`);
      const json = await res.json();
      const parts = (json.parts || []).slice().sort((a, b) => (a.release_date || '9999').localeCompare(b.release_date || '9999'));
      const candidateIndex = parts.findIndex(p => p.id === candidate.tmdbId);
      // Candidate not found in its own collection's parts list (shouldn't
      // happen, but TMDB data is occasionally inconsistent) -- treat as
      // fresh rather than gate on a comparison that can't be made.
      if (candidateIndex <= 0) return true;
      const earlierParts = parts.slice(0, candidateIndex);
      return earlierParts.some(p => titleOverlapsAny(normalizeTitle(p.title), alreadyHave));
    } catch (e) {
      console.warn('TMDB collection lookup failed for candidate', candidate.title, e);
      // A failed lookup shouldn't silently exclude a candidate that might
      // be perfectly fine -- same "fail open" posture as the rest of this
      // file's franchise/dedup checks when a network call errors.
      return true;
    }
  }
```

- [ ] **Step 2: Verify live**

```javascript
const alreadyHaveEmpty = new Set();
const alreadyHaveWithToyStory = new Set(['toy story', 'toy story 2']);
const candidates = await fetchTMDBRecommendationsFor('Toy Story', 'movie');
const toyStory3 = candidates.find(c => /toy story 3/i.test(c.title));
console.log(await isFreshMovieEntry(toyStory3, alreadyHaveEmpty)); // Expect: false
console.log(await isFreshMovieEntry(toyStory3, alreadyHaveWithToyStory)); // Expect: true
// Also verify the detail-endpoint round trip actually returns a real
// collectionId for a known franchise movie (sanity check the plan
// correction itself, not just the end-to-end gating behavior):
const detailCheck = await fetch(`https://api.themoviedb.org/3/movie/${toyStory3.tmdbId}?api_key=${TMDB_API_KEY}`).then(r => r.json());
console.log(detailCheck.belongs_to_collection); // Expect: { id: ..., name: "Toy Story Collection", ... }, not null
```

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat: add movie franchise-tail check via TMDB collections"
```

---

### Task 4: TV spin-off/prequel blanket exclusion (keyword-based)

**Files:**
- Modify: `index.html` — add after Task 3's function.

**Interfaces:**
- Consumes: nothing new.
- Produces: `async function isTVSpinoffOrPrequel(candidate)` — returns `true` if TMDB's keywords for this show include `"spin off"` or `"prequel"`. Used only for `category === 'western'`, and only against the small finalist set (see Task 5) — never the full raw candidate pool.

- [ ] **Step 1: Write the function**

```javascript
  // TV has no structured relation-to-parent-show data on TMDB at all --
  // verified live against a known real spin-off pair (Better Call Saul ->
  // Breaking Bad): the show's full detail response has no field
  // connecting them, only generic keyword tags with no reference to
  // WHICH show they're a spin-off/prequel of. So unlike isFreshMovieEntry
  // (which can check "is the earlier entry tracked"), this can only
  // blanket-exclude -- a spin-off/prequel-tagged show never surfaces,
  // regardless of whether its (unidentifiable) parent is tracked. Explicit
  // user decision (2026-09-13), not a default -- the alternative (skip TV
  // franchise-checking entirely) was the original recommendation.
  async function isTVSpinoffOrPrequel(candidate) {
    try {
      const res = await fetch(`https://api.themoviedb.org/3/tv/${candidate.tmdbId}/keywords?api_key=${TMDB_API_KEY}`);
      const json = await res.json();
      const keywords = (json.results || []).map(k => k.name.toLowerCase());
      return keywords.includes('spin off') || keywords.includes('prequel');
    } catch (e) {
      console.warn('TMDB keywords lookup failed for candidate', candidate.title, e);
      return false; // fail open, same posture as isFreshMovieEntry
    }
  }
```

- [ ] **Step 2: Verify live**

```javascript
console.log(await isTVSpinoffOrPrequel({ tmdbId: 60059 })); // Better Call Saul -- expect: true
console.log(await isTVSpinoffOrPrequel({ tmdbId: 1396 })); // Breaking Bad -- expect: false
```

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat: add TV spin-off/prequel blanket exclusion via TMDB keywords"
```

---

### Task 5: Wire category dispatch into `computeRecommendations`

**Files:**
- Modify: `index.html:4113-4241` (the `computeRecommendations` function body).

**Interfaces:**
- Consumes: all four TMDB functions from Tasks 1-4, plus the existing AniList functions (`fetchRecommendationsForSeed`, `fetchGenreAffinityCandidates`, `fetchPeakUnseenCandidates`, `isFreshFranchiseEntry`) and existing shared helpers (unchanged).
- Produces: `computeRecommendations(scope, category, rows, allRows)` now branches correctly for `category` in `{'anime', 'manga', 'western', 'movie'}`. No change to its external signature or return shape (`{ becauseYouLiked, overallTaste, peakUnseen }`), so `loadRecommendations` (its only caller) needs no changes.

This is the highest-risk task in the plan — it touches the function that the ALREADY-SHIPPED, ALREADY-VERIFIED Anime/Manga path depends on. The dispatch table pattern below is written so the `anime`/`manga` branches call the exact same functions, in the exact same way, as the current code — this task must not change Anime/Manga behavior at all.

- [ ] **Step 1: Read the current function in full before touching it**

```bash
grep -n "async function computeRecommendations" index.html
```

Read from that line to the function's closing `}` (roughly 130 lines) before making any edit — the seed loop, the tier-quota fill loop, the genre-affinity loop, and the peak-unseen loop each call an AniList-specific function and `isFreshFranchiseEntry` directly. Every one of those call sites needs to go through the new dispatch table instead.

- [ ] **Step 2: Add the dispatch table immediately before `computeRecommendations`**

```javascript
  // One entry per Recommendations category, so computeRecommendations'
  // shared orchestration (tier quotas, cross-section dedup, watchlist
  // flagging, caching) doesn't need to know which API or franchise-check
  // strategy backs a given category. `mediaType` is passed through to
  // whichever fetch functions need it (AniList's `type`, TMDB's
  // `mediaType` path segment) -- named generically here since the two
  // source families use it for different literal values.
  const RECOMMENDATION_SOURCES = {
    anime: {
      mediaType: 'ANIME',
      fetchSeed: (seed, mediaType) => fetchRecommendationsForSeed(seed, mediaType),
      fetchGenreAffinity: (genres, mediaType, count) => fetchGenreAffinityCandidates(genres, mediaType, count),
      fetchPeakUnseen: (mediaType, count) => fetchPeakUnseenCandidates(mediaType, count),
      isFreshEntry: (candidate, alreadyHave) => isFreshFranchiseEntry(candidate, alreadyHave),
    },
    manga: {
      mediaType: 'MANGA',
      fetchSeed: (seed, mediaType) => fetchRecommendationsForSeed(seed, mediaType),
      fetchGenreAffinity: (genres, mediaType, count) => fetchGenreAffinityCandidates(genres, mediaType, count),
      fetchPeakUnseen: (mediaType, count) => fetchPeakUnseenCandidates(mediaType, count),
      isFreshEntry: (candidate, alreadyHave) => isFreshFranchiseEntry(candidate, alreadyHave),
    },
    movie: {
      mediaType: 'movie',
      fetchSeed: (seed, mediaType) => fetchTMDBRecommendationsFor(seed.title, mediaType),
      fetchGenreAffinity: (genres, mediaType, count) => fetchTMDBGenreAffinityCandidates(genres, mediaType, count),
      fetchPeakUnseen: (mediaType, count) => fetchTMDBPeakUnseenCandidates(mediaType, count),
      isFreshEntry: (candidate, alreadyHave) => isFreshMovieEntry(candidate, alreadyHave),
    },
    western: {
      mediaType: 'tv',
      fetchSeed: (seed, mediaType) => fetchTMDBRecommendationsFor(seed.title, mediaType),
      fetchGenreAffinity: (genres, mediaType, count) => fetchTMDBGenreAffinityCandidates(genres, mediaType, count),
      fetchPeakUnseen: (mediaType, count) => fetchTMDBPeakUnseenCandidates(mediaType, count),
      // No structured franchise data for TV at all (see
      // isTVSpinoffOrPrequel's comment) -- every candidate passes this
      // check; the blanket spin-off/prequel exclusion runs separately,
      // ONLY against the small finalist set, after quotas are filled
      // (Step 4 below), not per-raw-candidate here.
      isFreshEntry: async () => true,
    },
  };
```

- [ ] **Step 3: Replace the hardcoded `type` line and every direct function call**

Replace:
```javascript
    const type = category === 'anime' ? 'ANIME' : 'MANGA';
```
with:
```javascript
    const source = RECOMMENDATION_SOURCES[category];
    const type = source.mediaType;
```

Then, within the function body:
- Every `fetchRecommendationsForSeed(seed, type)` → `source.fetchSeed(seed, type)`
- Every `fetchGenreAffinityCandidates(topGenres, type, ...)` → `source.fetchGenreAffinity(topGenres, type, ...)`
- Every `fetchPeakUnseenCandidates(type, ...)` → `source.fetchPeakUnseen(type, ...)`
- Every `isFreshFranchiseEntry(candidate, alreadyHave)` (there are multiple call sites — in the seed-candidate loop, the genre-affinity loop, and the peak-unseen loop) → `await source.isFreshEntry(candidate, alreadyHave)`. **These loops are not currently `async`-aware at these call sites for the anime/manga path since `isFreshFranchiseEntry` was synchronous** — since `isFreshMovieEntry` is async (it makes a network call), every one of these call sites' enclosing loop must already be (and is) inside an `async function` with `for...of`/plain `for` (not `.filter()`/`.some()`, which don't await correctly) — confirm each site is a plain `for` loop already (it is, per the existing peak-unseen and genre-affinity loops added in earlier Recommendations work), and add `await` in front of the `source.isFreshEntry(...)` call.
- The one call site that uses `.filter()` with `isFreshFranchiseEntry` inline (the seed-candidate `bySeedTitle` building pass, `candidates.forEach(candidate => { ... if (!isFreshFranchiseEntry(candidate, alreadyHave)) return; ...})`) needs converting from `.forEach()` to a plain `for...of` loop so it can `await`:

```javascript
    // was: candidates.forEach(candidate => { ... });
    for (const candidate of candidates) {
      if (candidateMatchesAny(candidate, alreadyHave)) continue;
      if (!(await source.isFreshEntry(candidate, alreadyHave))) continue;
      const titleKey = normalizeTitle(candidate.title);
      if (dismissed.has(externalIdFor(candidate))) continue;
      const existing = bySeedTitle.get(titleKey);
      if (existing) {
        existing.seedCount += 1;
        existing.bestSeedRating = Math.max(existing.bestSeedRating, seed.effectiveRating);
      } else {
        bySeedTitle.set(titleKey, { item: candidate, seedCount: 1, bestSeedRating: seed.effectiveRating, seedTitle: seed.title });
      }
    }
```

(Note: this loop is nested inside the outer `seedResults.forEach((candidates, i) => {...})` — that outer one also needs converting to a `for` loop with an index variable, since the inner body now awaits.)

- [ ] **Step 4: Add the TV blanket spin-off/prequel filter as a post-pass**

At the very end of `computeRecommendations`, immediately before the `const sections = { becauseYouLiked, overallTaste, peakUnseen };` line, add:

```javascript
    // TV can't check a specific candidate against a specific parent (see
    // RECOMMENDATION_SOURCES.western's isFreshEntry comment) -- instead,
    // blanket-filter the already-quota-filled finalist arrays. Filtering
    // AFTER quotas fill (rather than per-raw-candidate during the main
    // loops above) keeps this to ~10-30 keyword lookups total instead of
    // one per raw candidate (30-50+ per section) -- no backfill for a
    // removed slot, same "a tier just contributes what it has" philosophy
    // as the rest of this function's quota logic.
    if (category === 'western') {
      const filterSpinoffs = async (list) => {
        const kept = [];
        for (const item of list) {
          if (!(await isTVSpinoffOrPrequel(item))) kept.push(item);
        }
        return kept;
      };
      becauseYouLiked = await filterSpinoffs(becauseYouLiked);
      overallTaste = await filterSpinoffs(overallTaste);
      peakUnseen = await filterSpinoffs(peakUnseen);
    }
```

This requires `becauseYouLiked`, `overallTaste`, and `peakUnseen` to be declared `let` rather than `const` (check their declarations earlier in the function and change `const becauseYouLiked = []` etc. to `let` if not already).

- [ ] **Step 5: Verify the Anime/Manga path is unchanged**

```javascript
// Same regression check used earlier this session (2026-09-13) to verify the 30/30/40 tier split
const rows = [/* ... 10-13 synthetic anime rows spanning rating tiers, as used earlier this session ... */];
const sections = await computeRecommendations('karl', 'anime', rows, rows);
console.log(sections.becauseYouLiked.length, sections.overallTaste.length, sections.peakUnseen.length);
// Expect: same shape/counts as before this task's changes -- if this regresses, the refactor broke something and must be fixed before proceeding
```

- [ ] **Step 6: Verify Movie and Western paths work end-to-end**

```javascript
const movieRows = [
  { id: 'toy-story', title: 'Toy Story', category: 'movie', scope: 'karl', rating: 5, listStatus: 'watching', inTierPool: true, genres: ['Animation','Family'], allRatings: [{user_id:'x',rating:5}] },
  // ... several more rated movie rows to clear MIN_RATED_FOR_AFFINITY (5) ...
];
const movieSections = await computeRecommendations('karl', 'movie', movieRows, movieRows);
console.log(movieSections);
// Expect: becauseYouLiked/overallTaste/peakUnseen all populated, no Toy Story 2/3 leaking through without Toy Story tracked as a prerequisite (there isn't one here, so if a later Toy Story appears it should ONLY be because it's NOT gated -- verify by explicitly checking a sequel case per Task 3's own verification)

const tvRows = [
  { id: 'breaking-bad', title: 'Breaking Bad', category: 'western', scope: 'karl', rating: 5, listStatus: 'watching', inTierPool: true, genres: ['Drama','Crime'], allRatings: [{user_id:'x',rating:5}] },
  // ... several more rated western rows ...
];
const tvSections = await computeRecommendations('karl', 'western', tvRows, tvRows);
console.log(tvSections);
// Expect: "Better Call Saul" does NOT appear in any section (spin-off-tagged), even though Breaking Bad is tracked
```

- [ ] **Step 7: Commit**

```bash
git add index.html
git commit -m "feat: wire Western/Movie categories into computeRecommendations"
```

---

### Task 6: UI — Western/Movies sub-tabs and category-aware watchlist status

**Files:**
- Modify: `index.html` — `renderRecommendationsTab` (search `async function renderRecommendationsTab`) and the `isWatchlistStatus` definitions inside `computeRecommendations` and `openShowDetailModal` (both currently branch only on `category === 'anime' ? 'watchlist' : 'plan_to_read'`).

**Interfaces:**
- Consumes: `setRecCategory` (existing, already generic — just sets `activeRecCategory` and re-renders, no change needed).
- Produces: two new working sub-tab buttons; `rows`/`allRows` filtering and watchlist-status detection correctly handles `'western'`/`'movie'` (both use `shows` table, `list_status: 'watchlist'` — same as anime, NOT `'plan_to_read'`, which is manga/manhwa/book/webnovel-only).

- [ ] **Step 1: Fix the two `isWatchlistStatus` definitions**

Both currently read:
```javascript
    const isWatchlistStatus = category === 'anime' ? (s) => s === 'watchlist' : (s) => s === 'plan_to_read';
```

`'plan_to_read'` is specific to `written_media` (manga/manhwa/book/webnovel) — `shows` rows (anime, western, movie) all use `'watchlist'`. Replace both occurrences with:
```javascript
    const isWatchlistStatus = category === 'manga' ? (s) => s === 'plan_to_read' : (s) => s === 'watchlist';
```

- [ ] **Step 2: Add the sub-tab buttons and category-to-fetch-source wiring in `renderRecommendationsTab`**

Find:
```javascript
    const allRows = activeRecCategory === 'anime' ? await fetchShows(activeScope) : await fetchWrittenMedia(activeScope);
    const rows = activeRecCategory === 'anime'
      ? allRows.filter(s => s.category === 'anime')
      : allRows.filter(m => m.category === 'manga' || m.category === 'manhwa');
```

Replace with:
```javascript
    const isShowsCategory = activeRecCategory === 'anime' || activeRecCategory === 'western' || activeRecCategory === 'movie';
    const allRows = isShowsCategory ? await fetchShows(activeScope) : await fetchWrittenMedia(activeScope);
    const rows = isShowsCategory
      ? allRows.filter(s => s.category === activeRecCategory)
      : allRows.filter(m => m.category === 'manga' || m.category === 'manhwa');
```

Find the sub-tab buttons markup (inside the same function's template string):
```javascript
        <button class="tab-btn sub-tab-btn${activeRecCategory === 'anime' ? ' active' : ''}" onclick="setRecCategory('anime')">Anime</button>
        <button class="tab-btn sub-tab-btn${activeRecCategory === 'manga' ? ' active' : ''}" onclick="setRecCategory('manga')">Manga / Manhwa</button>
```

Add two more buttons directly after:
```javascript
        <button class="tab-btn sub-tab-btn${activeRecCategory === 'western' ? ' active' : ''}" onclick="setRecCategory('western')">Western</button>
        <button class="tab-btn sub-tab-btn${activeRecCategory === 'movie' ? ' active' : ''}" onclick="setRecCategory('movie')">Movies</button>
```

- [ ] **Step 3: Verify live end-to-end in the browser**

```javascript
currentProfile = { id: 'x', display_name: 'Karl' };
activeScope = 'karl';
document.getElementById('app-header').style.display = '';
document.getElementById('signed-out-screen').style.display = 'none';
document.getElementById('app-content').style.display = '';
// mock fetchShows with a synthetic western/movie library (5+ rated rows per category to clear MIN_RATED_FOR_AFFINITY)
fetchShows = async () => [ /* synthetic rows, mix of category: 'western' and 'movie' */ ];
document.querySelector('button.tab-btn[data-toptab="recommendations"]').click();
```

Then click the new "Western" and "Movies" sub-tab buttons in the rendered page and screenshot each — confirm all three sections render with real TMDB data, no console errors, and a watchlisted movie/show shows the disabled "On Watchlist" button (reusing Task 5's/the existing `findWatchlistMatch` logic, which needs no changes for this task since it's already data-source-agnostic).

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: add Western and Movies sub-tabs to Recommendations tab"
```

---

## Self-Review Notes

- **Spec coverage**: Task 1-2 cover "New TMDB fetch functions"; Task 3 covers "Movies" franchise-tail; Task 4 covers "TV" franchise-tail; Task 5 covers the orchestration wiring; Task 6 covers "UI & category plumbing". The spec's "verify DB constraint" item was resolved during planning (confirmed live, no migration needed — see plan header's Tech Stack line) rather than deferred to a task, since it was a pure verification step with a real yes/no answer already in hand.
- **`vote_count.gte=200` in Task 2** is explicitly flagged as unverified (mirrors how `PEAK_MIN_POPULARITY` was picked) — Task 6's live verification step is the natural point to eyeball this against real results and adjust if it's letting through obscurities or excluding well-known titles; not treated as a blocking placeholder since the spec explicitly deferred this exact number to implementation-time spot-checking.
- **Type consistency check**: `RECOMMENDATION_SOURCES[category].mediaType` values (`'ANIME'`/`'MANGA'` for AniList, `'movie'`/`'tv'` for TMDB) are passed straight through to each source's own fetch functions, which already expect exactly those literal values (AniList's GraphQL `MediaType` enum is uppercase; TMDB's URL path segments are lowercase) — confirmed consistent across Tasks 1-5.
