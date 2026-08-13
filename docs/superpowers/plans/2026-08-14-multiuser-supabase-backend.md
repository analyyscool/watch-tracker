# Multi-User Supabase Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `data.json` + Claude-mediated writes + `localStorage`-only ratings with a real Supabase backend supporting two accounts (Karl, Liisa) each with a personal scope plus a shared "Together" scope, direct in-page writes for progress/finish/ratings/notes/pins, and a Letterboxd import path.

**Architecture:** Two Supabase tables (`shows`, `ratings`) plus `profiles`, gated by Supabase Auth magic-link sign-in and Row Level Security. The static `index.html` talks to Supabase directly via `supabase-js` loaded from a CDN (no build step). Claude-mediated writes (Add Show, Letterboxd import) go through a local `curl` helper script using a gitignored service-role key that bypasses RLS.

**Tech Stack:** Supabase (Postgres + Auth + PostgREST), `supabase-js` v2 (CDN), vanilla JS/HTML (existing stack, no bundler), Node.js (for one-off generation/import scripts, no npm deps).

**Spec:** `docs/superpowers/specs/2026-08-14-multiuser-supabase-backend-design.md`

## Global Constraints

- No build step — everything runs from static files opened via a plain HTTP server, exactly like today.
- No new npm dependencies; if a script needs to run in Node, use only built-ins (`fetch`, `fs`, `readline`).
- The **publishable/anon key** is safe to commit inside `index.html`. The **service-role key** must never be committed — it lives only in a gitignored local file.
- Match existing `index.html` code style: no framework, plain `document.getElementById`/`querySelectorAll`, template-literal HTML strings, the existing `.tab-btn`/`.category-btn` toggle pattern for any new toggle UI.
- Ratings scale stays 0–5 in 0.5 steps (matches both the existing UI and Letterboxd's scale — no conversion needed).
- Every task must leave the app in a working, loadable state — no task should leave `index.html` broken for the next task to fix.

---

### Task 1: Supabase schema, RLS, and data migration SQL

**Files:**
- Create: `supabase/migration.sql`
- Create: `scripts/generate-migration-sql.mjs`

**Interfaces:**
- Produces: the `shows`, `ratings`, `profiles` tables and `show_scope`/`list_status` enums that every later task's Supabase queries depend on. Exact column names/types are load-bearing for all subsequent tasks — see the spec's "Data model" section, reproduced in Step 1 below.

- [ ] **Step 1: Write `scripts/generate-migration-sql.mjs`**

This script reads `data.json` and prints the full migration SQL (schema + RLS + Karl's existing shows) to stdout.

```js
// scripts/generate-migration-sql.mjs
import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync(new URL('../data.json', import.meta.url)));

function sqlStr(v) {
  if (v === null || v === undefined) return 'null';
  return `'${String(v).replace(/'/g, "''")}'`;
}
function sqlArr(v) {
  if (!v || !v.length) return 'null';
  return `array[${v.map(sqlStr).join(',')}]`;
}
function sqlNum(v) {
  return v === null || v === undefined ? 'null' : String(v);
}
function sqlBool(v) {
  return v ? 'true' : 'false';
}

const schema = `
create type show_scope as enum ('karl', 'liisa', 'together');
create type list_status as enum ('watching', 'watchlist');

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null
);

create table shows (
  id text primary key,
  title text not null,
  category text not null,
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
  list_status list_status,
  in_tier_pool boolean not null default false,
  pinned boolean not null default false,
  tags text[],
  last_updated date,
  created_at timestamptz not null default now()
);

create table ratings (
  show_id text not null references shows(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  rating numeric(2,1),
  note text,
  updated_at timestamptz not null default now(),
  primary key (show_id, user_id)
);

alter table profiles enable row level security;
alter table shows enable row level security;
alter table ratings enable row level security;

create policy "profiles readable by authenticated" on profiles
  for select using (auth.role() = 'authenticated');

create policy "shows readable by authenticated" on shows
  for select using (auth.role() = 'authenticated');

create policy "shows writable by owner or together" on shows
  for all using (
    scope = 'together'
    or scope::text = (select lower(display_name) from profiles where id = auth.uid())
  );

create policy "ratings readable by authenticated" on ratings
  for select using (auth.role() = 'authenticated');

create policy "ratings writable by owner" on ratings
  for insert, update, delete using (user_id = auth.uid());
`.trim();

// Merge watching + watched + watchlist into one row set, keyed by id,
// mirroring the app's existing merge logic (a finished `watching` entry and
// its `watched` counterpart are the same show).
const rows = new Map();

function upsert(id, patch) {
  rows.set(id, { ...(rows.get(id) || {}), ...patch });
}

