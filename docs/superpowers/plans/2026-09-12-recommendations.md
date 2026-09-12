# Recommendations (Anime + Manga/Manhwa) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Recommendations" tab suggesting anime and manga/manhwa the user doesn't already have tracked, based on AniList's community "if you liked X" data plus a genre/studio-affinity fallback, cached cross-device in Supabase.

**Architecture:** All new logic lives in `index.html` (the project's single-file convention — no build step, no separate JS files). Two new Supabase tables cache computed recommendation lists and dismissals per scope. A client-side pipeline resolves seed titles to AniList media via GraphQL, aggregates their `recommendations` field, falls back to a genre-affinity search when sparse, dedupes against everything already tracked, and writes the result to the cache table.

**Tech Stack:** Vanilla JS, Supabase JS v2 (already loaded via CDN in `index.html`), AniList GraphQL API, Jikan v4 REST API (fallback), Playwright MCP for verification (no test framework exists in this project).

**Spec:** `docs/superpowers/specs/2026-09-12-recommendations-design.md`

## Global Constraints

- No new files split out of `index.html` for app logic — this project keeps all client JS in one file; only the Supabase migration gets its own `.sql` file, per existing convention (`supabase/migration-*.sql`).
- Every new Supabase write goes through the existing `checkWriteError(error)` guard.
- AniList failures (including its "temporarily disabled" outage, which returns HTTP 200 with a GraphQL `errors` array) must fall back to Jikan, never throw uncaught — mirrors `checkAnimeSequel`'s existing pattern.
- No automated test suite exists. Every task's verification step drives the real page via Playwright MCP with mocked `supabase.from(...)` and mocked `fetch(...)`, per the pattern already used for the watchlist-affinity feature this session.
- `rating` values are on the existing 0.5–5.0 half-star scale already used throughout the app (see `starsInnerHTML`) — do not treat them as 0–10.

---

### Task 1: Supabase migration for recommendation tables

**Files:**
- Create: `supabase/migration-recommendations.sql`

**Interfaces:**
- Produces: two tables, `recommendations_cache` and `dismissed_recommendations`, that Tasks 5 and 6 read/write via `supabase.from('recommendations_cache')` / `supabase.from('dismissed_recommendations')`.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migration-recommendations.sql
-- Run once in the Supabase SQL Editor.
--
-- Backs the Recommendations tab: caches computed anime/manga
-- recommendation lists per scope+category (cross-device, refreshed on a
-- throttle by the client) and tracks per-scope dismissals so a dismissed
-- title doesn't resurface on the next refresh.

create table recommendations_cache (
  scope show_scope not null,
  -- 'anime' caches against `shows` (category='anime'); 'manga' caches
  -- against `written_media` rows of EITHER category='manga' OR
  -- category='manhwa' -- both use AniList type MANGA, so they share one
  -- cache bucket and seed pool.
  category text not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (scope, category)
);

create table dismissed_recommendations (
  scope show_scope not null,
  -- AniList media id when available; falls back to "mal:<id>" or
  -- "title:<normalized title>" when a recommendation came from the Jikan
  -- fallback path (Jikan has no AniList id) -- see externalIdFor() in
  -- index.html, added in Task 5.
  external_id text not null,
  primary key (scope, external_id)
);

alter table recommendations_cache enable row level security;
alter table dismissed_recommendations enable row level security;

create policy "recommendations_cache readable by authenticated" on recommendations_cache
  for select using (auth.role() = 'authenticated');
create policy "recommendations_cache writable by owner or together" on recommendations_cache
  for all using (
    auth.role() = 'authenticated'
    and (scope = 'together' or scope::text = (select lower(display_name) from profiles where id = auth.uid()))
  );

create policy "dismissed_recommendations readable by authenticated" on dismissed_recommendations
  for select using (auth.role() = 'authenticated');
create policy "dismissed_recommendations writable by owner or together" on dismissed_recommendations
  for all using (
    auth.role() = 'authenticated'
    and (scope = 'together' or scope::text = (select lower(display_name) from profiles where id = auth.uid()))
  );

grant select, insert, update, delete on public.recommendations_cache, public.dismissed_recommendations
  to service_role, authenticated, anon;
```

- [ ] **Step 2: Sanity-check the SQL**

This project has no local Postgres/Supabase CLI — every other `migration-*.sql` file is applied manually by the user in the Supabase Dashboard's SQL Editor, so there's nothing to run locally. Instead, verify by inspection against the existing `supabase/migration.sql` (the `shows`/`ratings` RLS policies) to confirm the `create policy` syntax matches exactly, and confirm every table referenced in a policy (`profiles`) already exists in the base schema.

- [ ] **Step 3: Tell the user this migration needs to be applied**

This step has no code — it's a note for whoever runs this plan: the app-code tasks below (5 and 6) are fully verifiable via Playwright with mocked Supabase calls without this migration being live yet, but the feature won't work against real data until the user pastes this file into the Supabase SQL Editor. Flag this explicitly when the plan completes.

- [ ] **Step 4: Commit**

```bash
git add supabase/migration-recommendations.sql
git commit -m "feat: add recommendations_cache and dismissed_recommendations tables"
```

---

### Task 2: Seed selection and dedup-set helpers

**Files:**
- Modify: `index.html` (insert after `applyAffinityRanking`, i.e. right after the existing "Taste affinity scoring" section added for the watchlist-ranking feature)
- Test: manual Playwright `browser_evaluate` calls (no page interaction needed — pure functions)

**Interfaces:**
- Consumes: nothing new — operates on the same row shape `fetchShows`/`fetchWrittenMedia` already produce (`{ title, rating, allRatings, genres, studio, ... }`).
- Produces: `buildAlreadyHaveTitles(rows): Set<string>` and `pickRecommendationSeeds(rows, { scope, limit, minRating }): Array<row & { effectiveRating: number }>`, both consumed by Task 5's `computeRecommendations`.

- [ ] **Step 1: Add the two helper functions**

Insert this immediately after the existing `applyAffinityRanking` function (search for `function applyAffinityRanking` in `index.html` — this new block goes right after its closing `}`, before the `// Shared write-error guard` comment):

