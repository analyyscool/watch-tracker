# Together → Personal Rating Mirror Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Whenever a `together`-scoped `shows` or `written_media` row exists with no matching personal-scope (`karl`/`liisa`) row, automatically create that personal-scope sibling (and copy over the current user's existing Together rating/note onto it), so the app's existing `syncRatingToSiblingScope` mirror has something to write into/from and ratings behave identically whichever side they're rated from.

**Architecture:** Two new self-healing functions in `index.html` — `mirrorTogetherShowsIntoPersonal()` and `mirrorTogetherMediaIntoPersonal()` — each called at the top of the personal-scope Ratings tab render (`renderRatingsTab`, `renderReadingRatingsTab`). They mirror the existing (reverse-direction) `syncTogetherFromPersonalRatings` function's shape closely: read all rows across scopes, find `together` rows with no personal-scope sibling for the signed-in user, insert the missing sibling, then upsert that user's existing Together rating onto it. No schema change — reuses the existing `ratings` table and its existing conflict keys.

**Tech Stack:** Same as the rest of the app — Supabase (Postgres + Auth + PostgREST), `supabase-js` v2 (CDN, plain `<script>`, no bundler/module system — every top-level function in `index.html` is globally callable, including from a browser console), vanilla JS/HTML.

**Spec:** `docs/superpowers/specs/2026-09-17-together-personal-rating-mirror-design.md`

## Global Constraints