for (const s of data.watching ?? []) {
  upsert(s.id, {
    id: s.id, title: s.title, category: s.category ?? 'anime',
    poster_url: s.posterUrl, studio: s.studio, genres: s.genres,
    total_episodes: s.totalEpisodes, total_seasons: s.totalSeasons,
    current_episode: s.currentEpisode, season_episode: s.seasonEpisode,
    current_season: s.currentSeason, runtime_minutes: s.runtimeMinutes,
    list_status: 'watching', last_updated: s.lastUpdated,
  });
}
for (const s of data.watched ?? []) {
  upsert(s.id, {
    id: s.id, title: s.title, category: s.category ?? 'anime',
    poster_url: s.posterUrl, in_tier_pool: true,
    runtime_minutes: rows.get(s.id)?.runtime_minutes ?? s.runtimeMinutes,
  });
}
for (const s of data.watchlist ?? []) {
  upsert(s.id, { id: s.id, title: s.title, category: s.category ?? 'anime', list_status: 'watchlist' });
}

const inserts = [...rows.values()].map(r => `insert into shows
  (id, title, category, scope, poster_url, studio, genres, total_episodes, total_seasons,
   current_episode, season_episode, current_season, runtime_minutes, list_status, in_tier_pool, last_updated)
values (
  ${sqlStr(r.id)}, ${sqlStr(r.title)}, ${sqlStr(r.category)}, 'karl',
  ${sqlStr(r.poster_url)}, ${sqlStr(r.studio)}, ${sqlArr(r.genres)},
  ${sqlNum(r.total_episodes)}, ${sqlNum(r.total_seasons)}, ${sqlNum(r.current_episode)},
  ${sqlNum(r.season_episode)}, ${sqlNum(r.current_season)}, ${sqlNum(r.runtime_minutes)},
  ${r.list_status ? sqlStr(r.list_status) : 'null'}, ${sqlBool(r.in_tier_pool ?? false)},
  ${sqlStr(r.last_updated)}
);`).join('\n');

console.log(schema + '\n\n-- Karl\'s existing shows\n' + inserts + '\n');
console.log(`-- Profiles: replace the two UUIDs below with the real auth.users ids
-- from Supabase Dashboard -> Authentication -> Users, after creating the
-- two invited users there.
-- insert into profiles (id, display_name) values ('<karl-uuid>', 'Karl');
-- insert into profiles (id, display_name) values ('<liisa-uuid>', 'Liisa');`);
```

- [ ] **Step 2: Run the generator and save its output**

Run: `node scripts/generate-migration-sql.mjs > supabase/migration.sql`

Expected: `supabase/migration.sql` now contains the full schema + ~90 `insert into shows` statements ending in `scope = 'karl'`.

- [ ] **Step 3: Verify row count matches `data.json`**

Run: `grep -c "^insert into shows" supabase/migration.sql`

Expected: matches the number of distinct ids across `data.json`'s `watching`+`watched`+`watchlist` arrays (spot-check a few known titles like `samurai-champloo` and `suzume` appear).

- [ ] **Step 4: Hand off to Karl to create the two Supabase Auth users, then run the SQL**

This step is manual, not automatable — report back to Karl:

1. In the Supabase dashboard: Authentication → Users → Invite user, once for Karl's email, once for Liisa's email.
2. Copy each user's UUID from that same Users list.
3. Open `supabase/migration.sql`, uncomment the two `insert into profiles` lines at the bottom, and paste in the real UUIDs.
4. Paste the whole file into the Supabase SQL Editor and run it.

Expected: SQL Editor reports success with no errors; Table Editor shows `shows` with ~90 rows, `profiles` with 2 rows, `ratings` empty.

- [ ] **Step 5: Commit**

```bash
git add scripts/generate-migration-sql.mjs supabase/migration.sql
git commit -m "add: Supabase schema + data migration SQL generator"
```

---

### Task 2: Service-role key setup + Claude-side write helper

**Files:**
- Create: `.supabase-service-key` (gitignored, not committed — placeholder created empty, Karl pastes the real key in manually)
- Modify: `.gitignore`
- Create: `scripts/supabase-write.mjs`

**Interfaces:**
- Consumes: `SUPABASE_URL` (hardcoded, same project URL as the app) and the service-role key read from `.supabase-service-key`.
- Produces: a `supabaseWrite(table, rows)` upsert helper other scripts (Add Show, Letterboxd import) call via CLI.

- [ ] **Step 1: Add the key file to `.gitignore`**

```bash
echo ".supabase-service-key" >> .gitignore
```

- [ ] **Step 2: Create the empty key file and ask Karl to fill it**

Run: `if [ ! -f .supabase-service-key ]; then touch .supabase-service-key; fi`

Report to Karl: "Go to Supabase Dashboard → Project Settings → API Keys → reveal/copy the `service_role` **secret** key (not the publishable one), and paste it as the only line in `.supabase-service-key` (already gitignored)."

- [ ] **Step 3: Write `scripts/supabase-write.mjs`**

```js
// scripts/supabase-write.mjs
// Usage: node scripts/supabase-write.mjs <table> '<json array of rows>'
// Upserts rows into the given table using the service-role key, bypassing RLS.
import { readFileSync } from 'node:fs';