```js
  // ── Recommendation seed selection ──
  // Dedup key is the lowercased/trimmed title -- our rows don't store an
  // AniList id today, so title matching is the only key we have (same
  // caveat already accepted for sequel detection elsewhere in this file).
  function buildAlreadyHaveTitles(rows) {
    return new Set(rows.map(r => r.title.toLowerCase().trim()));
  }

  // Picks up to `limit` seed items rated >= minRating, highest first. For
  // scope === 'together', averages every rater's score per item first
  // (rows carry `allRatings`, an array of { user_id, rating, note }) so a
  // show only one partner loved doesn't get treated as a shared favorite.
  function pickRecommendationSeeds(rows, { scope, limit = 10, minRating = 4.0 } = {}) {
    const withEffectiveRating = rows.map(r => {
      let effectiveRating = r.rating;
      if (scope === 'together' && r.allRatings && r.allRatings.length) {
        const values = r.allRatings.map(x => x.rating).filter(v => v != null);
        effectiveRating = values.length ? values.reduce((a, b) => a + b, 0) / values.length : null;
      }
      return { ...r, effectiveRating };
    });
    return withEffectiveRating
      .filter(r => r.effectiveRating != null && r.effectiveRating >= minRating)
      .sort((a, b) => b.effectiveRating - a.effectiveRating)
      .slice(0, limit);
  }
```

- [ ] **Step 2: Verify with Playwright**

Start the app locally and load it:

```bash
(python -m http.server 8934 >/tmp/wt-http.log 2>&1 &)
```

Use `browser_navigate` to `http://localhost:8934/index.html`, then `browser_evaluate`:

```js
() => {
  const rows = [
    { title: 'A', rating: 5, allRatings: [{ user_id: 'u1', rating: 5 }, { user_id: 'u2', rating: 3 }] },
    { title: 'B', rating: 2, allRatings: [] },
    { title: 'C', rating: null, allRatings: [] },
  ];
  const alreadyHave = buildAlreadyHaveTitles(rows);
  const soloSeeds = pickRecommendationSeeds(rows, { scope: 'karl', minRating: 4 });
  const togetherSeeds = pickRecommendationSeeds(rows, { scope: 'together', minRating: 3.5 });
  return {
    alreadyHaveHasA: alreadyHave.has('a'),
    soloSeedTitles: soloSeeds.map(s => s.title),
    togetherSeedTitles: togetherSeeds.map(s => s.title),
    togetherEffectiveRatingForA: togetherSeeds.find(s => s.title === 'A')?.effectiveRating,
  };
}
```

Expected result: `alreadyHaveHasA: true`, `soloSeedTitles: ["A"]` (only A meets `rating >= 4`), `togetherSeedTitles: ["A"]` (A's averaged rating is 4, which meets the 3.5 threshold; B's plain rating of 2 does not), `togetherEffectiveRatingForA: 4`.

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat: add recommendation seed selection and dedup-set helpers"
```

---

### Task 3: AniList recommendations fetch + Jikan fallback

**Files:**
- Modify: `index.html` (insert after `searchAniListCovers`'s closing `}`, before `async function searchTMDBCovers`)
- Test: Playwright with mocked `window.fetch`

**Interfaces:**
- Consumes: nothing new.
- Produces: `fetchRecommendationsForSeed(seed, type): Promise<Array<{ anilistId, malId, title, genres, coverUrl, studio }>>` — `type` is `'ANIME'` or `'MANGA'`. Consumed by Task 5's `computeRecommendations`.

- [ ] **Step 1: Add the AniList combined query**

```js
  // ── Recommendations: AniList + Jikan fetch ──
  // Resolves `title` to an AniList id AND fetches its `recommendations`
  // field in a single round-trip (Media(search:) already returns the
  // matched entry's id, so a separate id-lookup call isn't needed).
  async function fetchAniListRecommendationsFor(title, type) {
    const query = `query ($s: String, $type: MediaType) { Media(search: $s, type: $type) {
      id
      recommendations(sort: RATING_DESC, perPage: 10) {
        nodes { mediaRecommendation { id title { romaji english } genres coverImage { large } studios(isMain: true) { nodes { name } } } }
      }
    } }`;
    const res = await fetch('https://graphql.anilist.co', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ query, variables: { s: title, type } })
    });
    const json = await res.json();
    // AniList's recurring "temporarily disabled due to severe stability
    // issues" outage still returns 200 with a GraphQL `errors` array
    // rather than a non-2xx status, so both must be checked.
    if (!res.ok || json.errors) throw new Error(`AniList error ${res.status}`);
    const nodes = json?.data?.Media?.recommendations?.nodes || [];
    return nodes.map(n => n.mediaRecommendation).filter(Boolean).map(m => ({
      anilistId: m.id,
      malId: null,
      title: m.title.english || m.title.romaji,
      genres: m.genres || [],
      coverUrl: m.coverImage?.large || null,
      studio: m.studios?.nodes?.[0]?.name || null,
    }));
  }

  // Fallback when AniList fails wholesale for a seed -- same MAL-search-
  // then-detail approach as fetchJikanAnimeSequel/fetchJikanMangaSequel,
  // pulling the /recommendations endpoint instead of /relations. Jikan
  // has no AniList id, so anilistId stays null here -- externalIdFor()
  // (Task 5) falls back to a "mal:<id>" key for dedup/dismissal instead.
  async function fetchJikanRecommendationsFor(title, kind) {
    const searchRes = await fetch(`https://api.jikan.moe/v4/${kind}?q=${encodeURIComponent(title)}&limit=5`);
    const searchJson = await searchRes.json();
    const results = searchJson.data || [];
    if (!results.length) return [];
    const exact = results.find(r => {
      const variants = [r.title, r.title_english, r.title_japanese, ...(r.titles || []).map(t => t.title)];
      return variants.some(v => (v || '').toLowerCase().trim() === title.toLowerCase().trim());
    });
    const match = exact || results[0];
    const recRes = await fetch(`https://api.jikan.moe/v4/${kind}/${match.mal_id}/recommendations`);
    const recJson = await recRes.json();
    const entries = recJson.data || [];
    return entries.slice(0, 10).map(e => ({
      anilistId: null,
      malId: e.entry.mal_id,
      title: e.entry.title,
      genres: [],
      coverUrl: e.entry.images?.jpg?.image_url || null,
      studio: null,
    }));
  }

  // Tries AniList first; on failure, falls back to Jikan. Never blends
  // both -- a successful AniList result is authoritative. Mirrors
  // checkAnimeSequel's fallback pattern.
  async function fetchRecommendationsForSeed(seed, type) {
    try {
      return await fetchAniListRecommendationsFor(seed.title, type);
    } catch (e) {
      console.warn('AniList recommendations failed for', seed.title, '— falling back to Jikan', e);
      const kind = type === 'ANIME' ? 'anime' : 'manga';
      return await fetchJikanRecommendationsFor(seed.title, kind).catch(() => []);
    }
  }
