# Book Recommendations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Books" sub-tab to the existing Recommendations tab, backed by Open Library's author-search and subject-search endpoints (no per-title "similar books" API exists), reusing the shared cache/dismissal/render infrastructure already built for Anime/Manga/Western/Movies with two small generalizations instead of a parallel system.

**Architecture:** A new `computeBookRecommendations` function runs its own two-section pass (author affinity, genre/subject affinity) parallel to — not merged into — `computeRecommendations`, since Open Library has neither a seed-based similarity endpoint nor a popularity ranking, so the existing three-section/tier-weighted orchestration doesn't fit. Four small generalizations in shared code (`externalIdFor`, `filterDismissedSections`, the `written_media` insert in `addRecommendationItemToWatchlist`/`startRecommendationItemNow`, and `renderRecSectionGrid`'s reason-text branch) let the existing render/cache/dismiss layer serve both shapes without duplicating it.

**Tech Stack:** Vanilla JS in `index.html` (no build step), Open Library's free no-key `search.json` and `subjects/{slug}.json` endpoints, Supabase (`recommendations_cache`, `dismissed_recommendations` — already `category text` with no enum constraint, per the western/movie plan's live verification of the same column).

**Spec:** `docs/superpowers/specs/2026-09-13-book-recommendations-design.md`

## Global Constraints

- No test framework in this project — verification is Playwright driving the real `index.html` (served via `python -m http.server`) with `fetchWrittenMedia` mocked to a synthetic library, and REAL network calls to Open Library (no mocking) — same pattern used throughout this project's recommendations work.
- Sequential (not `Promise.all`) network calls in any loop over multiple seeds/genres, with a small delay between requests — matches the existing rate-limit discipline for AniList/TMDB/Jikan calls elsewhere in this file.
- `category` value for this feature is `'book'` (already used elsewhere in this codebase for `written_media` rows — do not invent a new category string).
- Webnovels are explicitly out of scope (no free catalog exists) — do not add a webnovel branch anywhere in this plan.
- Every new function gets a one-line comment only if the WHY isn't obvious from the name + existing surrounding comments — follow this file's existing comment density, don't under- or over-comment.

---

### Task 1: Open Library fetch functions for recommendations

**Files:**
- Modify: `index.html` — insert a new `// ── Recommendations: Open Library fetch (books) ──` section directly after the TV franchise-check comment block (search for `// ── Recommendations: orchestration, cache, dismissal ──` — the new functions go immediately before that line, after the existing `isFreshMovieEntry`/TV-franchise comment block).

**Interfaces:**
- Consumes: nothing new (no existing helper reused here — these are the book-domain equivalent of `fetchTMDBRecommendationsFor`/`fetchTMDBGenreAffinityCandidates`).
- Produces: `async function fetchOpenLibraryAuthorCandidates(authorName, count)` and `async function fetchOpenLibrarySubjectCandidates(genre, count)`. Both return an array of candidate objects shaped `{ olid, title, author, coverUrl, genres, score, reason, reasonDetail }` on success (possibly empty), or `null` if the fetch itself failed — same three-way contract (`null` = failed, `[]` = succeeded-but-empty) as every other fetch function in this file.

- [ ] **Step 1: Write the two mapper functions and both fetchers**