- No build step — everything runs from static files opened via a plain HTTP server (`python -m http.server` from the repo root is the existing local-dev convention).
- No new npm dependencies, no schema/migration changes.
- Match existing `index.html` code style: `async function` declarations, `supabase.from(...)` query chains, `console.error` + `continue` for per-row error handling (never abort the whole pass on one bad row), `invalidateShowsCache()`/`invalidateWrittenMediaCache()` called once at the end only if something actually changed.
- Every Supabase write call must be checked for an error and logged before continuing — never a swallowed/unchecked write.
- No cross-user writes: every insert/upsert must use `scope: myScope` (the signed-in user's own scope, from `currentProfile.display_name.toLowerCase()`) and `user_id: currentProfile.id` — never touch or infer the other person's scope/user_id. This is what keeps the feature RLS-safe with no policy changes.
- There is no unit test runner in this repo — verification is direct Supabase REST calls (`curl` with the service-role key at `.supabase-service-key`, same pattern used throughout this project's other plans) plus a real browser session via the Playwright MCP tools, driven with Karl's credentials (`.supabase-passwords`) since only his password is available locally.
- Every test fixture created against the real Supabase project must be deleted again at the end of its task's verification — this is the live production database, not a sandbox.

---

### Task 1: `mirrorTogetherShowsIntoPersonal()`

**Files:**
- Modify: `index.html` — add the new function near `syncTogetherFromPersonalRatings` (~line 9170), and wire it into `renderRatingsTab` (~line 9221).

**Interfaces:**
- Consumes: `fetchShows(scope)` (returns rows shaped `{ id, title, category, scope, posterUrl, studio, genres, totalEpisodes, totalSeasons, runtimeMinutes, allRatings: [{user_id, rating, note}], ... }`, `null` scope fetches every row regardless of scope), `currentProfile` (global, `{ id, display_name }` of the signed-in user), `invalidateShowsCache()`, `checkWriteError` is NOT used here (follows `syncTogetherFromPersonalRatings`'s own `console.error`-and-continue style instead, per that function's existing precedent — do not introduce `checkWriteError` into this code path).
- Produces: `mirrorTogetherShowsIntoPersonal()` — an `async function` taking no arguments, returning `undefined`. Later tasks and any future caller can call it directly; it no-ops (returns immediately) if `currentProfile` is unset or `currentProfile.display_name.toLowerCase()` isn't `'karl'`/`'liisa'`.

- [ ] **Step 1: Add the function**

Insert this immediately after `syncTogetherFromPersonalRatings` (the function ending at index.html:9219, right before the blank line at 9220):

```js
  // Reverse direction of syncTogetherFromPersonalRatings above: ensures a
  // personal-scope sibling row exists for every together-scoped show the
  // current user has rated, so syncRatingToSiblingScope (which requires
  // both rows to already exist) always has something to mirror into/from.
  // See docs/superpowers/specs/2026-09-17-together-personal-rating-mirror-design.md.
  async function mirrorTogetherShowsIntoPersonal() {
    if (!currentProfile) return;
    const myScope = currentProfile.display_name.toLowerCase();
    if (myScope !== 'karl' && myScope !== 'liisa') return;

    const allRows = await fetchShows(null);
    const togetherRows = allRows.filter(s => s.scope === 'together');
    const myRowIds = new Set(allRows.filter(s => s.scope === myScope).map(s => s.id));

    let changed = false;
    for (const togetherShow of togetherRows) {
      if (myRowIds.has(togetherShow.id)) continue;

      const { error: showErr } = await supabase.from('shows').insert({
        id: togetherShow.id, title: togetherShow.title, category: togetherShow.category, scope: myScope,
        poster_url: togetherShow.posterUrl, studio: togetherShow.studio, genres: togetherShow.genres,
        total_episodes: togetherShow.totalEpisodes, total_seasons: togetherShow.totalSeasons,
        current_episode: togetherShow.totalEpisodes, season_episode: togetherShow.totalEpisodes,
        current_season: togetherShow.totalSeasons, runtime_minutes: togetherShow.runtimeMinutes,
        list_status: null, in_tier_pool: true,
        last_updated: new Date().toISOString().slice(0, 10),
      });
      if (showErr) { console.error(showErr); continue; }
      myRowIds.add(togetherShow.id);
      changed = true;

      const myRating = (togetherShow.allRatings || []).find(r => r.user_id === currentProfile.id);
      if (myRating?.rating == null && !myRating?.note) continue;
      const { error: ratingErr } = await supabase.from('ratings').upsert({
        show_id: togetherShow.id, scope: myScope, user_id: currentProfile.id,
        rating: myRating.rating, note: myRating.note ?? null, updated_at: new Date().toISOString(),
      }, { onConflict: 'show_id,scope,user_id' });
      if (ratingErr) { console.error(ratingErr); continue; }
    }
    if (changed) invalidateShowsCache();
  }
```

- [ ] **Step 2: Wire it into `renderRatingsTab`**

Change the first line of `renderRatingsTab` (index.html:9222):

```js
  async function renderRatingsTab() {
    if (activeScope === 'together') await syncTogetherFromPersonalRatings();
```

to:

```js
  async function renderRatingsTab() {
    if (activeScope === 'together') await syncTogetherFromPersonalRatings();
    else await mirrorTogetherShowsIntoPersonal();
```

- [ ] **Step 3: Manual smoke test — page still loads**

```bash
cd "C:\Users\karljohannesteet\Projects\watch-tracker"
python -m http.server 8811
```

Open `http://localhost:8811` in a browser (or via the Playwright MCP `browser_navigate` tool), sign in as Karl (`voileib27@gmail.com` / password in `.supabase-passwords`), open the Ratings tab. Expected: tab renders exactly as before (no console errors), since Karl already has personal-scope rows for everything he's rated — this step only confirms the new call site doesn't break the existing render.

- [ ] **Step 4: Create a test fixture — a together-only rated show**

```bash
cd "C:\Users\karljohannesteet\Projects\watch-tracker"
KEY=$(cat .supabase-service-key)
BASE="https://ppelaixzzgfhqximihpr.supabase.co"

# Insert a together-only show with no personal-scope sibling.
curl -s -X POST "$BASE/rest/v1/shows" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"id":"mirror-test-show","title":"Mirror Test Show","category":"movie","scope":"together","runtime_minutes":90,"in_tier_pool":true,"last_updated":"2026-09-18"}'

# Look up Karl's profile id.
curl -s "$BASE/rest/v1/profiles?select=id,display_name&display_name=eq.Karl" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```

Copy the returned `id` for Karl, then record a Together-scope rating for him against the test show (replace `<KARL_ID>`):

```bash
curl -s -X POST "$BASE/rest/v1/ratings" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"show_id":"mirror-test-show","scope":"together","user_id":"<KARL_ID>","rating":4.5,"note":"test fixture"}'
```

Expected: both inserts return `201`/the created row with no error.

- [ ] **Step 5: Trigger the mirror and verify**

With Karl still signed in (from Step 3), reload the app and open the Ratings tab under his own (`karl`) scope — or, faster, run this directly in the browser console (Playwright MCP `browser_evaluate`) while the page is open and signed in as Karl:

```js
await mirrorTogetherShowsIntoPersonal();
```

Then verify via REST:

```bash
curl -s "$BASE/rest/v1/shows?select=id,title,scope,in_tier_pool,current_episode&id=eq.mirror-test-show" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
curl -s "$BASE/rest/v1/ratings?select=*&show_id=eq.mirror-test-show" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```

Expected: the `shows` query now returns **two** rows for `mirror-test-show` (`scope: "together"` and `scope: "karl"`, the latter with `in_tier_pool: true`). The `ratings` query returns **two** rows for Karl's `user_id` — one `scope: "together"` (the original), one `scope: "karl"` (the new mirror) — both `rating: 4.5`.

- [ ] **Step 6: Verify idempotency**

Run `await mirrorTogetherShowsIntoPersonal();` in the console a second time. Re-run the same two `curl` checks from Step 5. Expected: still exactly two `shows` rows and two `ratings` rows for this test show — no duplicates.

- [ ] **Step 7: Verify the hand-off to the existing sibling sync**

Still signed in as Karl on his own (`karl`) scope, open the Ratings tab in the browser (not the console) and change "Mirror Test Show"'s star rating from 4.5 to 3. Then verify:

```bash
curl -s "$BASE/rest/v1/ratings?select=scope,rating&show_id=eq.mirror-test-show" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```

Expected: both the `karl`-scope and `together`-scope rating rows now read `3` — confirming `setRating`'s existing call to `syncRatingToSiblingScope` picked up the sibling this task just created.

- [ ] **Step 8: Clean up the test fixture**

```bash
curl -s -X DELETE "$BASE/rest/v1/ratings?show_id=eq.mirror-test-show" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
curl -s -X DELETE "$BASE/rest/v1/shows?id=eq.mirror-test-show" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```

Expected: both return `204`. Re-run the Step 5 `shows`/`ratings` queries once more to confirm zero rows remain for `mirror-test-show`.

- [ ] **Step 9: Commit**

```bash
cd "C:\Users\karljohannesteet\Projects\watch-tracker"
git add index.html
git commit -m "$(cat <<'EOF'
feat: mirror Together-only show ratings into a personal-scope row

Adds mirrorTogetherShowsIntoPersonal(), the reverse direction of the
existing syncTogetherFromPersonalRatings -- creates the missing
personal-scope sibling (and copies the rating) whenever a
together-scoped show has no karl/liisa row, so the existing
syncRatingToSiblingScope mirror has something to write into.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `mirrorTogetherMediaIntoPersonal()`

**Files:**
- Modify: `index.html` — add the new function near `mirrorTogetherShowsIntoPersonal` (from Task 1), and wire it into `renderReadingRatingsTab` (~line 9317).

**Interfaces:**
- Consumes: `fetchWrittenMedia(scope)` (returns rows shaped `{ id, title, category, scope, author, coverUrl, genres, totalChapters, totalVolumes, totalPages, seriesStatus, allRatings: [{user_id, rating, note}], ... }`, `null` scope fetches every row regardless of scope), `currentProfile`, `invalidateWrittenMediaCache()`.
- Produces: `mirrorTogetherMediaIntoPersonal()` — an `async function` taking no arguments, returning `undefined`, same no-op guard as `mirrorTogetherShowsIntoPersonal()` (Task 1) when not signed in as `karl`/`liisa`.

- [ ] **Step 1: Add the function**

Insert this immediately after `mirrorTogetherShowsIntoPersonal` (added in Task 1):

```js
  // Same idea as mirrorTogetherShowsIntoPersonal, but written_media rows
  // don't share an id across scope copies (each gets its own generated
  // UUID -- see CLAUDE.md's written_media "not idempotent" note), so
  // matching an existing personal-scope sibling has to go by normalized
  // title+category instead of id.
  async function mirrorTogetherMediaIntoPersonal() {
    if (!currentProfile) return;
    const myScope = currentProfile.display_name.toLowerCase();
    if (myScope !== 'karl' && myScope !== 'liisa') return;

    const mediaKey = m => `${m.title.toLowerCase().trim()}::${m.category}`;
    const allMedia = await fetchWrittenMedia(null);
    const togetherMedia = allMedia.filter(m => m.scope === 'together');
    const myMediaKeys = new Set(allMedia.filter(m => m.scope === myScope).map(mediaKey));

    let changed = false;
    for (const togetherItem of togetherMedia) {
      const key = mediaKey(togetherItem);
      if (myMediaKeys.has(key)) continue;

      const { data: inserted, error: mediaErr } = await supabase.from('written_media').insert({
        title: togetherItem.title, category: togetherItem.category, scope: myScope,
        author: togetherItem.author, cover_url: togetherItem.coverUrl, genres: togetherItem.genres,
        total_chapters: togetherItem.totalChapters, current_chapter: togetherItem.totalChapters,
        total_volumes: togetherItem.totalVolumes, current_volume: togetherItem.totalVolumes,
        total_pages: togetherItem.totalPages, current_page: togetherItem.totalPages,
        series_status: togetherItem.seriesStatus, list_status: 'completed',
        last_updated: new Date().toISOString().slice(0, 10),
      }).select('id').single();
      if (mediaErr) { console.error(mediaErr); continue; }
      myMediaKeys.add(key);
      changed = true;

      const myRating = (togetherItem.allRatings || []).find(r => r.user_id === currentProfile.id);
      if (myRating?.rating == null && !myRating?.note) continue;
      const { error: ratingErr } = await supabase.from('ratings').upsert({
        written_media_id: inserted.id, user_id: currentProfile.id,
        rating: myRating.rating, note: myRating.note ?? null, updated_at: new Date().toISOString(),
      }, { onConflict: 'written_media_id,user_id' });
      if (ratingErr) { console.error(ratingErr); continue; }
    }
    if (changed) invalidateWrittenMediaCache();
  }
```

- [ ] **Step 2: Wire it into `renderReadingRatingsTab`**

Change the first line of `renderReadingRatingsTab` (index.html:9317, the line before the `fetchWrittenMedia` call):

```js
  async function renderReadingRatingsTab() {
    const media = (await fetchWrittenMedia(activeScope)).filter(m => m.listStatus === 'completed');
```

to:

```js
  async function renderReadingRatingsTab() {
    await mirrorTogetherMediaIntoPersonal();
    const media = (await fetchWrittenMedia(activeScope)).filter(m => m.listStatus === 'completed');
```

- [ ] **Step 3: Manual smoke test — page still loads**

With the local server from Task 1 Step 3 still running (or restart `python -m http.server 8811` from the repo root), sign in as Karl, open the Reading tab's Ratings sub-tab. Expected: renders as before, no console errors.

- [ ] **Step 4: Create a test fixture — a together-only rated manga**

```bash
cd "C:\Users\karljohannesteet\Projects\watch-tracker"
KEY=$(cat .supabase-service-key)
BASE="https://ppelaixzzgfhqximihpr.supabase.co"

curl -s -X POST "$BASE/rest/v1/written_media" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"title":"Mirror Test Manga","category":"manga","scope":"together","total_chapters":10,"list_status":"completed","last_updated":"2026-09-18"}'
```

The response body is the created row — copy its `id` (call it `<TOGETHER_MEDIA_ID>`). Get Karl's profile id the same way as Task 1 Step 4, then:

```bash
curl -s -X POST "$BASE/rest/v1/ratings" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"written_media_id":"<TOGETHER_MEDIA_ID>","user_id":"<KARL_ID>","rating":4,"note":"test fixture"}'
```

Expected: both return the created row with no error.

- [ ] **Step 5: Trigger the mirror and verify**

While signed in as Karl with the page open, run in the browser console (Playwright MCP `browser_evaluate`):

```js
await mirrorTogetherMediaIntoPersonal();
```

Then verify via REST:

```bash
curl -s "$BASE/rest/v1/written_media?select=id,title,scope,list_status,current_chapter&title=eq.Mirror%20Test%20Manga" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```

Expected: two rows now — `scope: "together"` (original, `id` = `<TOGETHER_MEDIA_ID>`) and `scope: "karl"` (new, a different `id`, `current_chapter: 10`, `list_status: "completed"`). Copy the new `karl`-scope row's `id` (call it `<KARL_MEDIA_ID>`), then:

```bash
curl -s "$BASE/rest/v1/ratings?select=*&written_media_id=eq.<KARL_MEDIA_ID>" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```

Expected: one row, `rating: 4`, `note: "test fixture"`, for Karl's `user_id`.

- [ ] **Step 6: Verify idempotency**

Run `await mirrorTogetherMediaIntoPersonal();` a second time. Re-run the Step 5 `written_media` query. Expected: still exactly two rows (`together` and `karl`) for "Mirror Test Manga" — no third row created.

- [ ] **Step 7: Clean up the test fixture**

```bash
curl -s -X DELETE "$BASE/rest/v1/ratings?written_media_id=eq.<TOGETHER_MEDIA_ID>" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
curl -s -X DELETE "$BASE/rest/v1/ratings?written_media_id=eq.<KARL_MEDIA_ID>" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
curl -s -X DELETE "$BASE/rest/v1/written_media?title=eq.Mirror%20Test%20Manga" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```

Expected: all `204`. Re-run the Step 5 `written_media` query once more to confirm zero rows remain.

- [ ] **Step 8: Commit**

```bash
cd "C:\Users\karljohannesteet\Projects\watch-tracker"
git add index.html
git commit -m "$(cat <<'EOF'
feat: mirror Together-only written_media ratings into a personal row

Same self-healing mirror as the shows-side one (previous commit), but
matched by normalized title+category instead of id, since
written_media rows don't share an id across scope copies.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```