```

- [ ] **Step 2: Verify the AniList success path with Playwright**

Navigate to the running local server, then `browser_evaluate`:

```js
async () => {
  window.__origFetch = window.fetch;
  window.fetch = async (url, opts) => {
    if (String(url).includes('graphql.anilist.co')) {
      return { ok: true, status: 200, json: async () => ({
        data: { Media: { id: 999, recommendations: { nodes: [
          { mediaRecommendation: { id: 111, title: { romaji: 'Rec A', english: null }, genres: ['Drama'], coverImage: { large: 'http://x/a.jpg' }, studios: { nodes: [{ name: 'Studio A' }] } } },
        ] } } }
      }) };
    }
    return window.__origFetch(url, opts);
  };
  const result = await fetchRecommendationsForSeed({ title: 'Seed Show' }, 'ANIME');
  window.fetch = window.__origFetch;
  return result;
}
```

Expected: an array with one item, `{ anilistId: 111, malId: null, title: 'Rec A', genres: ['Drama'], coverUrl: 'http://x/a.jpg', studio: 'Studio A' }`.

- [ ] **Step 3: Verify the Jikan fallback path with Playwright**

```js
async () => {
  window.__origFetch = window.fetch;
  window.fetch = async (url) => {
    if (String(url).includes('graphql.anilist.co')) {
      return { ok: false, status: 403, json: async () => ({ errors: [{ message: 'down' }] }) };
    }
    if (String(url).includes('/v4/anime?q=')) {
      return { ok: true, json: async () => ({ data: [{ mal_id: 42, title: 'Seed Show', title_english: null, title_japanese: null, titles: [] }] }) };
    }
    if (String(url).includes('/v4/anime/42/recommendations')) {
      return { ok: true, json: async () => ({ data: [{ entry: { mal_id: 7, title: 'Jikan Rec', images: { jpg: { image_url: 'http://x/b.jpg' } } } }] }) };
    }
    return window.__origFetch(url);
  };
  const result = await fetchRecommendationsForSeed({ title: 'Seed Show' }, 'ANIME');
  window.fetch = window.__origFetch;
  return result;
}
```

Expected: an array with one item, `{ anilistId: null, malId: 7, title: 'Jikan Rec', genres: [], coverUrl: 'http://x/b.jpg', studio: null }`.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: add AniList recommendations fetch with Jikan fallback"
```

---

### Task 4: Genre-affinity fallback fetch