const SUPABASE_URL = 'https://ppelaixzzgfhqximihpr.supabase.co';
const serviceKey = readFileSync(new URL('../.supabase-service-key', import.meta.url), 'utf8').trim();

const [, , table, rowsJson] = process.argv;
if (!table || !rowsJson) {
  console.error('Usage: node scripts/supabase-write.mjs <table> \'<json array of rows>\'');
  process.exit(1);
}

const rows = JSON.parse(rowsJson);

const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    Prefer: 'resolution=merge-duplicates,return=representation',
  },
  body: JSON.stringify(rows),
});

const body = await res.json();
if (!res.ok) {
  console.error('Supabase write failed:', res.status, body);
  process.exit(1);
}
console.log(JSON.stringify(body, null, 2));
```

- [ ] **Step 4: Test with a throwaway row, then delete it**

Run: `node scripts/supabase-write.mjs shows '[{"id":"test-row","title":"Test","category":"anime","scope":"karl"}]'`

Expected: prints the inserted row as JSON, HTTP 201/200.

Run: `curl -s -X DELETE "https://ppelaixzzgfhqximihpr.supabase.co/rest/v1/shows?id=eq.test-row" -H "apikey: $(cat .supabase-service-key)" -H "Authorization: Bearer $(cat .supabase-service-key)"`

Expected: empty success response; re-running a `select` for `test-row` returns nothing.

- [ ] **Step 5: Commit**

```bash
git add .gitignore scripts/supabase-write.mjs
git commit -m "add: gitignored service-role key + Claude-side Supabase write helper"
```

---

### Task 3: Wire `index.html` reads to Supabase + sign-in

**Files:**
- Modify: `index.html` (add `supabase-js` CDN script, client init, auth UI, replace the 3 `fetch('data.json')` call sites)

**Interfaces:**
- Consumes: `shows`/`ratings`/`profiles` tables from Task 1.
- Produces: a `supabase` client global, `getSession()`/`currentUser()` helpers, and `fetchShows(scope)` — an async function returning all `shows` rows for a scope, left-joined with the signed-in user's own `ratings` row. Later tasks (4–9) call `fetchShows` instead of touching `fetch('data.json')` directly.

- [ ] **Step 1: Add the Supabase client and auth UI to `index.html`**

Add before the existing `<script>` block's other code, near the top of the script:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>
```

```js
const SUPABASE_URL = 'https://ppelaixzzgfhqximihpr.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_gaxXcTPI8efpzoATbGqXnA_XqKLlH3_';
const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

let currentProfile = null; // { id, display_name } once signed in

async function refreshAuthUI() {
  const { data: { session } } = await supabase.auth.getSession();
  const authArea = document.getElementById('auth-area');
  if (!session) {
    currentProfile = null;
    authArea.innerHTML = `<button class="btn" id="btn-signin">Sign in</button>`;
    document.getElementById('btn-signin').addEventListener('click', async () => {
      const email = prompt('Email for magic link:');
      if (!email) return;
      const { error } = await supabase.auth.signInWithOtp({ email });
      authArea.innerHTML = error ? `<span>Sign-in failed</span>` : `<span>Check your email</span>`;
    });
    return;
  }
  const { data: profile } = await supabase.from('profiles').select('*').eq('id', session.user.id).single();
  currentProfile = profile;
  authArea.innerHTML = `<span>${profile.display_name}</span> <button class="btn" id="btn-signout">Sign out</button>`;
  document.getElementById('btn-signout').addEventListener('click', () => supabase.auth.signOut().then(refreshAuthUI));
}

supabase.auth.onAuthStateChange(() => refreshAuthUI());
```

Add the `#auth-area` element to the header, next to the existing theme button:

```html
<div class="header-actions">
  <button class="btn btn-primary" id="btn-add">+ Add Show</button>
  <button class="btn" id="btn-reload">↺ Reload</button>
  <button class="btn" id="btn-theme">dark mode</button>
  <span id="auth-area"></span>
</div>
```

- [ ] **Step 2: Replace the 3 `fetch('data.json')` call sites with a shared `fetchShows` helper**

Add near the other data-access helpers:

```js
let showsCache = null;

async function fetchShows(scope) {
  const key = scope || 'all';
  if (showsCache && showsCache.key === key) return showsCache.rows;
  let query = supabase.from('shows').select('*, ratings(user_id, rating, note)');
  if (scope) query = query.eq('scope', scope);
  const { data, error } = await query;
  if (error) { console.error(error); return []; }
  const rows = data.map(s => ({
    id: s.id, title: s.title, category: s.category, scope: s.scope,
    posterUrl: s.poster_url, studio: s.studio, genres: s.genres,
    totalEpisodes: s.total_episodes, totalSeasons: s.total_seasons,
    currentEpisode: s.current_episode, seasonEpisode: s.season_episode,
    currentSeason: s.current_season, runtimeMinutes: s.runtime_minutes,
    listStatus: s.list_status, inTierPool: s.in_tier_pool, pinned: s.pinned,
    tags: s.tags, lastUpdated: s.last_updated,
    rating: currentProfile ? s.ratings.find(r => r.user_id === currentProfile.id)?.rating ?? null : null,
    note: currentProfile ? s.ratings.find(r => r.user_id === currentProfile.id)?.note ?? null : null,
  }));
  showsCache = { key, rows };
  return rows;
}

function invalidateShowsCache() { showsCache = null; }
```

Replace `loadShows()`'s body (previously `fetch('data.json?t=' + Date.now())`) to call `const rows = await fetchShows(activeScope); const watching = rows.filter(s => s.listStatus === 'watching'); const watchlist = rows.filter(s => s.listStatus === 'watchlist');` — keep the rest of `loadShows` (sort/filter/render logic) unchanged, since it already operates on plain arrays of shows with the same field names (`currentEpisode`, `totalEpisodes`, etc.) `fetchShows` now produces.

Replace `getAllWatchedShows()`'s body to `return (await fetchShows(activeScope)).filter(s => s.inTierPool || (s.listStatus === 'watching' && s.currentEpisode >= s.totalEpisodes));`.

Replace `renderStatsTab()`'s `fetch('data.json?t=' + Date.now())` + `data.watching`/`data.watched`/`data.watchlist` destructuring with `const rows = await fetchShows(activeScope); const watching = rows.filter(s => s.listStatus === 'watching'); const watchedOnly = rows.filter(s => s.inTierPool); const watchlist = rows.filter(s => s.listStatus === 'watchlist');` — the rest of the function's math is unchanged since it already only reads these three arrays plus per-show fields that keep the same names.

`activeScope` is a new top-level variable, defaulting to `null` until Task 4 adds the scope switcher — for this task, hardcode `let activeScope = 'karl';` so the app renders Karl's data exactly as before while Task 4 is still pending.

- [ ] **Step 3: Manual verification via Playwright**

Start a local server (`python -m http.server 8791`) and use Playwright to:
1. Navigate to the app, confirm the Watching tab renders Karl's ~10 in-progress shows (same as it did from `data.json`).
2. Click "Sign in", enter Karl's email, confirm "Check your email" appears.
3. (After Karl clicks the emailed magic link in a real browser, confirming session persistence is out of scope for headless Playwright — note this as a manual check for Karl to do once, not part of automated verification.)

Expected: Watching/Tier List/Ratings/Stats tabs all render identically to the pre-migration `data.json`-backed version, confirming the read path is fully replaced.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "add: wire index.html reads to Supabase, add magic-link sign-in"
```

---

### Task 4: Scope switcher (Karl / Liisa / Together) + server-side pins

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: `fetchShows(scope)`, `invalidateShowsCache()` from Task 3.
- Produces: `activeScope` (replaces the Task-3 hardcoded value, now user-controlled), `canWriteScope(scope)` — a boolean helper later tasks (5, 6) use to gate write UI.

- [ ] **Step 1: Add the scope switcher to the header, above the tab bar**

```html
<div class="category-toggle" id="scope-toggle">
  <button class="btn scope-btn active" data-scope="karl">Karl</button>
  <button class="btn scope-btn" data-scope="liisa">Liisa</button>
  <button class="btn scope-btn" data-scope="together">Together</button>