```javascript
  // ── Recommendations: Open Library fetch (books) ──
  // Open Library has neither a per-title "similar books" endpoint (like
  // AniList's/TMDB's recommendations field) nor a general popularity
  // ranking -- only author search and subject/genre search. So Books gets
  // exactly two candidate sources instead of the three-source pattern used
  // by every other category (see computeBookRecommendations below).

  // Author-search and subject-search results come back with DIFFERENT
  // field names for the same concepts (cover_i vs cover_id, author_name[]
  // vs authors[].name) -- kept as two small mapper functions rather than
  // one "smart" mapper that branches on shape.
  function openLibrarySearchDocToCandidate(doc, reasonDetail) {
    return {
      olid: doc.key,
      title: doc.title,
      author: doc.author_name?.[0] || null,
      coverUrl: doc.cover_i ? `https://covers.openlibrary.org/b/id/${doc.cover_i}-L.jpg` : null,
      genres: (doc.subject || []).slice(0, 5),
      score: null,
      reason: 'by_author',
      reasonDetail,
    };
  }

  // The subjects endpoint doesn't return each work's own tag list -- the
  // subject we searched under IS a genre this book is tagged with, so it's
  // used directly as `genres` rather than left empty.
  function openLibrarySubjectWorkToCandidate(work, reasonDetail) {
    return {
      olid: work.key,
      title: work.title,
      author: work.authors?.[0]?.name || null,
      coverUrl: work.cover_id ? `https://covers.openlibrary.org/b/id/${work.cover_id}-L.jpg` : null,
      genres: [reasonDetail],
      score: null,
      reason: 'affinity',
      reasonDetail,
    };
  }

  async function fetchOpenLibraryAuthorCandidates(authorName, count) {
    try {
      const res = await fetch(`https://openlibrary.org/search.json?author=${encodeURIComponent(authorName)}&limit=20&fields=title,author_name,cover_i,subject,key`);
      if (!res.ok) return null;
      const json = await res.json();
      const docs = json.docs || [];
      return docs.slice(0, count).map(d => openLibrarySearchDocToCandidate(d, authorName));
    } catch (e) {
      console.warn('Open Library author search failed for', authorName, e);
      return null;
    }
  }

  // Open Library subject slugs are lowercase with underscores, e.g.
  // "Science Fiction" -> "science_fiction" (documented convention, see
  // CLAUDE.md's book-lookup section).
  function subjectSlug(genre) {
    return genre.toLowerCase().trim().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  }

  async function fetchOpenLibrarySubjectCandidates(genre, count) {
    try {
      const res = await fetch(`https://openlibrary.org/subjects/${subjectSlug(genre)}.json?limit=${Math.max(count, 20)}`);
      if (!res.ok) return null;
      const json = await res.json();
      const works = json.works || [];
      return works.map(w => openLibrarySubjectWorkToCandidate(w, genre));
    } catch (e) {
      console.warn('Open Library subject search failed for', genre, e);
      return null;
    }
  }
```

- [ ] **Step 2: Verify live against real Open Library data**

Serve the file locally:

```bash
python -m http.server 8791
```

Then in a Playwright/browser console against `http://localhost:8791/index.html`:

```javascript
const authorCands = await fetchOpenLibraryAuthorCandidates('Brandon Sanderson', 10);
console.log(authorCands.length, authorCands[0]);
// Expect: an array of candidate objects, each with olid/title/author/coverUrl/genres, reason: 'by_author'

const genreCands = await fetchOpenLibrarySubjectCandidates('Science Fiction', 10);
console.log(genreCands.length, genreCands[0]);
// Expect: an array of candidate objects, each with genres: ['Science Fiction'], reason: 'affinity'

const badAuthor = await fetchOpenLibraryAuthorCandidates('zzzznonexistentauthor12345', 10);
console.log(badAuthor);
// Expect: [] (search succeeds with 0 docs, NOT null -- Open Library doesn't 404 on no results)
```

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat: add Open Library author/subject fetch functions for book recommendations"
```

---

### Task 2: Generalize shared recommendation code for a non-shows, non-manga category

**Files:**
- Modify: `index.html:4454-4459` (`externalIdFor`), `index.html:4750-4758` (`filterDismissedSections`), `index.html:7765-7813` (`addRecommendationItemToWatchlist` and `startRecommendationItemNow`), `index.html:7832-7847` (`renderRecSectionGrid`'s reason-text branch).

**Interfaces:**
- Consumes: nothing new.
- Produces: `externalIdFor` now also matches `item.olid`; `filterDismissedSections(sections, dismissed, keys)` takes an explicit `keys` array (defaulting to the existing three-section shape, so every current caller is unaffected); `addRecommendationItemToWatchlist`/`startRecommendationItemNow` write the passed-in `category` (not a hardcoded `'manga'`) and an `author` field to `written_media`; `renderRecSectionGrid` renders a `'by_author'` reason.

This task must not change Anime/Manga/Western/Movie behavior — every change here is either additive (a new `if` branch checked before existing ones fall through unchanged) or defaults to today's exact behavior when called without the new parameter.

- [ ] **Step 1: Add the Open Library case to `externalIdFor`**

Find (`index.html:4454`):
```javascript
  function externalIdFor(item) {
    if (item.anilistId) return String(item.anilistId);
    if (item.tmdbId) return `tmdb:${item.tmdbId}`;
    if (item.malId) return `mal:${item.malId}`;
    return `title:${normalizeTitle(item.title)}`;
  }