**Files:**
- Modify: `index.html` (insert immediately after Task 3's new functions, still before `async function searchTMDBCovers`)
- Test: Playwright with mocked `window.fetch`

**Interfaces:**
- Consumes: nothing new.
- Produces: `fetchGenreAffinityCandidates(genres, type, count): Promise<Array<{ anilistId, malId, title, genres, coverUrl, studio }>>`. Consumed by Task 5.

- [ ] **Step 1: Add the function**

```js
  // Fills remaining recommendation slots once the recommendations-field
  // pass doesn't produce enough candidates -- searches AniList's overall
  // catalog for popular titles in the given genres. Best-effort: a failed
  // or empty response here just means fewer recommendations shown, not a
  // hard error, so failures return [] rather than throwing.
  async function fetchGenreAffinityCandidates(genres, type, count) {
    if (!genres.length || count <= 0) return [];
    const query = `query ($genres: [String], $type: MediaType, $perPage: Int) {
      Page(perPage: $perPage) {
        media(genre_in: $genres, type: $type, sort: SCORE_DESC) {
          id title { romaji english } genres coverImage { large } studios(isMain: true) { nodes { name } }
        }
      }
    }`;
    try {
      const res = await fetch('https://graphql.anilist.co', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query, variables: { genres, type, perPage: count } })
      });
      const json = await res.json();
      if (!res.ok || json.errors) return [];
      const media = json?.data?.Page?.media || [];
      return media.map(m => ({
        anilistId: m.id,
        malId: null,
        title: m.title.english || m.title.romaji,
        genres: m.genres || [],
        coverUrl: m.coverImage?.large || null,
        studio: m.studios?.nodes?.[0]?.name || null,
      }));
    } catch (e) {
      console.warn('Genre-affinity recommendation search failed', e);
      return [];
    }
  }
```

- [ ] **Step 2: Verify with Playwright**

```js
async () => {
  window.__origFetch = window.fetch;
  window.fetch = async () => ({ ok: true, json: async () => ({
    data: { Page: { media: [
      { id: 55, title: { romaji: 'Genre Match', english: null }, genres: ['Suspense'], coverImage: { large: 'http://x/c.jpg' }, studios: { nodes: [{ name: 'Madhouse' }] } },
    ] } }
  }) });
  const result = await fetchGenreAffinityCandidates(['Suspense'], 'ANIME', 5);
  window.fetch = window.__origFetch;
  return result;
}
```

Expected: `[{ anilistId: 55, malId: null, title: 'Genre Match', genres: ['Suspense'], coverUrl: 'http://x/c.jpg', studio: 'Madhouse' }]`.

- [ ] **Step 3: Verify the empty-genres and failure cases return `[]` without throwing**

```js
async () => {
  const empty = await fetchGenreAffinityCandidates([], 'ANIME', 5);
  window.__origFetch = window.fetch;
  window.fetch = async () => { throw new Error('network down'); };
  const failed = await fetchGenreAffinityCandidates(['Drama'], 'ANIME', 5);
  window.fetch = window.__origFetch;
  return { empty, failed };
}
```

Expected: `{ empty: [], failed: [] }`.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: add genre-affinity recommendation fallback search"
```

---

### Task 5: Orchestration, cache, and dismissal

**Files:**
- Modify: `index.html` (insert after Task 4's `fetchGenreAffinityCandidates`, still before `async function searchTMDBCovers`)
- Test: Playwright with mocked `supabase.from` and the Task 3/4 fetch functions stubbed directly (these are already-defined globals in the page, so they can be reassigned for the test)

**Interfaces:**
- Consumes: `buildAlreadyHaveTitles`, `pickRecommendationSeeds` (Task 2), `fetchRecommendationsForSeed` (Task 3), `fetchGenreAffinityCandidates` (Task 4), `computeAffinity` (already exists, from the watchlist-ranking feature), `checkWriteError` (already exists).
- Produces: `externalIdFor(item): string`, `computeRecommendations(scope, category, rows): Promise<Array<recommendation>>`, `loadRecommendations(scope, category, rows, { force }): Promise<{ list, stale }>`, `dismissRecommendation(scope, item): Promise<boolean>`. Consumed by Task 6's rendering.
- A "recommendation" object has shape: `{ anilistId, malId, title, genres, coverUrl, studio, reason: 'because_rated'|'affinity', reasonDetail: string, sourceRating: number|null }`.

- [ ] **Step 1: Add the orchestration functions**

```js
  // ── Recommendations: orchestration, cache, dismissal ──
  const REC_CACHE_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;

  // Stable dedup/dismissal key across sources: AniList id when we have
  // one, else a MAL-id key (Jikan fallback), else a normalized-title key
  // as a last resort (genre-affinity results always have an anilistId,
  // so this only applies to a Jikan result with a missing malId, which
  // shouldn't happen in practice but keeps the function total).
  function externalIdFor(item) {
    if (item.anilistId) return String(item.anilistId);
    if (item.malId) return `mal:${item.malId}`;
    return `title:${item.title.toLowerCase().trim()}`;
  }

  async function getDismissedRecommendationIds(scope) {
    const { data, error } = await supabase.from('dismissed_recommendations').select('external_id').eq('scope', scope);
    if (error) { console.error(error); return new Set(); }
    return new Set(data.map(d => d.external_id));
  }

  async function dismissRecommendation(scope, item) {
    const { error } = await supabase.from('dismissed_recommendations')
      .insert({ scope, external_id: externalIdFor(item) });
    return !checkWriteError(error);
  }

  // Builds the ranked, deduped recommendation list for one scope+category
  // and writes it to recommendations_cache. `rows` is the full shows or
  // written_media list for the scope (any status) -- caller fetches it.
  async function computeRecommendations(scope, category, rows) {
    const type = category === 'anime' ? 'ANIME' : 'MANGA';
    const alreadyHave = buildAlreadyHaveTitles(rows);
    const dismissed = await getDismissedRecommendationIds(scope);
    const seeds = pickRecommendationSeeds(rows, { scope });

    const seedResults = await Promise.all(seeds.map(seed => fetchRecommendationsForSeed(seed, type)));
    const bySeedCount = new Map();
    seedResults.forEach((candidates, i) => {
      const seed = seeds[i];
      candidates.forEach(candidate => {
        if (alreadyHave.has(candidate.title.toLowerCase().trim())) return;
        const id = externalIdFor(candidate);
        if (dismissed.has(id)) return;
        const existing = bySeedCount.get(id);
        if (existing) {
          existing.seedCount += 1;
          existing.bestSeedRating = Math.max(existing.bestSeedRating, seed.effectiveRating);
        } else {
          bySeedCount.set(id, { item: candidate, seedCount: 1, bestSeedRating: seed.effectiveRating, seedTitle: seed.title });
        }
      });
    });

    let ranked = [...bySeedCount.values()]
      .sort((a, b) => (b.seedCount - a.seedCount) || (b.bestSeedRating - a.bestSeedRating))
      .slice(0, 15)
      .map(r => ({ ...r.item, reason: 'because_rated', reasonDetail: r.seedTitle, sourceRating: r.bestSeedRating }));

    if (ranked.length < 15) {
      const affinity = computeAffinity(rows);
      const topGenres = Object.entries(affinity.genreAvg).sort((a, b) => b[1] - a[1]).slice(0, 5).map(([g]) => g);
      const rankedIds = new Set(ranked.map(r => externalIdFor(r)));
      const need = 15 - ranked.length;
      const fillCandidates = await fetchGenreAffinityCandidates(topGenres, type, need + rankedIds.size);
      for (const candidate of fillCandidates) {
        if (ranked.length >= 15) break;
        if (alreadyHave.has(candidate.title.toLowerCase().trim())) continue;
        const id = externalIdFor(candidate);
        if (dismissed.has(id) || rankedIds.has(id)) continue;
        rankedIds.add(id);
        ranked.push({ ...candidate, reason: 'affinity', reasonDetail: topGenres.slice(0, 2).join('/'), sourceRating: null });
      }
    }

    const { error } = await supabase.from('recommendations_cache')
      .upsert({ scope, category, data: ranked, updated_at: new Date().toISOString() }, { onConflict: 'scope,category' });
    checkWriteError(error);
    return ranked;
  }

  // Cache-first loader: returns the cached list if it's under the
  // throttle age, otherwise recomputes. `force` (the manual Refresh
  // button, added in Task 6) skips the age check. On a total recompute
  // failure, falls back to the last cached list rather than showing
  // nothing (`stale: true` signals the UI to show a notice).
  async function loadRecommendations(scope, category, rows, { force = false } = {}) {
    if (!force) {
      const { data, error } = await supabase.from('recommendations_cache')
        .select('data, updated_at').eq('scope', scope).eq('category', category).maybeSingle();
      if (!error && data && (Date.now() - new Date(data.updated_at).getTime()) < REC_CACHE_MAX_AGE_MS) {
        return { list: data.data, stale: false };
      }
    }
    try {
      const list = await computeRecommendations(scope, category, rows);
      return { list, stale: false };
    } catch (e) {
      console.warn('Recommendations recompute failed, falling back to last cache', e);
      const { data } = await supabase.from('recommendations_cache')
        .select('data').eq('scope', scope).eq('category', category).maybeSingle();
      return { list: data?.data || [], stale: true };
    }
  }
```

- [ ] **Step 2: Verify dedup + ranking with Playwright**

This test stubs `fetchRecommendationsForSeed`/`fetchGenreAffinityCandidates` directly (they're page-level globals) rather than mocking `fetch`, since we're testing the orchestration logic, not the network layer already covered in Tasks 3–4:

```js
async () => {
  window.__origFrom = supabase.from.bind(supabase);
  let upserted = null;
  supabase.from = (table) => {
    if (table === 'dismissed_recommendations') return { select: () => ({ eq: () => Promise.resolve({ data: [{ external_id: '999' }], error: null }) }) };
    if (table === 'recommendations_cache') return { upsert: (row) => { upserted = row; return Promise.resolve({ error: null }); } };
    return window.__origFrom(table);
  };
  window.__origFetchSeed = fetchRecommendationsForSeed;
  window.__origFetchGenre = fetchGenreAffinityCandidates;
  fetchRecommendationsForSeed = async (seed) => {
    if (seed.title === 'Seed A') return [
      { anilistId: 101, malId: null, title: 'Already Have', genres: [], coverUrl: null, studio: null },
      { anilistId: 102, malId: null, title: 'Good Rec', genres: ['Drama'], coverUrl: null, studio: null },
      { anilistId: 999, malId: null, title: 'Dismissed One', genres: [], coverUrl: null, studio: null },
    ];
    return [{ anilistId: 102, malId: null, title: 'Good Rec', genres: ['Drama'], coverUrl: null, studio: null }];
  };
  fetchGenreAffinityCandidates = async () => [];
  const rows = [
    { title: 'Seed A', rating: 5, allRatings: [], genres: ['Drama'], studio: null },
    { title: 'Seed B', rating: 4.5, allRatings: [], genres: ['Drama'], studio: null },
    { title: 'Already Have', rating: null, allRatings: [], genres: [], studio: null },
  ];
  const result = await computeRecommendations('karl', 'anime', rows);
  fetchRecommendationsForSeed = window.__origFetchSeed;
  fetchGenreAffinityCandidates = window.__origFetchGenre;
  supabase.from = window.__origFrom;
  return { result, upsertedCategory: upserted?.category, upsertedCount: upserted?.data?.length };
}
```

Expected: `result` contains exactly one item, `{ anilistId: 102, title: 'Good Rec', ..., reason: 'because_rated', reasonDetail: 'Seed A', sourceRating: 5 }` — "Already Have" excluded (dedup by title), "Dismissed One" excluded (id 999 in the dismissed set), and it's recommended by both seeds so `seedCount: 2` puts it first (there's nothing else to rank against here, but confirm no error and exactly one surviving item). `upsertedCategory: 'anime'`, `upsertedCount: 1`.

- [ ] **Step 3: Verify the stale-cache fallback with Playwright**

```js
async () => {
  window.__origFrom = supabase.from.bind(supabase);
  let callCount = 0;
  supabase.from = (table) => {
    if (table === 'recommendations_cache') {
      callCount++;
      // First call (inside loadRecommendations' throttle check) returns
      // no cache; second call (inside the catch block, after compute
      // fails) returns a previously-cached list.
      return { select: () => ({ eq: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve(
        callCount === 1 ? { data: null, error: null } : { data: { data: [{ title: 'Old Cached Rec' }] }, error: null }
      ) }) }) } };
    }
    return window.__origFrom(table);
  };
  window.__origCompute = computeRecommendations;
  computeRecommendations = async () => { throw new Error('AniList and Jikan both down'); };
  const result = await loadRecommendations('karl', 'anime', []);
  computeRecommendations = window.__origCompute;
  supabase.from = window.__origFrom;
  return result;
}
```

Expected: `{ list: [{ title: 'Old Cached Rec' }], stale: true }`.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: add recommendations orchestration, cache, and dismissal"
```