</div>
```

Add matching CSS next to the existing `.ratings-category-btn.active` rule:

```css
.scope-btn.active { background: var(--accent); color: #fff; border-color: var(--accent); }
```

- [ ] **Step 2: Wire the switcher to `activeScope` and re-render whichever tab is open**

```js
let activeScope = 'karl';

function canWriteScope(scope) {
  return scope === 'together' || (currentProfile && scope === currentProfile.display_name.toLowerCase());
}

document.querySelectorAll('.scope-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    if (btn.classList.contains('active')) return;
    document.querySelectorAll('.scope-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    activeScope = btn.dataset.scope;
    invalidateShowsCache();
    const tab = document.querySelector('.tab-btn.active')?.dataset.tab;
    if (tab === 'tierlist') initTierlistView();
    else if (tab === 'ratings') renderRatingsTab();
    else if (tab === 'stats') renderStatsTab();
    else loadShows();
  });
});
```

Default `activeScope` to the signed-in user's own scope right after sign-in: in `refreshAuthUI()`, after setting `currentProfile`, add `document.querySelector(\`.scope-btn[data-scope="${profile.display_name.toLowerCase()}"]\`)?.click();` (guarded so it only auto-switches once per sign-in, not on every auth-state tick — track with a `let hasAutoSwitchedScope = false;` flag set after the first successful profile fetch).

- [ ] **Step 3: Move pins server-side**

Replace `getPinned()`/`setPinned()` (previously `localStorage`) with:

```js
function getPinnedIds(rows) {
  return rows.filter(s => s.pinned).map(s => s.id);
}

async function togglePin(id, pinned) {
  if (!canWriteScope(activeScope)) return;
  await supabase.from('shows').update({ pinned }).eq('id', id);
  invalidateShowsCache();
  loadShows();
}
```

Update every call site that referenced `getPinned()`/`setPinned()` (the pin button's click handler, `loadShows()`'s pinned-sort logic) to instead read `s.pinned` directly off the row objects `fetchShows` returns, and call `togglePin(id, !currentlyPinned)` from the pin button's handler instead of the old `localStorage` toggle. Keep the existing max-5-pinned limit check, now reading `getPinnedIds(rows).length` instead of `getPinned().length`.

- [ ] **Step 4: Verify via Playwright**

Sign in as Karl (see Task 3 Step 3's note on magic-link limits — if a real session isn't available yet, verify the scope-switcher's read-only behavior instead): click each of the three scope buttons, confirm Watching/Tier List/Ratings/Stats reload and show the right data (Karl's 90 shows under "Karl", empty under "Liisa" and "Together"). Confirm pin buttons are disabled/no-op when `activeScope` isn't writable.

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "add: Karl/Liisa/Together scope switcher, move pins server-side"
```

---

### Task 5: Direct-write progress bump + mark-finished UI

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: `canWriteScope`, `invalidateShowsCache`, `loadShows` from Tasks 3–4.
- Produces: `bumpProgress(id, newEpisode)` and `markFinished(id)` — exported as top-level functions so Task 8 (Add Show flow) and any future UI can call them directly.

- [ ] **Step 1: Add episode-stepper and mark-finished markup to Watching cards**

In the card-rendering template inside `loadShows()` (the function building each `.show-card` for `active`), add, only when `canWriteScope(activeScope)`:

```js
const progressControls = canWriteScope(activeScope) ? `
  <div class="progress-controls">
    <button class="btn progress-step" data-id="${show.id}" data-delta="-1">−</button>
    <span class="progress-value">${show.currentEpisode}/${show.totalEpisodes}</span>
    <button class="btn progress-step" data-id="${show.id}" data-delta="1">+</button>
    <button class="btn mark-finished-btn" data-id="${show.id}">Mark Finished</button>
  </div>` : '';
```

Include `progressControls` in that card's template string, near where the episode count is already displayed.

- [ ] **Step 2: Implement `bumpProgress` and `markFinished`**

```js
async function bumpProgress(id, delta) {
  const rows = await fetchShows(activeScope);
  const show = rows.find(s => s.id === id);
  if (!show || !canWriteScope(activeScope)) return;
  const newEpisode = Math.max(0, Math.min(show.totalEpisodes, show.currentEpisode + delta));
  await supabase.from('shows').update({
    current_episode: newEpisode,
    season_episode: newEpisode, // seasons collapse to a single running total in this simplified control; per-season tracking still works via Task 8's Add Show flow setting initial values
    last_updated: new Date().toISOString().slice(0, 10),
  }).eq('id', id);
  invalidateShowsCache();
  loadShows();
}

async function markFinished(id) {
  const rows = await fetchShows(activeScope);
  const show = rows.find(s => s.id === id);
  if (!show || !canWriteScope(activeScope)) return;
  await supabase.from('shows').update({
    current_episode: show.totalEpisodes,
    season_episode: show.totalEpisodes,
    current_season: show.totalSeasons,
    in_tier_pool: true,
    last_updated: new Date().toISOString().slice(0, 10),
  }).eq('id', id);
  invalidateShowsCache();
  loadShows();
}

document.body.addEventListener('click', e => {
  const stepBtn = e.target.closest('.progress-step');
  if (stepBtn) { bumpProgress(stepBtn.dataset.id, parseInt(stepBtn.dataset.delta, 10)); return; }
  const finBtn = e.target.closest('.mark-finished-btn');
  if (finBtn) { markFinished(finBtn.dataset.id); return; }
});
```

- [ ] **Step 3: Verify via Playwright**

Sign in as Karl, on the Watching tab click `+` on a show, confirm the episode count increments by 1 and the card re-renders with the new value; click "Mark Finished" on a different show, confirm it moves to the Completed section.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "add: direct-write progress bump and mark-finished controls"
```

---

### Task 6: Ratings/notes direct writes, remove export flow

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: `currentProfile`, `invalidateShowsCache` from Tasks 3–4.
- Produces: `setRating(id, value)` / `setNote(id, text)` — same function names as the old `localStorage` versions but now `async` and writing to Supabase, so call sites need `await`.

- [ ] **Step 1: Replace `getRatings`/`setRating`/`getNotes`/`setNote` with Supabase-backed versions**

```js
async function setRating(id, value) {
  if (!currentProfile) return;
  await supabase.from('ratings').upsert({
    show_id: id, user_id: currentProfile.id, rating: value, updated_at: new Date().toISOString(),
  });
  invalidateShowsCache();
}

async function setNote(id, text) {
  if (!currentProfile) return;
  await supabase.from('ratings').upsert({
    show_id: id, user_id: currentProfile.id, note: text || null, updated_at: new Date().toISOString(),
  });
  invalidateShowsCache();
}
```

Update the star-click delegated listener (`document.body.addEventListener('click', e => { const btn = e.target.closest('.star-hit'); ... })`) to `await setRating(...)` and re-fetch the current value from `fetchShows` for the label update, since `getRatings()` no longer exists — replace `const current = getRatings()[id];` with `const rows = await fetchShows(activeScope); const current = rows.find(s => s.id === id)?.rating;`, and similarly replace the post-click `widget.innerHTML = starsInnerHTML(id, getRatings()[id]);` with a value read from a fresh `fetchShows` call.

Update the note-modal save handler the same way (`await setNote(...)` instead of the synchronous call).

- [ ] **Step 2: Remove the export flow**

Delete the `#btn-export-ratings` button from the Ratings tab's HTML, the `countUnsynced`/`updateSyncBadge` functions, and the `btn-export-ratings` click handler that built the `RATINGS & NOTES EXPORT` clipboard text. Remove the calls to `updateSyncBadge()` scattered through `renderRatingsTab()`.

- [ ] **Step 3: Verify via Playwright**

Sign in as Karl, go to Ratings tab, click a star rating on a show, confirm it persists after switching tabs and back (re-fetches from Supabase, not `localStorage`). Add a note via the note modal, confirm it saves. Confirm the "Copy Ratings & Notes" button and unsynced badge are gone from the UI.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "add: direct-write ratings/notes to Supabase, remove export-and-paste flow"
```

---

### Task 7: Watchlist mood tags

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: `canWriteScope`, `invalidateShowsCache` from Tasks 3–4.
- Produces: none consumed by later tasks — this is a leaf feature.

- [ ] **Step 1: Add a tag-pill filter bar above the watchlist section**

```html
<div class="tag-filter-bar" id="watchlist-tag-filter"></div>
```

```js
function renderWatchlistTagFilter(watchlist, activeTags) {
  const allTags = [...new Set(watchlist.flatMap(s => s.tags || []))].sort();
  const bar = document.getElementById('watchlist-tag-filter');
  bar.innerHTML = allTags.map(tag => `<button class="btn tag-pill${activeTags.includes(tag) ? ' active' : ''}" data-tag="${tag}">${tag}</button>`).join('');
  bar.querySelectorAll('.tag-pill').forEach(btn => {
    btn.addEventListener('click', () => {
      btn.classList.toggle('active');
      loadShows(); // re-render with updated tag filter read fresh from the DOM
    });
  });
}
```

In `loadShows()`, after rendering the watchlist tag bar, filter the watchlist array by the currently-active tag pills (`document.querySelectorAll('.tag-pill.active')`) before rendering the watchlist section — a show matches if it has *any* active tag, or if no tags are active (show everything).

- [ ] **Step 2: Add a freeform tag input to the watchlist "add" flow**

The current watchlist has no in-page add UI (it's Claude-mediated via `data.json` today, per `CLAUDE.md`) — for Together specifically, add a small inline form:

```html
<div class="watchlist-add" id="watchlist-add" style="display:none">
  <input type="text" id="watchlist-add-title" placeholder="Title…">
  <input type="text" id="watchlist-add-tags" placeholder="tags, comma, separated">
  <button class="btn" id="watchlist-add-btn">+ Add</button>
</div>
```

Show this form only when `canWriteScope(activeScope)` (toggle its `display` in the same place the scope switcher's re-render happens). Wire `#watchlist-add-btn`:

```js
document.getElementById('watchlist-add-btn').addEventListener('click', async () => {
  const title = document.getElementById('watchlist-add-title').value.trim();
  const tagsRaw = document.getElementById('watchlist-add-tags').value.trim();
  if (!title) return;
  const id = title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
  await supabase.from('shows').insert({
    id, title, category: 'anime', scope: activeScope, list_status: 'watchlist',
    tags: tagsRaw ? tagsRaw.split(',').map(t => t.trim()).filter(Boolean) : null,
  });
  document.getElementById('watchlist-add-title').value = '';
  document.getElementById('watchlist-add-tags').value = '';
  invalidateShowsCache();
  loadShows();
});
```

- [ ] **Step 3: Verify via Playwright**

Switch to Together scope, use the add form to add a show with tags "brainrot, funny", confirm it appears in the watchlist with those tags, confirm the tag-pill bar shows both tags, click "brainrot" and confirm only matching shows remain visible.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "add: mood-tagged watchlist with in-page add form"
```

---

### Task 8: Add Show flow via service-role script

**Files:**
- Modify: `index.html` (update the Add Show modal copy)
- Modify: `CLAUDE.md` (replace the "Research episode counts" / data.json-editing instructions with the new Supabase-write instructions)

**Interfaces:**
- Consumes: `scripts/supabase-write.mjs` from Task 2.
- Produces: none — this is the terminal task for the Claude-mediated add-show workflow.

- [ ] **Step 1: Update the Add Show modal copy**

```html
<p>
  Tell Claude what you want to add and which list —<br>
  e.g. <em>"Add Vinland Saga to my list, I'm on S1E5"</em> or <em>"add Perfect Blue to our watchlist"</em><br><br>
  Claude will look up the episode count and add it directly. Reload to see it appear.
</p>
```

- [ ] **Step 2: Rewrite the relevant `CLAUDE.md` sections**

Replace the "Auto-commit after data.json edits" and "Research episode counts when adding a new show" sections with:

```markdown
## Adding a new show

When adding a new show, first ask (if not already clear from context) which
scope it belongs to: Karl's list, Liisa's list, or Together.

Look up the exact episode count before writing the entry, same as before:
- Anime: Jikan API (`https://api.jikan.moe/v4/anime?q=<title>&limit=1`).
- Live-action: TMDB.

Then insert directly into Supabase instead of editing `data.json`:

\`\`\`bash
node scripts/supabase-write.mjs shows '[{
  "id": "show-slug", "title": "Show Title", "category": "anime",
  "scope": "karl", "poster_url": "...", "studio": "...", "genres": ["..."],
  "total_episodes": 24, "total_seasons": 1, "current_episode": 5,
  "season_episode": 5, "current_season": 1, "list_status": "watching",
  "last_updated": "2026-08-14"
}]'
\`\`\`

No `git commit` is needed for this action specifically — nothing changed in
the repo, only in Supabase.
```

Remove the "Bumping episode progress" and "Marking a show finished" sections' instructions to edit `data.json` — those are now handled by the in-page controls from Task 5, so replace them with a one-line note: "Progress bumps and marking shows finished are handled in-page now (episode stepper / Mark Finished button) — no longer Claude-mediated."

Remove the "Merging a RATINGS & NOTES EXPORT paste" section entirely (ratings/notes are direct writes now, per Task 6).

- [ ] **Step 3: Verify by adding one real show end-to-end**

Ask Karl for a show he actually wants added; look it up via Jikan/TMDB as usual, run the `supabase-write.mjs` command, then reload the app and confirm it appears in the correct scope's Watching tab with correct episode/poster/genre data.

- [ ] **Step 4: Commit**

```bash
git add index.html CLAUDE.md
git commit -m "update: Add Show flow writes to Supabase, rewrite CLAUDE.md rules"
```

---

### Task 9: Letterboxd import script

**Files:**
- Create: `scripts/import-letterboxd.mjs`

**Interfaces:**
- Consumes: `scripts/supabase-write.mjs`'s pattern (this script talks to Supabase directly rather than shelling out, for simplicity — see Step 1) and the `shows`/`ratings` schema from Task 1.
- Produces: none — terminal task.

- [ ] **Step 1: Write the import script**

```js
// scripts/import-letterboxd.mjs
// Usage: node scripts/import-letterboxd.mjs <path-to-ratings.csv> <liisa-user-id>
import { readFileSync } from 'node:fs';

const SUPABASE_URL = 'https://ppelaixzzgfhqximihpr.supabase.co';
const serviceKey = readFileSync(new URL('../.supabase-service-key', import.meta.url), 'utf8').trim();

const [, , csvPath, userId] = process.argv;
if (!csvPath || !userId) {
  console.error('Usage: node scripts/import-letterboxd.mjs <path-to-ratings.csv> <liisa-user-id>');
  process.exit(1);
}

// Letterboxd ratings.csv columns: Date,Name,Year,Letterboxd URI,Rating
function parseCsv(text) {
  const [header, ...lines] = text.trim().split('\n');
  const cols = header.split(',');
  return lines.map(line => {
    // naive split is fine here — Letterboxd quotes titles containing commas
    const matches = [...line.matchAll(/"([^"]*)"|([^,]+)/g)].map(m => m[1] ?? m[2] ?? '');
    return Object.fromEntries(cols.map((c, i) => [c, matches[i] ?? '']));
  });
}

async function fetchAllShows() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/shows?select=id,title`, {
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
  });
  return res.json();
}