```

Replace with:
```javascript
  function externalIdFor(item) {
    if (item.anilistId) return String(item.anilistId);
    if (item.tmdbId) return `tmdb:${item.tmdbId}`;
    if (item.malId) return `mal:${item.malId}`;
    if (item.olid) return `olid:${item.olid}`;
    return `title:${normalizeTitle(item.title)}`;
  }
```

- [ ] **Step 2: Generalize `filterDismissedSections` to take explicit section keys**

Find (`index.html:4750`):
```javascript
  function filterDismissedSections(sections, dismissed) {
    const safe = Array.isArray(sections) || !sections ? {} : sections;
    const filterOne = (list) => (list || []).filter(item => !dismissed.has(externalIdFor(item)));
    return {
      becauseYouLiked: filterOne(safe.becauseYouLiked),
      overallTaste: filterOne(safe.overallTaste),
      peakUnseen: filterOne(safe.peakUnseen),
    };
  }
```

Replace with:
```javascript
  function filterDismissedSections(sections, dismissed, keys = ['becauseYouLiked', 'overallTaste', 'peakUnseen']) {
    const safe = Array.isArray(sections) || !sections ? {} : sections;
    const filterOne = (list) => (list || []).filter(item => !dismissed.has(externalIdFor(item)));
    const result = {};
    keys.forEach(key => { result[key] = filterOne(safe[key]); });
    return result;
  }
```

Every existing call site omits the third argument, so nothing else needs to change yet — Task 3 passes `['byAuthor', 'overallTaste']` for books.

- [ ] **Step 3: Fix the hardcoded `category: 'manga'` and missing `author` field**

Find (`index.html:7765`, inside `addRecommendationItemToWatchlist`):
```javascript
    } else {
      const { error } = await supabase.from('written_media').insert({
        title: item.title, category: 'manga', scope, cover_url: item.coverUrl, genres: item.genres, list_status: 'plan_to_read',
      });
      if (checkWriteError(error)) return false;
      invalidateWrittenMediaCache();
    }
```

Replace with:
```javascript
    } else {
      const { error } = await supabase.from('written_media').insert({
        title: item.title, category, scope, cover_url: item.coverUrl, genres: item.genres, author: item.author, list_status: 'plan_to_read',
      });
      if (checkWriteError(error)) return false;
      invalidateWrittenMediaCache();
    }
```

Find (`index.html:7790`, inside `startRecommendationItemNow`):
```javascript
    } else {
      const { error } = await supabase.from('written_media').insert({
        title: item.title, category: 'manga', scope, cover_url: item.coverUrl, genres: item.genres,
        list_status: 'reading', current_chapter: 0,
        last_updated: new Date().toISOString().slice(0, 10),
      });
      if (checkWriteError(error)) return false;
      invalidateWrittenMediaCache();
    }
```

Replace with:
```javascript
    } else {
      const { error } = await supabase.from('written_media').insert({
        title: item.title, category, scope, cover_url: item.coverUrl, genres: item.genres, author: item.author,
        list_status: 'reading', current_chapter: 0,
        last_updated: new Date().toISOString().slice(0, 10),
      });
      if (checkWriteError(error)) return false;
      invalidateWrittenMediaCache();
    }