---

### Task 6: Recommendations tab UI and wiring

**Files:**
- Modify: `index.html`:
  - HTML: add a new top-tab button and a new `<div id="view-recommendations">` container (near the existing `#top-tabs` and `#view-stats` markup, around line 1622 and line 1814 respectively)
  - CSS: add `.rec-grid`, `.rec-reason`, `.rec-card-actions`, `.rec-dismiss-btn` (near the existing `.watchlist-*` rules)
  - JS: extend `TOPTAB_GROUPS`, `TAB_HEADERS`, `activateSubtab`, `rerenderActiveTab`; add `activeRecCategory`, `setRecCategory`, `renderRecommendationsTab`
- Test: Playwright, full end-to-end with mocked `supabase.from` and stubbed `loadRecommendations`

**Interfaces:**
- Consumes: `loadRecommendations`, `dismissRecommendation`, `externalIdFor` (Task 5), `computeAffinity`/`MIN_RATED_FOR_AFFINITY` (existing, from the watchlist-ranking feature), `fetchShows`/`fetchWrittenMedia` (existing), `escapeHTML`/`showToast`/`checkWriteError`/`canWriteScope` (existing).
- Produces: `renderRecommendationsTab({ force })`, `setRecCategory(cat)` — both called from the tab-switch wiring, matching how `renderStatsTab`/`setStatsCategory` already work.