function slugify(title) {
  return title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
}

const rows = parseCsv(readFileSync(csvPath, 'utf8'));
const existingShows = await fetchAllShows();
const unmatched = [];
const toInsertShows = [];
const toInsertRatings = [];

for (const row of rows) {
  const title = row.Name;
  const rating = parseFloat(row.Rating);
  let match = existingShows.find(s => s.title.toLowerCase() === title.toLowerCase());
  if (!match) {
    const id = slugify(`${title}-${row.Year || ''}`);
    match = { id, title };
    toInsertShows.push({ id, title, category: 'movie', scope: 'liisa', list_status: null, in_tier_pool: true });
    unmatched.push(title);
  }
  if (!isNaN(rating)) {
    toInsertRatings.push({ show_id: match.id, user_id: userId, rating });
  }
}

if (toInsertShows.length) {
  await fetch(`${SUPABASE_URL}/rest/v1/shows`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, Prefer: 'resolution=merge-duplicates' },
    body: JSON.stringify(toInsertShows),
  });
}
if (toInsertRatings.length) {
  await fetch(`${SUPABASE_URL}/rest/v1/ratings`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, Prefer: 'resolution=merge-duplicates' },
    body: JSON.stringify(toInsertRatings),
  });
}

console.log(`Imported ${toInsertRatings.length} ratings, created ${toInsertShows.length} new show rows.`);
if (unmatched.length) {
  console.log('\nCreated as new (no existing title match — review these for accuracy):');
  unmatched.forEach(t => console.log(`  - ${t}`));
}
```

- [ ] **Step 2: Verify with a small hand-built test CSV**

Run:
```bash
printf 'Date,Name,Year,Letterboxd URI,Rating\n2024-01-01,"Perfect Blue",1997,https://boxd.it/x,4.5\n' > /tmp/test-letterboxd.csv
node scripts/import-letterboxd.mjs /tmp/test-letterboxd.csv <liisa-user-id-from-profiles-table>
```

Expected: prints "Imported 1 ratings, created 1 new show rows." and lists "Perfect Blue" under unmatched (since it's not already in `shows`). Confirm via Supabase Table Editor that a new `shows` row and a matching `ratings` row exist.

- [ ] **Step 3: Clean up the test row and commit**

```bash
curl -s -X DELETE "https://ppelaixzzgfhqximihpr.supabase.co/rest/v1/shows?id=eq.perfect-blue-1997" -H "apikey: $(cat .supabase-service-key)" -H "Authorization: Bearer $(cat .supabase-service-key)"
git add scripts/import-letterboxd.mjs
git commit -m "add: Letterboxd CSV import script"
```

---

### Task 10: Retire `data.json`

**Files:**
- Delete: `data.json`
- Modify: `CLAUDE.md` (remove any remaining `data.json` references)

**Interfaces:**
- Consumes: nothing — by this point no code path reads `data.json` (confirmed in Task 3).

- [ ] **Step 1: Grep for any remaining `data.json` references**

Run: `grep -n "data.json" index.html CLAUDE.md`

Expected: no matches (Task 3 removed the reads, Task 8 removed the write-instruction references). If any remain, remove them before proceeding.

- [ ] **Step 2: Confirm the live app works with `data.json` absent**

Run: `mv data.json /tmp/data.json.bak` (don't delete yet — reversible move first), reload the app in the browser, confirm every tab still renders correctly from Supabase alone.

- [ ] **Step 3: Delete for real and commit**

```bash
git rm data.json
git commit -m "remove: data.json, fully retired in favor of Supabase backend"
```

---

## Self-Review Notes

- **Spec coverage:** accounts/auth (Task 3), schema/RLS (Task 1), scope switcher (Task 4), progress/finish writes (Task 5), ratings/notes writes (Task 6), mood tags (Task 7), Add Show via service key (Tasks 2, 8), Letterboxd import (Task 9), data.json retirement (Task 10) — all spec sections have a task.
- **Type consistency:** `fetchShows()` (Task 3) is the single field-name contract every later task relies on (`currentEpisode`, `totalEpisodes`, `inTierPool`, `listStatus`, `pinned`, `rating`, `note`) — Tasks 4–7 all read/write against those same names, not the raw `snake_case` DB columns.
- **Known limitation carried from the spec:** the RLS write policy's `scope::text = lower(display_name)` match only works for exactly this two-person setup — flagged in the spec's "Open risks," unchanged here since fixing it isn't needed for launch.