```

(`category` here is the function's own parameter, already `'manga'` for manga candidates and `'book'` for book candidates — no caller changes needed. `item.author` is `undefined` for manga candidates, so this is a harmless no-op there, same column stays null as it does today.)

- [ ] **Step 4: Add the `'by_author'` reason branch to `renderRecSectionGrid`**

Find (`index.html:7839`):
```javascript
      let reasonHTML;
      if (item.reason === 'because_rated') {
        reasonHTML = `Because you rated <strong>${escapeHTML(item.reasonDetail)}</strong>${item.sourceRating != null ? ` ★${item.sourceRating}` : ''}`;
      } else if (item.reason === 'affinity') {
        reasonHTML = `Matches your ${escapeHTML(item.reasonDetail)} taste`;
      } else {
        reasonHTML = `Popular pick you haven't seen yet`;
      }
```

Replace with:
```javascript
      let reasonHTML;
      if (item.reason === 'because_rated') {
        reasonHTML = `Because you rated <strong>${escapeHTML(item.reasonDetail)}</strong>${item.sourceRating != null ? ` ★${item.sourceRating}` : ''}`;
      } else if (item.reason === 'by_author') {
        reasonHTML = `More by <strong>${escapeHTML(item.reasonDetail)}</strong>`;
      } else if (item.reason === 'affinity') {
        reasonHTML = `Matches your ${escapeHTML(item.reasonDetail)} taste`;
      } else {
        reasonHTML = `Popular pick you haven't seen yet`;
      }
```

- [ ] **Step 5: Verify the Anime/Manga/Western/Movie paths are unchanged**

```javascript
// externalIdFor: existing cases still resolve exactly as before
console.log(externalIdFor({ anilistId: 123 })); // '123'
console.log(externalIdFor({ tmdbId: 456 })); // 'tmdb:456'
console.log(externalIdFor({ olid: '/works/OL123W' })); // 'olid:/works/OL123W'

// filterDismissedSections: default keys unchanged
const filtered = filterDismissedSections({ becauseYouLiked: [{ title: 'X', anilistId: 1 }], overallTaste: [], peakUnseen: [] }, new Set());
console.log(Object.keys(filtered)); // ['becauseYouLiked', 'overallTaste', 'peakUnseen']
```

Then re-open the Recommendations tab in the running app for the Anime and Manga sub-tabs and confirm cards, dismiss, and "+ Watchlist"/"Start Now" still work exactly as before (no regression) — this is the same manual smoke check used after every prior change to this shared code in this project.

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "refactor: generalize recommendation cache/dismiss/insert code for a non-shows, non-manga category"
```

---

### Task 3: `computeBookRecommendations` orchestration + wire into `loadRecommendations`

**Files:**
- Modify: `index.html` — add the new function directly after `computeRecommendations` (search for `function filterDismissedSections`, the new function is inserted immediately before that line). Modify `index.html:4768-4787` (`loadRecommendations`).

**Interfaces:**
- Consumes: `pickRecommendationSeeds`, `computeAffinity`, `buildAlreadyHaveTitles`, `candidateMatchesAny`, `normalizeTitle`, `findWatchlistMatch`, `getDismissedRecommendationIds`, `externalIdFor` (all existing, unchanged), `fetchOpenLibraryAuthorCandidates`/`fetchOpenLibrarySubjectCandidates` (Task 1), `sleep` (existing helper defined at `index.html:3609`).
- Produces: `async function computeBookRecommendations(scope, rows, allRows)` returning `{ byAuthor, overallTaste }` and upserting that shape into `recommendations_cache` with `category: 'book'`. `loadRecommendations` now dispatches to it for `category === 'book'`.

- [ ] **Step 1: Write `computeBookRecommendations`**