- [ ] **Step 1: Add the top-tab button**

In the `#top-tabs` div (around line 1622-1624), add a fourth button:

```html
    <button class="tab-btn active" data-toptab="tvmovies">TV / Movies</button>
    <button class="tab-btn" data-toptab="reading">Reading</button>
    <button class="tab-btn" data-toptab="recommendations">Recommendations</button>
    <button class="tab-btn" data-toptab="stats">Stats</button>
```

- [ ] **Step 2: Add the view container**

Near the existing `<div id="view-stats" style="display:none"></div>` (around line 1814), add:

```html
  <div id="view-recommendations" style="display:none"></div>
```

- [ ] **Step 3: Add CSS**

Near the existing `.watchlist-match` rule added for the watchlist-ranking feature, add:

```css
  .rec-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
    gap: 1rem;
  }

  .rec-reason {
    font-size: 0.62rem;
    color: var(--muted);
    margin: 0.4rem 0;
  }

  .rec-card-actions {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    margin-top: 0.5rem;
  }

  .rec-dismiss-btn {
    font-size: 0.9rem;
    line-height: 1;
    color: var(--muted);
    cursor: pointer;
    background: none;
    border: none;
    padding: 0.1rem 0.3rem;
  }
  .rec-dismiss-btn:hover { color: var(--text); }
```

- [ ] **Step 4: Wire the tab-switching config**

In `TOPTAB_GROUPS` (search for `const TOPTAB_GROUPS`):

```js
  const TOPTAB_GROUPS = {
    tvmovies: ['watching', 'movie-watchlist', 'spinwheel', 'tierlist', 'ratings'],
    reading: ['reading', 'reading-ratings'],
    recommendations: ['recommendations'],
    stats: ['stats'],
  };
```

In `TAB_HEADERS` (search for `const TAB_HEADERS`):

```js
  const TAB_HEADERS = {
    watching: { eyebrow: 'in progress', title: 'Currently Watching' },
    'movie-watchlist': { eyebrow: 'queued up', title: 'Movie Watchlist' },
    spinwheel: { eyebrow: "can't decide?", title: 'Spin the Wheel' },
    tierlist: { eyebrow: 'ranked', title: 'Tier List' },
    ratings: { eyebrow: 'rated', title: 'Ratings' },
    reading: { eyebrow: 'in progress', title: 'Currently Reading' },
    'reading-ratings': { eyebrow: 'rated', title: 'Reading Ratings' },
    recommendations: { eyebrow: 'discover', title: 'Recommendations' },
    stats: { eyebrow: 'the numbers', title: 'Stats' },
  };
```

In `activateSubtab` (search for `function activateSubtab`), add one display-toggle line alongside the existing ones, and one dispatch branch:

```js
    document.getElementById('view-recommendations').style.display = tab === 'recommendations' ? '' : 'none';
```