```javascript
  // Small delay between sequential Open Library requests -- same
  // rate-limit-friendly discipline as every other external-API loop in
  // this file (checkNewSeasons, checkMangaSequels, computeRecommendations'
  // own seed loop), even though Open Library has no documented rate limit
  // as aggressive as AniList/Jikan's.
  const OPEN_LIBRARY_REQUEST_DELAY_MS = 400;

  // Books get their own, simpler orchestration instead of a branch inside
  // computeRecommendations -- that function's tier-weighted seed quotas,
  // cross-section franchise filtering, and three-section shape are all
  // built around AniList/TMDB's per-title similarity + popularity data,
  // neither of which Open Library has. Two sections only: an author-search
  // pass (seeded from your top-rated books' authors) and a subject-search
  // pass (seeded from your top-rated genres) -- see the design spec's
  // "Why this can't reuse computeRecommendations as-is" section.
  async function computeBookRecommendations(scope, rows, allRows) {
    const alreadyHave = buildAlreadyHaveTitles(allRows.filter(r => r.listStatus !== 'plan_to_read'));
    const watchlistRows = allRows.filter(r => r.listStatus === 'plan_to_read');
    const dismissed = await getDismissedRecommendationIds(scope, 'book');
    const usedTitles = new Set();

    // ── More from authors you love ──
    const seeds = pickRecommendationSeeds(rows, { scope });
    const seedAuthors = [...new Set(seeds.map(s => s.author).filter(Boolean))];
    let byAuthor = [];
    let byAuthorFailed = seedAuthors.length === 0;
    for (const author of seedAuthors) {
      const candidates = await fetchOpenLibraryAuthorCandidates(author, REC_SECTION_CAP);
      if (candidates !== null) {
        byAuthorFailed = false;
        for (const candidate of candidates) {
          if (byAuthor.length >= REC_SECTION_CAP) break;
          if (candidateMatchesAny(candidate, alreadyHave)) continue;
          const titleKey = normalizeTitle(candidate.title);
          if (usedTitles.has(titleKey) || dismissed.has(externalIdFor(candidate))) continue;
          usedTitles.add(titleKey);
          const watchlistMatch = findWatchlistMatch(candidate, watchlistRows);
          byAuthor.push({ ...candidate, sourceRating: null, alreadyOnWatchlist: !!watchlistMatch, watchlistTags: watchlistMatch?.tags || [] });
        }
      }
      await sleep(OPEN_LIBRARY_REQUEST_DELAY_MS);
    }

    // ── Matches your taste ──
    const affinity = computeAffinity(rows);
    const topGenres = Object.entries(affinity.genreAvg).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([g]) => g);
    let overallTaste = [];
    let overallTasteFailed = topGenres.length === 0;
    for (const genre of topGenres) {
      const candidates = await fetchOpenLibrarySubjectCandidates(genre, REC_SECTION_CAP);
      if (candidates !== null) {
        overallTasteFailed = false;
        for (const candidate of candidates) {
          if (overallTaste.length >= REC_SECTION_CAP) break;
          if (candidateMatchesAny(candidate, alreadyHave)) continue;
          const titleKey = normalizeTitle(candidate.title);
          if (usedTitles.has(titleKey) || dismissed.has(externalIdFor(candidate))) continue;
          usedTitles.add(titleKey);
          const watchlistMatch = findWatchlistMatch(candidate, watchlistRows);
          overallTaste.push({ ...candidate, sourceRating: null, alreadyOnWatchlist: !!watchlistMatch, watchlistTags: watchlistMatch?.tags || [] });
        }
      }
      await sleep(OPEN_LIBRARY_REQUEST_DELAY_MS);
    }

    if (byAuthorFailed && overallTasteFailed) {
      throw new Error('computeBookRecommendations: both sections failed to fetch');
    }

    const sections = { byAuthor, overallTaste };
    const { error } = await supabase.from('recommendations_cache')
      .upsert({ scope, category: 'book', data: sections, updated_at: new Date().toISOString() }, { onConflict: 'scope,category' });
    checkWriteError(error);
    return sections;
  }
```

- [ ] **Step 2: Wire the dispatch into `loadRecommendations`**

Find (`index.html:4768`):
```javascript
  async function loadRecommendations(scope, category, rows, allRows, { force = false } = {}) {
    if (!force) {
      const { data, error } = await supabase.from('recommendations_cache')
        .select('data, updated_at').eq('scope', scope).eq('category', category).maybeSingle();
      if (!error && data && (Date.now() - new Date(data.updated_at).getTime()) < REC_CACHE_MAX_AGE_MS) {
        const dismissed = await getDismissedRecommendationIds(scope, category);
        return { sections: filterDismissedSections(data.data, dismissed), stale: false };
      }
    }
    try {
      const sections = await computeRecommendations(scope, category, rows, allRows);
      return { sections, stale: false };
    } catch (e) {
      console.warn('Recommendations recompute failed, falling back to last cache', e);
      const { data } = await supabase.from('recommendations_cache')
        .select('data').eq('scope', scope).eq('category', category).maybeSingle();
      const dismissed = await getDismissedRecommendationIds(scope, category);
      return { sections: filterDismissedSections(data?.data, dismissed), stale: true };
    }
  }
```