```js
    if (tab === 'recommendations') {
      renderRecommendationsTab();
    }
```

In `rerenderActiveTab` (search for `function rerenderActiveTab`), add a branch:

```js
    else if (currentTab === 'recommendations') renderRecommendationsTab();
```

- [ ] **Step 5: Add the category toggle state and render function**

Add near the existing `activeStatsCategory`/`setStatsCategory` (search for `let activeStatsCategory`):

```js
  let activeRecCategory = 'anime';
  function setRecCategory(cat) {
    activeRecCategory = cat;
    renderRecommendationsTab();
  }
```

Add the render function itself, placed after `renderStatsTab` (search for the closing `}` of `renderStatsTab`, right before the `// ── Auto-refresh on focus ──` comment):

```js
  async function renderRecommendationsTab({ force = false } = {}) {
    const container = document.getElementById('view-recommendations');
    const allRows = activeRecCategory === 'anime' ? await fetchShows(activeScope) : await fetchWrittenMedia(activeScope);
    // Restrict to the domain-appropriate rows for BOTH seed selection and
    // dedup -- otherwise a highly-rated western show would become a
    // wasted seed for an AniList `type: ANIME` search (it simply returns
    // no match, but it's still an unnecessary network call), mirroring
    // how computeAffinity is already called separately per-domain
    // elsewhere in this file (shows vs. written_media, never merged).
    const rows = activeRecCategory === 'anime'
      ? allRows.filter(s => s.category === 'anime')
      : allRows.filter(m => m.category === 'manga' || m.category === 'manhwa');
    const ratedCount = rows.filter(r => r.rating != null).length;

    container.innerHTML = `
      <div class="tabs sub-tabs">
        <button class="tab-btn sub-tab-btn${activeRecCategory === 'anime' ? ' active' : ''}" onclick="setRecCategory('anime')">Anime</button>
        <button class="tab-btn sub-tab-btn${activeRecCategory === 'manga' ? ' active' : ''}" onclick="setRecCategory('manga')">Manga / Manhwa</button>
        <button class="btn" id="rec-refresh-btn" style="margin-left:auto">Refresh</button>
      </div>
      <div id="rec-stale-note" style="display:none; font-size:0.65rem; color:var(--muted); margin:0.5rem 0"></div>
      <div id="rec-grid" class="rec-grid"></div>
    `;

    document.getElementById('rec-refresh-btn').addEventListener('click', () => renderRecommendationsTab({ force: true }));

    const grid = document.getElementById('rec-grid');
    if (ratedCount < MIN_RATED_FOR_AFFINITY) {
      grid.innerHTML = `<p style="font-size:0.75rem; color:var(--muted)">Rate a few more shows to get personalized recommendations.</p>`;
      return;
    }

    grid.innerHTML = `<p style="font-size:0.7rem; color:var(--muted)">Loading recommendations…</p>`;
    const { list, stale } = await loadRecommendations(activeScope, activeRecCategory, rows, { force });

    const staleNote = document.getElementById('rec-stale-note');
    if (stale) {
      staleNote.style.display = '';
      staleNote.textContent = "Couldn't refresh — showing last known recommendations.";
    }

    if (!list.length) {
      grid.innerHTML = `<p style="font-size:0.75rem; color:var(--muted)">No recommendations yet — try Refresh, or rate more titles.</p>`;
      return;
    }

    grid.innerHTML = list.map(item => `
      <div class="card rec-card">
        ${item.coverUrl ? `<img class="card-poster" src="${item.coverUrl}" alt="" onerror="this.remove()">` : ''}
        <div class="card-body">
          <div class="card-title">${escapeHTML(item.title)}</div>
          ${(item.genres || []).length ? `<div class="card-tags">${(item.genres || []).map(g => escapeHTML(g)).join(', ')}</div>` : ''}
          <div class="rec-reason">${item.reason === 'because_rated'
            ? `Because you rated <strong>${escapeHTML(item.reasonDetail)}</strong>${item.sourceRating != null ? ` ★${item.sourceRating}` : ''}`
            : `Matches your ${escapeHTML(item.reasonDetail)} taste`}</div>
          <div class="rec-card-actions">
            <button class="btn rec-add-btn">+ Add to Watchlist</button>
            <button class="rec-dismiss-btn" title="Dismiss">✕</button>
          </div>
        </div>
      </div>
    `).join('');

    grid.querySelectorAll('.rec-dismiss-btn').forEach((btn, i) => {
      btn.addEventListener('click', async () => {
        const ok = await dismissRecommendation(activeScope, list[i]);
        if (!ok) return;
        btn.closest('.rec-card').remove();
      });
    });

    grid.querySelectorAll('.rec-add-btn').forEach((btn, i) => {
      btn.addEventListener('click', async () => {
        const item = list[i];
        if (!canWriteScope(activeScope)) return;
        if (activeRecCategory === 'anime') {
          const { error } = await supabase.from('shows').insert({
            id: `rec-${externalIdFor(item)}-${Date.now()}`, title: item.title, category: 'anime', scope: activeScope,
            poster_url: item.coverUrl, studio: item.studio, genres: item.genres, list_status: 'watchlist', in_tier_pool: false,
          });
          if (checkWriteError(error)) return;
          invalidateShowsCache();
        } else {
          const { error } = await supabase.from('written_media').insert({
            title: item.title, category: 'manga', scope: activeScope, cover_url: item.coverUrl, genres: item.genres, list_status: 'plan_to_read',
          });
          if (checkWriteError(error)) return;
          invalidateWrittenMediaCache();
        }
        showToast(`Added "${item.title}" to your watchlist`);
        btn.closest('.rec-card').remove();
      });
    });
  }
```