Replace with:
```javascript
  async function loadRecommendations(scope, category, rows, allRows, { force = false } = {}) {
    const sectionKeys = category === 'book' ? ['byAuthor', 'overallTaste'] : ['becauseYouLiked', 'overallTaste', 'peakUnseen'];
    if (!force) {
      const { data, error } = await supabase.from('recommendations_cache')
        .select('data, updated_at').eq('scope', scope).eq('category', category).maybeSingle();
      if (!error && data && (Date.now() - new Date(data.updated_at).getTime()) < REC_CACHE_MAX_AGE_MS) {
        const dismissed = await getDismissedRecommendationIds(scope, category);
        return { sections: filterDismissedSections(data.data, dismissed, sectionKeys), stale: false };
      }
    }
    try {
      const sections = category === 'book'
        ? await computeBookRecommendations(scope, rows, allRows)
        : await computeRecommendations(scope, category, rows, allRows);
      return { sections, stale: false };
    } catch (e) {
      console.warn('Recommendations recompute failed, falling back to last cache', e);
      const { data } = await supabase.from('recommendations_cache')
        .select('data').eq('scope', scope).eq('category', category).maybeSingle();
      const dismissed = await getDismissedRecommendationIds(scope, category);
      return { sections: filterDismissedSections(data?.data, dismissed, sectionKeys), stale: true };
    }
  }
```

- [ ] **Step 3: Verify live**

```javascript
const bookRows = [
  { id: 'b1', title: 'Mistborn', category: 'book', scope: 'karl', rating: 5, listStatus: 'read', genres: ['Fantasy'], author: 'Brandon Sanderson', allRatings: [{ user_id: 'x', rating: 5 }] },
  { id: 'b2', title: 'The Way of Kings', category: 'book', scope: 'karl', rating: 4.5, listStatus: 'read', genres: ['Fantasy'], author: 'Brandon Sanderson', allRatings: [{ user_id: 'x', rating: 4.5 }] },
  { id: 'b3', title: 'Dune', category: 'book', scope: 'karl', rating: 5, listStatus: 'read', genres: ['Science Fiction'], author: 'Frank Herbert', allRatings: [{ user_id: 'x', rating: 5 }] },
  { id: 'b4', title: 'Foundation', category: 'book', scope: 'karl', rating: 4, listStatus: 'read', genres: ['Science Fiction'], author: 'Isaac Asimov', allRatings: [{ user_id: 'x', rating: 4 }] },
  { id: 'b5', title: 'Project Hail Mary', category: 'book', scope: 'karl', rating: 4, listStatus: 'read', genres: ['Science Fiction'], author: 'Andy Weir', allRatings: [{ user_id: 'x', rating: 4 }] },
];
const sections = await computeBookRecommendations('karl', bookRows, bookRows);
console.log(sections.byAuthor.length, sections.overallTaste.length);
// Expect: byAuthor has other Sanderson/Herbert/Asimov/Weir books, none matching the 5 titles above;
// overallTaste has Fantasy/Science Fiction books not already in the list

const loaded = await loadRecommendations('karl', 'book', bookRows, bookRows, { force: true });
console.log(loaded.sections.byAuthor.length, loaded.sections.overallTaste.length, loaded.stale);
// Expect: same shape, stale: false
```

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: add computeBookRecommendations and wire it into loadRecommendations"
```

---

### Task 4: UI — Books sub-tab with a two-section layout

**Files:**
- Modify: `index.html:7902-7955` (`renderRecommendationsTab`).

**Interfaces:**
- Consumes: `loadRecommendations` (Task 3), `renderRecSectionGrid` (Task 2), `MIN_RATED_FOR_AFFINITY` (existing).
- Produces: a working "Books" sub-tab button; `activeRecCategory === 'book'` renders exactly two section grids instead of three, with book-specific titles.

- [ ] **Step 1: Extend the rows/allRows filtering and sub-tab buttons**

Find (`index.html:7904`):
```javascript
    const isShowsCategory = activeRecCategory === 'anime' || activeRecCategory === 'western' || activeRecCategory === 'movie';
    const allRows = isShowsCategory ? await fetchShows(activeScope) : await fetchWrittenMedia(activeScope);
    const rows = isShowsCategory
      ? allRows.filter(s => s.category === activeRecCategory)
      : allRows.filter(m => m.category === 'manga' || m.category === 'manhwa');
```

Replace with:
```javascript
    const isShowsCategory = activeRecCategory === 'anime' || activeRecCategory === 'western' || activeRecCategory === 'movie';
    const allRows = isShowsCategory ? await fetchShows(activeScope) : await fetchWrittenMedia(activeScope);
    const rows = isShowsCategory
      ? allRows.filter(s => s.category === activeRecCategory)
      : activeRecCategory === 'book'
        ? allRows.filter(m => m.category === 'book')
        : allRows.filter(m => m.category === 'manga' || m.category === 'manhwa');
```

Find the sub-tab buttons (`index.html:7923-7926`):
```javascript
        <button class="tab-btn sub-tab-btn${activeRecCategory === 'anime' ? ' active' : ''}" onclick="setRecCategory('anime')">Anime</button>
        <button class="tab-btn sub-tab-btn${activeRecCategory === 'manga' ? ' active' : ''}" onclick="setRecCategory('manga')">Manga / Manhwa</button>
        <button class="tab-btn sub-tab-btn${activeRecCategory === 'western' ? ' active' : ''}" onclick="setRecCategory('western')">Western</button>
        <button class="tab-btn sub-tab-btn${activeRecCategory === 'movie' ? ' active' : ''}" onclick="setRecCategory('movie')">Movies</button>
```

Add one more button directly after:
```javascript
        <button class="tab-btn sub-tab-btn${activeRecCategory === 'book' ? ' active' : ''}" onclick="setRecCategory('book')">Books</button>
```

- [ ] **Step 2: Branch the section markup and render calls on the book category**

Find (`index.html:7930-7937`):
```javascript
      ${belowThreshold ? `<p style="font-size:0.75rem; color:var(--muted); margin-bottom:1rem">Rate a few more shows to unlock "Because you liked" and "Matches your taste" recommendations.</p>` : `
        <div class="rec-section-title">Because you liked...</div>
        <div id="rec-grid-because" class="rec-grid"><p style="font-size:0.7rem; color:var(--muted)">Loading…</p></div>
        <div class="rec-section-title">Matches your overall taste</div>
        <div id="rec-grid-overall" class="rec-grid"><p style="font-size:0.7rem; color:var(--muted)">Loading…</p></div>
      `}
      <div class="rec-section-title">Peak stuff you haven't seen</div>
      <div id="rec-grid-peak" class="rec-grid"><p style="font-size:0.7rem; color:var(--muted)">Loading…</p></div>
    `;
```

Replace with:
```javascript
      ${belowThreshold ? `<p style="font-size:0.75rem; color:var(--muted); margin-bottom:1rem">Rate a few more shows to unlock "Because you liked" and "Matches your taste" recommendations.</p>` : activeRecCategory === 'book' ? `
        <div class="rec-section-title">More from authors you love</div>
        <div id="rec-grid-author" class="rec-grid"><p style="font-size:0.7rem; color:var(--muted)">Loading…</p></div>
        <div class="rec-section-title">Matches your taste</div>
        <div id="rec-grid-book-taste" class="rec-grid"><p style="font-size:0.7rem; color:var(--muted)">Loading…</p></div>
      ` : `
        <div class="rec-section-title">Because you liked...</div>
        <div id="rec-grid-because" class="rec-grid"><p style="font-size:0.7rem; color:var(--muted)">Loading…</p></div>
        <div class="rec-section-title">Matches your overall taste</div>
        <div id="rec-grid-overall" class="rec-grid"><p style="font-size:0.7rem; color:var(--muted)">Loading…</p></div>
      `}
      ${activeRecCategory === 'book' ? '' : `
      <div class="rec-section-title">Peak stuff you haven't seen</div>
      <div id="rec-grid-peak" class="rec-grid"><p style="font-size:0.7rem; color:var(--muted)">Loading…</p></div>
      `}
    `;