- [ ] **Step 6: Verify end-to-end with Playwright**

Navigate to the running local server, sign in via the mock pattern already established for this app (set `currentProfile`, `activeScope`, show `#app-header`/`#app-content`, hide `#signed-out-screen`), then:

```js
async () => {
  currentProfile = { id: 'u1', display_name: 'Karl' };
  activeScope = 'karl';
  document.getElementById('app-header').style.display = '';
  document.getElementById('signed-out-screen').style.display = 'none';
  document.getElementById('app-content').style.display = '';

  window.__origFrom = supabase.from.bind(supabase);
  const showsData = Array.from({ length: 5 }, (_, i) => ({
    id: `s${i}`, title: `Rated ${i}`, category: 'anime', scope: 'karl', poster_url: null, studio: null,
    genres: ['Drama'], total_episodes: 12, total_seasons: 1, current_episode: 12, season_episode: 12, current_season: 1,
    runtime_minutes: null, list_status: 'watching', in_tier_pool: true, pinned: false, tags: null, last_updated: '2026-01-01',
    tier: null, rank: null, ratings: [{ user_id: 'u1', rating: 4.5, note: null }],
  }));
  supabase.from = (table) => {
    if (table === 'shows') return { select: () => ({ eq: () => Promise.resolve({ data: showsData, error: null }) }) };
    return window.__origFrom(table);
  };

  window.__origLoad = loadRecommendations;
  loadRecommendations = async () => ({ list: [
    { anilistId: 1, title: 'Great Match', genres: ['Drama'], coverUrl: null, studio: null, reason: 'because_rated', reasonDetail: 'Rated 0', sourceRating: 4.5 },
  ], stale: false });

  document.querySelector('[data-toptab="recommendations"]').click();
  await new Promise(r => setTimeout(r, 50));
  const html = document.getElementById('view-recommendations').innerHTML;

  loadRecommendations = window.__origLoad;
  supabase.from = window.__origFrom;
  return html.includes('Great Match') && html.includes('Because you rated') && html.includes('rec-add-btn');
}
```

Expected: `true`.

- [ ] **Step 7: Verify the dismiss button removes a card**

```js
async () => {
  currentProfile = { id: 'u1', display_name: 'Karl' };
  activeScope = 'karl';
  window.__origFrom = supabase.from.bind(supabase);
  supabase.from = (table) => {
    if (table === 'dismissed_recommendations') return { insert: () => Promise.resolve({ error: null }) };
    return window.__origFrom(table);
  };
  window.__origLoad = loadRecommendations;
  loadRecommendations = async () => ({ list: [
    { anilistId: 2, title: 'Dismiss Me', genres: [], coverUrl: null, studio: null, reason: 'affinity', reasonDetail: 'Drama', sourceRating: null },
  ], stale: false });

  await renderRecommendationsTab();
  await new Promise(r => setTimeout(r, 50));
  document.querySelector('.rec-dismiss-btn').click();
  await new Promise(r => setTimeout(r, 50));
  const stillThere = document.getElementById('view-recommendations').innerHTML.includes('Dismiss Me');

  loadRecommendations = window.__origLoad;
  supabase.from = window.__origFrom;
  return stillThere;
}
```

Expected: `false`.

- [ ] **Step 8: Clean up test artifacts and stop the local server**

```bash
pkill -f "http.server 8934" 2>/dev/null
rm -rf .playwright-mcp
```

- [ ] **Step 9: Commit**

```bash
git add index.html
git commit -m "feat: add Recommendations tab UI and wire it into tab navigation"
```

---

## Plan Self-Review Notes

- **Spec coverage:** data model (Task 1), computation pipeline steps 1-5 (Tasks 2-5), rendering & interactions (Task 6), error handling for seed failures/AniList outage/empty-threshold (Tasks 3, 5, 6), testing approach (every task's Playwright steps). The spec's "Together scope averages ratings" requirement is covered in Task 2. The one spec detail generalized during planning: `dismissed_recommendations.external_id` is described in the spec as "AniList media id" but Task 5's `externalIdFor()` extends this to a `mal:<id>` or `title:<...>` key when a recommendation came from the Jikan fallback (which has no AniList id) — necessary since the spec's Jikan-fallback error handling didn't otherwise specify how such an item gets dismissed/deduped. This is noted inline in Tasks 1 and 5.
- **Placeholder scan:** no TBD/TODO markers; every step has runnable code and concrete expected values.
- **Caught during review:** Task 6's anime branch originally passed the full unfiltered `shows` list (including western/movie rows) into `computeRecommendations`, which would waste calls seeding AniList `type: ANIME` searches from non-anime titles. Fixed to filter to `category === 'anime'` before passing, mirroring the manga branch's existing `manga`/`manhwa` filter and the codebase's established pattern of computing affinity separately per domain.
- **Type consistency:** `externalIdFor` (Task 5) is used identically in Task 5's dedup logic and Task 6's Add-to-Watchlist id generation. `computeRecommendations`/`loadRecommendations`/`dismissRecommendation` signatures match between their Task 5 definition and Task 6 call sites. The recommendation object shape (`anilistId, malId, title, genres, coverUrl, studio, reason, reasonDetail, sourceRating`) is consistent from Task 3/4's fetch functions through Task 5's ranking to Task 6's rendering.