```

Find the render calls (`index.html:7950-7954`):
```javascript
    if (!belowThreshold) {
      renderRecSectionGrid('rec-grid-because', sections.becauseYouLiked);
      renderRecSectionGrid('rec-grid-overall', sections.overallTaste);
    }
    renderRecSectionGrid('rec-grid-peak', sections.peakUnseen);
```

Replace with:
```javascript
    if (!belowThreshold) {
      if (activeRecCategory === 'book') {
        renderRecSectionGrid('rec-grid-author', sections.byAuthor);
        renderRecSectionGrid('rec-grid-book-taste', sections.overallTaste);
      } else {
        renderRecSectionGrid('rec-grid-because', sections.becauseYouLiked);
        renderRecSectionGrid('rec-grid-overall', sections.overallTaste);
      }
    }
    if (activeRecCategory !== 'book') renderRecSectionGrid('rec-grid-peak', sections.peakUnseen);
```

- [ ] **Step 3: Verify live end-to-end in the browser**

```javascript
currentProfile = { id: 'x', display_name: 'Karl' };
activeScope = 'karl';
document.getElementById('app-header').style.display = '';
document.getElementById('signed-out-screen').style.display = 'none';
document.getElementById('app-content').style.display = '';
// mock fetchWrittenMedia with a synthetic book library (5+ rated books across 2-3 authors/genres, per Task 3's sample data)
fetchWrittenMedia = async () => [ /* synthetic book rows */ ];
document.querySelector('button.tab-btn[data-toptab="recommendations"]').click();
```

Click the new "Books" sub-tab button and screenshot the rendered page — confirm exactly two section grids render ("More from authors you love", "Matches your taste"), no "Peak stuff you haven't seen" section appears, no console errors, and dismissing a card or clicking "+ Watchlist" works (a "+ Watchlist" click should insert into `written_media` with `category: 'book'` and a populated `author` — verify via a Supabase read or by switching to the To-Read tab and confirming the new row shows the right author).

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: add Books sub-tab to Recommendations tab"
```

---

## Self-Review Notes

- **Spec coverage**: Task 1 covers "New Open Library fetch functions"; Task 2 covers "Fixes needed in shared code" (all four bullet points: `externalIdFor`, `filterDismissedSections`, the two hardcoded-`'manga'` inserts, `renderRecSectionGrid`'s reason text); Task 3 covers "Why this can't reuse `computeRecommendations`" + "What's reused as-is" (the actual `computeBookRecommendations` function and its `loadRecommendations` wiring); Task 4 covers "UI & category plumbing". Webnovels are confirmed out of scope in every task's file list (no webnovel branch introduced anywhere).
- **Placeholder scan**: no TBD/TODO — the one "verify before implementation" item from the spec (the `category`/enum constraint check) was already resolved by the western/movie plan's live verification of the same `recommendations_cache`/`dismissed_recommendations` columns, referenced in this plan's header rather than repeated as a task.
- **Type consistency check**: `computeBookRecommendations` returns `{ byAuthor, overallTaste }` — the exact two keys `loadRecommendations`'s `sectionKeys` branch and Task 4's render calls both reference (`sections.byAuthor`, `sections.overallTaste`). Candidate shape (`olid`, `title`, `author`, `coverUrl`, `genres`, `score`, `reason`, `reasonDetail`) is consistent across both Task 1 mapper functions, Task 3's dedup/push logic, and Task 2's `renderRecSectionGrid`/`externalIdFor` changes. `sourceRating: null` is set explicitly on every book candidate so `renderRecSectionGrid`'s existing `item.sourceRating != null` check (used only by the `because_rated` branch, never reached by book candidates) has no undefined-property risk.
