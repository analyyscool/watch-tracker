# Written Media Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 5th "Reading" tab for tracking books, manga, manhwa, and webnovels — currently-reading/completed/to-read sections, chapter/page progress controls, pinning, and ratings/notes — parallel to the existing Watching tab, backed by a new `written_media` Supabase table.

**Architecture:** A new `written_media` table (separate from `shows`, since progress units differ — pages for books, chapters+volumes for manga/manhwa/webnovels) plus an alteration to the existing `ratings` table so it can point at either a `shows` row or a `written_media` row via a nullable second foreign key. `index.html` gains a parallel set of functions (`fetchWrittenMedia`, `loadReading`, `bumpChapter`, `setPage`, etc.) that mirror the existing shows-side functions closely enough to reuse the same CSS classes and card structure.

**Tech Stack:** Same as the rest of the app — Supabase (Postgres + Auth + PostgREST), `supabase-js` v2 (CDN), vanilla JS/HTML, no build step. `scripts/supabase-write.mjs` (already generic on table name) handles all Claude-mediated writes with no changes needed.

**Spec:** `docs/superpowers/specs/2026-08-14-written-media-design.md`

## Global Constraints

- No build step — everything runs from static files opened via a plain HTTP server.
- No new npm dependencies.
- Match existing `index.html` code style: no framework, `document.getElementById`/`querySelectorAll`, template-literal HTML strings, the existing `.tab-btn`/`.scope-btn` toggle pattern for any new toggle UI, event delegation on `document.body` for anything rendered repeatedly.
- Reuse existing CSS classes (`.card`, `.card-poster`, `.card-body`, `.card-top`, `.card-title`, `.card-right`, `.card-meta`, `.card-pct`, `.card-tags`, `.card-stats`, `.stat`, `.progress-bar`, `.progress-fill`, `.progress-controls`, `.progress-step`, `.mark-finished-btn`, `.pin-btn`, `.note-btn`, `.star-rating`) wherever the reading cards need the same visual shape as show cards — only add new CSS for things that genuinely don't exist yet (the page-number input, the category badge).
- Every task must leave the app in a working, loadable state.
- Every Supabase write call site must destructure `{ error }` and call the existing `checkWriteError(error)` guard before invalidating any cache — matches the pattern every current shows-side write already follows.

---

### Task 1: `written_media` schema, RLS, and `ratings` table alteration

**Files:**
- Create: `supabase/migration-written-media.sql`

**Interfaces:**
- Produces: the `written_media` table, `written_media_category`/`written_media_status` enums, and the altered `ratings` table (nullable `show_id`, new nullable `written_media_id`, surrogate `id` primary key, two partial unique indexes, one check constraint) that every later task's Supabase queries depend on. Exact column names are load-bearing for Tasks 2–7.

- [ ] **Step 1: Write the migration SQL**

```sql
-- supabase/migration-written-media.sql
-- Run once in the Supabase SQL Editor.

create type written_media_category as enum ('book', 'manga', 'manhwa', 'webnovel');
create type written_media_status as enum ('reading', 'completed', 'plan_to_read');

create table written_media (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category written_media_category not null,
  scope show_scope not null,
  author text,
  cover_url text,
  genres text[],
  total_chapters int,
  current_chapter int,
  total_volumes int,
  current_volume int,
  total_pages int,
  current_page int,
  list_status written_media_status not null default 'plan_to_read',
  pinned boolean not null default false,
  tags text[],
  last_updated date,
  created_at timestamptz not null default now()
);

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

-- Extend ratings to point at either a show or a written_media row.
alter table ratings add column id uuid default gen_random_uuid();
alter table ratings add column written_media_id uuid references written_media(id) on delete cascade;

alter table ratings drop constraint ratings_pkey;
alter table ratings alter column show_id drop not null;
update ratings set id = gen_random_uuid() where id is null;
alter table ratings alter column id set not null;
alter table ratings add primary key (id);

create unique index ratings_show_user_uniq
  on ratings (show_id, user_id) where show_id is not null;
create unique index ratings_written_media_user_uniq
  on ratings (written_media_id, user_id) where written_media_id is not null;

alter table ratings add constraint ratings_exactly_one_target
  check ((show_id is not null) <> (written_media_id is not null));
```

- [ ] **Step 2: Hand off to Karl to run the SQL**

This step is manual — DDL can't run through the REST API's service-role writes (`scripts/supabase-write.mjs` only does row inserts/upserts), it needs the SQL Editor. Report back to Karl:

1. Open the Supabase Dashboard → SQL Editor.
2. Paste the full contents of `supabase/migration-written-media.sql` and run it.

Expected: SQL Editor reports success with no errors. Table Editor shows a new `written_media` table (0 rows) and `ratings` now has an `id`/`written_media_id` column.

- [ ] **Step 3: Verify the `ratings` alteration didn't break existing rows**

Run:
```bash
node -e "
const { readFileSync } = require('fs');
const key = readFileSync('.supabase-service-key', 'utf8').trim();
const base = 'https://ppelaixzzgfhqximihpr.supabase.co';
fetch(base + '/rest/v1/ratings?select=*', { headers: { apikey: key, Authorization: 'Bearer ' + key } })
  .then(r => r.json()).then(d => console.log(JSON.stringify(d, null, 2)));
"
```

Expected: every existing row still has its `show_id`, `user_id`, `rating`/`note` values intact, now also has a non-null `id` and a null `written_media_id`.

- [ ] **Step 4: Fix the now-stale `setRating`/`setNote` upsert conflict target**

`ratings`' primary key changed from `(show_id, user_id)` to a surrogate `id` in Step 1. The existing `setRating`/`setNote` in `index.html` (shows-side, unchanged since the multi-user backend plan) call `.upsert({...})` with no `onConflict` — PostgREST's upsert defaults its conflict target to the table's primary key, which is now just `id`, a column these calls never set. Left as-is, every future rating/note save would silently **insert a new row** instead of updating the existing one. This must land in the same commit as the schema change, not wait for Task 6 (which generalizes these functions further for written media).

Update both functions in `index.html`:

```js
async function setRating(id, value) {
  if (!currentProfile) return;
  const { error } = await supabase.from('ratings').upsert({
    show_id: id, user_id: currentProfile.id, rating: value, updated_at: new Date().toISOString(),
  }, { onConflict: 'show_id,user_id' });
  if (checkWriteError(error)) return;
  invalidateShowsCache();
}

async function setNote(id, text) {
  if (!currentProfile) return;
  const { error } = await supabase.from('ratings').upsert({
    show_id: id, user_id: currentProfile.id, note: text || null, updated_at: new Date().toISOString(),
  }, { onConflict: 'show_id,user_id' });
  if (checkWriteError(error)) return;
  invalidateShowsCache();
}
```

- [ ] **Step 5: Verify existing shows-side ratings still upsert correctly**

Sign in as Karl, rate an already-rated show a second time (a different star value), reload, and query `ratings` directly (same `node -e` pattern as Step 3) to confirm there's still exactly one row for that `(show_id, user_id)` pair, not two.

- [ ] **Step 6: Commit**

```bash
git add supabase/migration-written-media.sql index.html
git commit -m "add: written_media schema + ratings table alteration for dual-target ratings

Also fixes setRating/setNote's upsert conflict target, which the PK
change from (show_id, user_id) to a surrogate id would otherwise have
silently broken (inserts instead of updates)."
```

---

### Task 2: Reading tab skeleton — `fetchWrittenMedia`, read-only render

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: `written_media` table from Task 1, `activeScope`/`canWriteScope`/`rerenderActiveTab` (existing, defined near the auth section around `function rerenderActiveTab()`).
- Produces: `fetchWrittenMedia(scope)` — async function returning all `written_media` rows for a scope, joined with the signed-in user's own rating/note (same shape as `fetchShows`). `invalidateWrittenMediaCache()`. `loadReading()` — the render entry point Tasks 4–7 call after every write. All exported as top-level functions.

- [ ] **Step 1: Add the "Reading" tab button and view container**

Modify the tabs bar:

```html
<div class="tabs">
  <button class="tab-btn active" data-tab="watching">Watching</button>
  <button class="tab-btn" data-tab="tierlist">Tier List</button>
  <button class="tab-btn" data-tab="ratings">Ratings</button>
  <button class="tab-btn" data-tab="stats">Stats</button>
  <button class="tab-btn" data-tab="reading">Reading</button>
</div>
```

Add a new view container as a sibling of `#view-watching` (right after its closing `</div>`, inside `#app-content`):

```html
<div id="view-reading" style="display:none">
  <div class="sort-filter-bar" id="reading-active-sf">
    <select class="sf-select" id="reading-sort">
      <option value="pinned">Sort: Pinned first</option>
      <option value="updated">Sort: Last updated</option>
      <option value="alpha">Sort: A–Z</option>
    </select>
    <select class="sf-select" id="reading-genre"><option value="">Genre: All</option></select>
    <select class="sf-select" id="reading-category"><option value="">Type: All</option></select>
  </div>

  <div id="reading-grid"></div>
  <div id="reading-empty">Nothing currently being read.</div>

  <div class="section-divider" id="reading-completed-divider" style="display:none"><span>completed</span></div>
  <div id="reading-completed"></div>

  <div class="section-divider"><span>to read</span></div>
  <div id="to-read-add" class="watchlist-add" style="display:none">
    <input type="text" id="to-read-add-title" placeholder="Title…">
    <select id="to-read-add-category">
      <option value="book">Book</option>
      <option value="manga">Manga</option>
      <option value="manhwa">Manhwa</option>
      <option value="webnovel">Webnovel</option>
    </select>
    <input type="text" id="to-read-add-tags" placeholder="tags, comma, separated">
    <button class="btn" id="to-read-add-btn">+ Add</button>
  </div>
  <input type="text" id="to-read-search" class="search-input" placeholder="Filter to-read…">
  <div id="to-read-list"></div>
</div>
```

Add matching CSS next to the existing `#grid`/`#empty` rules — `#reading-grid`/`#reading-completed` need the same flex-column layout as `#grid`, and `#reading-empty` needs the same empty-state treatment as `#empty` (which is ID-scoped in the existing CSS, not a reusable class, hence the new rules rather than a shared class):

```css
#reading-grid, #reading-completed {
  display: flex;
  flex-direction: column;
  gap: 0.625rem;
}

#reading-empty {
  display: none;
  text-align: center;
  padding: 3.5rem 1rem;
  font-size: 0.7rem;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--muted);
}
```

- [ ] **Step 2: Add `fetchWrittenMedia` next to the existing `fetchShows`**

```js
let writtenMediaCache = null;

async function fetchWrittenMedia(scope) {
  const key = scope || 'all';
  if (writtenMediaCache && writtenMediaCache.key === key) return writtenMediaCache.rows;
  let query = supabase.from('written_media').select('*, ratings(user_id, rating, note)');
  if (scope) query = query.eq('scope', scope);
  const { data, error } = await query;
  if (error) { console.error(error); return []; }
  const rows = data.map(m => ({
    id: m.id, title: m.title, category: m.category, scope: m.scope,
    author: m.author, coverUrl: m.cover_url, genres: m.genres,
    totalChapters: m.total_chapters, currentChapter: m.current_chapter,
    totalVolumes: m.total_volumes, currentVolume: m.current_volume,
    totalPages: m.total_pages, currentPage: m.current_page,
    listStatus: m.list_status, pinned: m.pinned, tags: m.tags, lastUpdated: m.last_updated,
    rating: currentProfile ? m.ratings.find(r => r.user_id === currentProfile.id)?.rating ?? null : null,
    note: currentProfile ? m.ratings.find(r => r.user_id === currentProfile.id)?.note ?? null : null,
  }));
  writtenMediaCache = { key, rows };
  return rows;
}

function invalidateWrittenMediaCache() { writtenMediaCache = null; }
```

- [ ] **Step 3: Add a read-only `loadReading()` that renders all three sections**

```js
function progressLabel(m) {
  if (m.category === 'book') {
    return m.totalPages ? `${m.currentPage || 0}/${m.totalPages}p` : `${m.currentPage || 0}p`;
  }
  const chapterPart = m.totalChapters ? `Ch ${m.currentChapter || 0}/${m.totalChapters}` : `Ch ${m.currentChapter || 0}`;
  return m.totalVolumes ? `Vol ${m.currentVolume || 0}/${m.totalVolumes} · ${chapterPart}` : chapterPart;
}

function progressPct(m) {
  if (m.category === 'book') {
    return m.totalPages ? Math.round((m.currentPage || 0) / m.totalPages * 100) : 0;
  }
  return m.totalChapters ? Math.round((m.currentChapter || 0) / m.totalChapters * 100) : 0;
}

async function loadReading() {
  const rows = await fetchWrittenMedia(activeScope);
  const reading = rows.filter(m => m.listStatus === 'reading');
  const completed = rows.filter(m => m.listStatus === 'completed');
  const toRead = rows.filter(m => m.listStatus === 'plan_to_read');
  const pinned = reading.filter(m => m.pinned).map(m => m.id);

  populateFilterSelect(document.getElementById('reading-genre'), reading.flatMap(m => m.genres || []), 'Genre', getSF('reading').genre);
  populateFilterSelect(document.getElementById('reading-category'), reading.map(m => m.category), 'Type', getSF('reading').category);
  document.getElementById('reading-sort').value = getSF('reading').sort || 'pinned';

  const grid = document.getElementById('reading-grid');
  const empty = document.getElementById('reading-empty');
  grid.innerHTML = '';
  if (reading.length === 0) {
    empty.style.display = 'block';
  } else {
    empty.style.display = 'none';
    reading.forEach(m => {
      const card = document.createElement('div');
      const isPinned = pinned.includes(m.id);
      card.className = 'card' + (isPinned ? ' pinned' : '');
      card.innerHTML = `
        ${m.coverUrl ? `<img class="card-poster" src="${m.coverUrl}" alt="" onerror="this.remove()">` : ''}
        <div class="card-body">
          <div class="card-top">
            <div class="card-title">${m.title}</div>
            <div class="card-right">
              <span class="card-meta">${m.category}</span>
              <span class="card-pct">${progressPct(m)}%</span>
            </div>
          </div>
          <div class="card-tags">${m.author || ''}</div>
          <div class="card-stats">
            <span class="stat">${progressLabel(m)}</span>
            <span class="stat">${timeAgo(m.lastUpdated)}</span>
          </div>
          <div class="progress-bar"><div class="progress-fill" style="width:${progressPct(m)}%"></div></div>
        </div>
      `;
      grid.appendChild(card);
    });
  }

  const completedEl = document.getElementById('reading-completed');
  const completedDivider = document.getElementById('reading-completed-divider');
  completedEl.innerHTML = '';
  if (completed.length === 0) {
    completedDivider.style.display = 'none';
  } else {
    completedDivider.style.display = '';
    completed.forEach(m => {
      const card = document.createElement('div');
      card.className = 'card';
      card.innerHTML = `
        ${m.coverUrl ? `<img class="card-poster" src="${m.coverUrl}" alt="" onerror="this.remove()">` : ''}
        <div class="card-body">
          <div class="card-top">
            <div class="card-title">${m.title}</div>
            <div class="card-right">
              <span class="card-meta">${m.category}</span>
              <span class="card-pct done">done</span>
            </div>
          </div>
          <div class="card-tags">${m.author || ''}</div>
          <div class="card-stats"><span class="stat">${timeAgo(m.lastUpdated)}</span></div>
        </div>
      `;
      completedEl.appendChild(card);
    });
  }

  document.getElementById('to-read-list').innerHTML = toRead.map(m => `
    <div class="watchlist-item"><span class="watchlist-name">${m.title}</span><span class="watchlist-cta">→ start</span></div>
  `).join('');
}
```

- [ ] **Step 4: Wire the tab button and scope-switch re-render**

In the tab-click handler (near `document.querySelectorAll('.tab-btn').forEach(...)`), add a new `display` toggle line for `view-reading` alongside the existing three, and a `if (tab === 'reading') loadReading();` branch alongside the `tierlist`/`ratings`/`stats` branches.

In `rerenderActiveTab()` (near the auth section), add a branch: `else if (tab === 'reading') loadReading();` before the final `else loadShows();` fallback.

- [ ] **Step 5: Verify via Playwright**

Sign in as Karl, click the "Reading" tab, confirm it shows "Nothing currently being read." with no console errors. Confirm switching scopes (Karl/Liisa/Together) while on the Reading tab doesn't throw.

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "add: Reading tab skeleton, fetchWrittenMedia read path"
```

---

### Task 3: Add-entry flow + `CLAUDE.md` docs + first real entries

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: `scripts/supabase-write.mjs` (unchanged, already generic on table name).
- Produces: none — this documents the Claude-mediated add flow and seeds real data so Tasks 4–7 have something to test against.

- [ ] **Step 1: Add a "Adding a book/manga/manhwa/webnovel" section to `CLAUDE.md`**

Insert after the existing "Adding a new show" section:

```markdown
## Adding a book, manga, manhwa, or webnovel

When adding a written-media entry, first ask (if not already clear from
context) which scope it belongs to: Karl's list, Liisa's list, or Together.

Look up chapter/volume counts before writing the entry:
- Manga (and manhwa, when MAL has it): query Jikan
  (`https://api.jikan.moe/v4/manga?q=<title>&limit=1`) — gives `chapters`,
  `volumes`, `status`, cover (`images.jpg.large_image_url`), `authors[0].name`,
  and `genres[].name`.
- Manhwa not on MAL, webnovels, and books: no reliable free API — ask the
  user for author, chapter/page count (or leave null if unknown/ongoing),
  and cover art URL if they have one.

`category` is one of `"book"`, `"manga"`, `"manhwa"`, or `"webnovel"`.
`total_pages`/`current_page` are only meaningful for `"book"`; the rest use
`total_chapters`/`current_chapter` (plus `total_volumes`/`current_volume`
when the source has volumes).

Then insert directly into Supabase:

\`\`\`bash
node scripts/supabase-write.mjs written_media '[{
  "title": "Title", "category": "manga",
  "scope": "karl", "author": "...", "cover_url": "...", "genres": ["..."],
  "total_chapters": 100, "current_chapter": 5,
  "total_volumes": 12, "current_volume": 1,
  "list_status": "reading",
  "last_updated": "2026-08-14"
}]'
\`\`\`

No `git commit` is needed for this action — nothing changed in the repo,
only in Supabase.
```

- [ ] **Step 2: Add one real entry per category with Karl**

Ask Karl for one real manga/manhwa/webnovel and one real book he's actually reading. Look up the manga/manhwa via Jikan if available; take the rest as manual entry per the new `CLAUDE.md` section. Insert both via `supabase-write.mjs`.

Expected: `node scripts/supabase-write.mjs written_media '[...]'` prints the inserted rows as JSON.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "add: written-media add-flow docs, CLAUDE.md"
```

---

### Task 4: Progress controls — chapter stepper (manga/manhwa/webnovel), page input (books), mark finished

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: `fetchWrittenMedia`, `invalidateWrittenMediaCache`, `loadReading`, `canWriteScope`, `checkWriteError` (existing).
- Produces: `bumpChapter(id, delta)`, `setPage(id, page)`, `markReadingFinished(id)` — top-level functions.

- [ ] **Step 1: Add progress controls to the Currently Reading card template**

In `loadReading()`'s reading-card template (Task 2, Step 3), replace the static `progressLabel(m)` stat line with write controls when `canWriteScope(activeScope)`:

```js
const progressControls = canWriteScope(activeScope)
  ? (m.category === 'book'
      ? `<div class="progress-controls">
           <input type="number" class="page-input" data-id="${m.id}" min="0" max="${m.totalPages || ''}" value="${m.currentPage || 0}">
           <span class="progress-value">/ ${m.totalPages || '?'}p</span>
           <button class="btn mark-finished-btn" data-media-id="${m.id}">Mark Finished</button>
         </div>`
      : `<div class="progress-controls">
           <button class="btn chapter-step" data-id="${m.id}" data-delta="-1">−</button>
           <span class="progress-value">Ch ${m.currentChapter || 0}${m.totalChapters ? '/' + m.totalChapters : ''}</span>
           <button class="btn chapter-step" data-id="${m.id}" data-delta="1">+</button>
           <button class="btn mark-finished-btn" data-media-id="${m.id}">Mark Finished</button>
         </div>`)
  : '';
```

Add `${progressControls}` at the end of the card's `.card-body` template, after the existing `.progress-bar` div.

Add matching CSS next to the existing `.progress-controls`/`.progress-value` rules:

```css
.page-input {
  width: 4.5rem;
  font-family: 'DM Mono', monospace;
  font-size: 0.7rem;
  padding: 0.3rem 0.4rem;
  border: 1px solid var(--border2);
  border-radius: 4px;
  background: var(--bg);
  color: var(--text);
}
```

- [ ] **Step 2: Implement `bumpChapter`, `setPage`, `markReadingFinished`**

```js
async function bumpChapter(id, delta) {
  const rows = await fetchWrittenMedia(activeScope);
  const m = rows.find(r => r.id === id);
  if (!m || !canWriteScope(activeScope)) return;
  const max = m.totalChapters ?? Infinity;
  const newChapter = Math.max(0, Math.min(max, (m.currentChapter || 0) + delta));
  const { error } = await supabase.from('written_media').update({
    current_chapter: newChapter,
    last_updated: new Date().toISOString().slice(0, 10),
  }).eq('id', id);
  if (checkWriteError(error)) return;
  invalidateWrittenMediaCache();
  loadReading();
}

async function setPage(id, page) {
  const rows = await fetchWrittenMedia(activeScope);
  const m = rows.find(r => r.id === id);
  if (!m || !canWriteScope(activeScope)) return;
  const max = m.totalPages ?? Infinity;
  const newPage = Math.max(0, Math.min(max, page));
  const { error } = await supabase.from('written_media').update({
    current_page: newPage,
    last_updated: new Date().toISOString().slice(0, 10),
  }).eq('id', id);
  if (checkWriteError(error)) return;
  invalidateWrittenMediaCache();
  loadReading();
}

async function markReadingFinished(id) {
  const rows = await fetchWrittenMedia(activeScope);
  const m = rows.find(r => r.id === id);
  if (!m || !canWriteScope(activeScope)) return;
  const { error } = await supabase.from('written_media').update({
    current_chapter: m.totalChapters ?? m.currentChapter,
    current_page: m.totalPages ?? m.currentPage,
    current_volume: m.totalVolumes ?? m.currentVolume,
    list_status: 'completed',
    last_updated: new Date().toISOString().slice(0, 10),
  }).eq('id', id);
  if (checkWriteError(error)) return;
  invalidateWrittenMediaCache();
  loadReading();
}

document.body.addEventListener('click', e => {
  const chBtn = e.target.closest('.chapter-step');
  if (chBtn) { bumpChapter(chBtn.dataset.id, parseInt(chBtn.dataset.delta, 10)); return; }
  const finBtn = e.target.closest('.mark-finished-btn[data-media-id]');
  if (finBtn) { markReadingFinished(finBtn.dataset.mediaId); return; }
});

document.body.addEventListener('change', e => {
  const input = e.target.closest('.page-input');
  if (!input) return;
  const page = parseInt(input.value, 10);
  if (!isNaN(page)) setPage(input.dataset.id, page);
});
```

Note the existing `.mark-finished-btn` delegated listener (from the shows side, Task 5 of the multi-user plan) matches on `.mark-finished-btn` with `data-id` — this new listener scopes to `[data-media-id]` specifically so the two don't collide on the same button class.

- [ ] **Step 3: Verify via Playwright**

Sign in as Karl, go to Reading tab, click `+` on the manga entry from Task 3 and confirm the chapter count increments and persists after a tab switch. Type a page number into the book entry's input and blur, confirm it saves. Click "Mark Finished" on one entry, confirm it moves to the Completed section.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "add: chapter/page progress controls and mark-finished for reading"
```

---

### Task 5: Pinning for `written_media`

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: `fetchWrittenMedia`, `invalidateWrittenMediaCache`, `loadReading`, `canWriteScope`, `checkWriteError`, `MAX_PINNED` (existing constant from the shows side, value 5).
- Produces: `toggleReadingPin(id)`.

- [ ] **Step 1: Add the pin button to the Currently Reading card**

In the reading-card template's `.card-right` block, add the pin button before the category badge, matching the shows-card pin button exactly:

```js
const isPinned = pinned.includes(m.id);
// ...inside the template string's .card-right div:
`<button class="pin-btn${isPinned ? ' pinned' : ''}" ${canWriteScope(activeScope) ? '' : 'disabled'} onclick="toggleReadingPin('${m.id}')" aria-label="${isPinned ? 'Unpin' : 'Pin'} ${m.title}">
  <svg width="14" height="14" viewBox="0 0 24 24" fill="${isPinned ? 'currentColor' : 'none'}" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path>
    <circle cx="12" cy="10" r="3"></circle>
  </svg>
</button>`
```

- [ ] **Step 2: Implement `toggleReadingPin` and sort pinned-first**

```js
async function toggleReadingPin(id) {
  if (!canWriteScope(activeScope)) return;
  const rows = await fetchWrittenMedia(activeScope);
  const m = rows.find(r => r.id === id);
  if (!m) return;
  const current = !!m.pinned;
  const reading = rows.filter(r => r.listStatus === 'reading');
  if (!current && reading.filter(r => r.pinned).length >= MAX_PINNED) {
    showToast(`Max ${MAX_PINNED} pinned — unpin one first`);
    return;
  }
  const { error } = await supabase.from('written_media').update({ pinned: !current }).eq('id', id);
  if (checkWriteError(error)) return;
  invalidateWrittenMediaCache();
  loadReading();
}
```

In `loadReading()`, before rendering the grid, split `reading` into pinned-first order the same way `loadShows()` does for the Watching tab:

```js
const pinnedReading = reading.filter(m => m.pinned);
const nonPinnedReading = reading.filter(m => !m.pinned);
const orderedReading = [...pinnedReading, ...nonPinnedReading]; // sort applied to nonPinnedReading only, per the sort dropdown, before concatenation
```

Use `orderedReading` in place of `reading` when building the grid.

- [ ] **Step 3: Verify via Playwright**

Pin the manga entry, confirm it re-renders with the pinned star/border style and stays first in the list; pin 5 items total (add throwaway entries via `supabase-write.mjs` if needed) and confirm the 6th pin attempt shows the "Max 5 pinned" toast; clean up any throwaway entries afterward via a `DELETE` to the REST endpoint.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "add: pinning for reading, max-5 parity with Watching"
```

---

### Task 6: Ratings/notes for written media — generalize the shared rating/note plumbing

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: `openNoteModal`, `starsInnerHTML`, `noteButtonHTML` (existing, currently show-only), `ratings` table's `written_media_id` column from Task 1.
- Produces: `setRating`/`setNote` gain a `kind` parameter (`'show' | 'media'`, defaulting to `'show'` so every existing call site keeps working unchanged); the star-rating and note-button delegated listeners read a new `data-kind` attribute to route to the right target.

- [ ] **Step 1: Generalize `setRating`/`setNote` to accept a target kind**

Replace the existing functions (which Task 1 Step 4 already updated to pass `onConflict: 'show_id,user_id'` — this step extends that same fix to branch by kind rather than reintroducing it):

```js
async function setRating(id, value, kind = 'show') {
  if (!currentProfile) return;
  const targetCol = kind === 'media' ? 'written_media_id' : 'show_id';
  const { error } = await supabase.from('ratings').upsert({
    [targetCol]: id, user_id: currentProfile.id, rating: value, updated_at: new Date().toISOString(),
  }, { onConflict: kind === 'media' ? 'written_media_id,user_id' : 'show_id,user_id' });
  if (checkWriteError(error)) return;
  if (kind === 'media') invalidateWrittenMediaCache(); else invalidateShowsCache();
}

async function setNote(id, text, kind = 'show') {
  if (!currentProfile) return;
  const targetCol = kind === 'media' ? 'written_media_id' : 'show_id';
  const { error } = await supabase.from('ratings').upsert({
    [targetCol]: id, user_id: currentProfile.id, note: text || null, updated_at: new Date().toISOString(),
  }, { onConflict: kind === 'media' ? 'written_media_id,user_id' : 'show_id,user_id' });
  if (checkWriteError(error)) return;
  if (kind === 'media') invalidateWrittenMediaCache(); else invalidateShowsCache();
}
```

- [ ] **Step 2: Make the star-rating widget kind-aware**

Update `renderStars` to accept and stamp a `data-kind`:

```js
function renderStars(id, rating, kind = 'show') {
  return `<div class="star-rating" data-id="${id}" data-kind="${kind}">${starsInnerHTML(id, rating)}</div>`;
}
```

Update the star-hit delegated click listener to branch on `widget.dataset.kind`:

```js
document.body.addEventListener('click', async e => {
  const btn = e.target.closest('.star-hit');
  if (!btn) return;
  e.stopPropagation();
  const widget = btn.closest('.star-rating');
  const id = widget.dataset.id;
  const kind = widget.dataset.kind || 'show';
  const value = parseFloat(btn.dataset.star);
  const rows = kind === 'media' ? await fetchWrittenMedia(activeScope) : await fetchShows(activeScope);
  const current = rows.find(s => s.id === id)?.rating;
  await setRating(id, current === value ? null : value, kind);
  const updatedRows = kind === 'media' ? await fetchWrittenMedia(activeScope) : await fetchShows(activeScope);
  const r = updatedRows.find(s => s.id === id)?.rating;
  widget.innerHTML = starsInnerHTML(id, r);
  const label = widget.parentElement && widget.parentElement.querySelector('.rating-label');
  if (label) label.textContent = r ? `${r}` : '—';
});
```

This replaces the existing listener (same event type/selector, now kind-aware) rather than adding a second one.

- [ ] **Step 3: Make the note button and modal kind-aware**

Update `noteButtonHTML` to stamp `data-note-kind`:

```js
function noteButtonHTML(id, title, extraClass = '', note = '', kind = 'show') {
  const hasNote = !!note;
  return `<button class="note-btn ${extraClass}${hasNote ? ' has-note' : ''}" data-note-id="${id}" data-note-kind="${kind}" data-note-title="${title.replace(/"/g, '&quot;')}" data-note-text="${(note || '').replace(/&/g, '&amp;').replace(/"/g, '&quot;')}" aria-label="Note" title="Note">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path>
      <path d="M14 2v6h6"></path>
      <line x1="8" y1="13" x2="16" y2="13"></line>
      <line x1="8" y1="17" x2="13" y2="17"></line>
    </svg>
  </button>`;
}
```

Add a `noteModalKind` variable alongside the existing `noteModalShowId`/`noteModalOnSave`, set it in `openNoteModal`'s new `kind` parameter (defaulting to `'show'`), and read it in the save handler:

```js
let noteModalKind = 'show';

function openNoteModal(id, title, currentText, onSave, kind = 'show') {
  noteModalShowId = id;
  noteModalOnSave = onSave;
  noteModalKind = kind;
  document.getElementById('note-modal-title').textContent = `Note — ${title}`;
  document.getElementById('note-modal-text').value = currentText || '';
  document.getElementById('note-modal').classList.add('open');
  document.getElementById('note-modal-text').focus();
}
```

Update the save handler:

```js
document.getElementById('note-modal-save').addEventListener('click', async () => {
  if (!noteModalShowId) return;
  const text = document.getElementById('note-modal-text').value.trim();
  await setNote(noteModalShowId, text, noteModalKind);
  if (noteModalOnSave) noteModalOnSave(!!text);
  showToast(text ? 'Note saved' : 'Note cleared');
  closeNoteModal();
});
```

Update the note-btn delegated click listener to read and pass the kind:

```js
document.body.addEventListener('click', e => {
  const btn = e.target.closest('.note-btn');
  if (!btn) return;
  e.stopPropagation();
  const id = btn.dataset.noteId;
  const kind = btn.dataset.noteKind || 'show';
  const title = btn.dataset.noteTitle || id;
  const currentText = btn.dataset.noteText || '';
  openNoteModal(id, title, currentText, hasNote => {
    document.querySelectorAll(`.note-btn[data-note-id="${CSS.escape(id)}"]`).forEach(b => {
      b.classList.toggle('has-note', hasNote);
    });
  }, kind);
});
```

- [ ] **Step 4: Add the note button and star rating to Completed reading cards**

In `loadReading()`'s completed-card template (Task 2, Step 3), add `${noteButtonHTML(m.id, m.title, '', m.note, 'media')}` in the `.card-right` block (same position as the shows-side Completed cards), and add `${renderStars(m.id, m.rating, 'media')}` inside `.card-body`, below the author line.

- [ ] **Step 5: Verify via Playwright**

Mark an entry finished (from Task 4), go to its Completed card, rate it via the star widget, confirm the rating persists after a reload. Click the note icon, write a note, save, confirm the note icon shows the "has note" state. Switch to the Watching tab's Completed section and confirm shows-side ratings/notes still work unchanged (regression check on the generalization).

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "add: ratings/notes for written media, generalize shared rating/note plumbing"
```

---

### Task 7: To Read list — quick-add form, tag filter, start-reading transition

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: `renderWatchlistTagFilter`'s pattern (existing, shows-side — this task writes a parallel `renderToReadTagFilter` rather than sharing the function, since the shows-side one calls `loadShows()` on tag click and this one needs to call `loadReading()`), `canWriteScope`, `checkWriteError`.
- Produces: none — leaf feature.

- [ ] **Step 1: Wire the to-read quick-add form (from Task 2's skeleton HTML)**

```js
document.getElementById('to-read-add-btn').addEventListener('click', async () => {
  const title = document.getElementById('to-read-add-title').value.trim();
  const category = document.getElementById('to-read-add-category').value;
  const tagsRaw = document.getElementById('to-read-add-tags').value.trim();
  if (!title) return;
  const { error } = await supabase.from('written_media').insert({
    title, category, scope: activeScope, list_status: 'plan_to_read',
    tags: tagsRaw ? tagsRaw.split(',').map(t => t.trim()).filter(Boolean) : null,
  });
  if (checkWriteError(error)) return;
  document.getElementById('to-read-add-title').value = '';
  document.getElementById('to-read-add-tags').value = '';
  invalidateWrittenMediaCache();
  loadReading();
});
```

Toggle `#to-read-add`'s visibility in `loadReading()`, same pattern as the shows-side watchlist: `document.getElementById('to-read-add').style.display = canWriteScope(activeScope) ? '' : 'none';`

- [ ] **Step 2: Add click-to-start-reading on each to-read item**

Replace the static to-read list HTML from Task 2 with a version that has real click handling (mirrors `renderWatchlist`, but starts reading instead of copying a clipboard command, since there's no Claude-mediated "start" step needed here — the user owns the full lifecycle once an entry exists):

```js
let toReadCache = [];

function renderToRead(items) {
  const el = document.getElementById('to-read-list');
  el.innerHTML = '';
  items.forEach(item => {
    const row = document.createElement('div');
    row.className = 'watchlist-item';
    row.innerHTML = `<span class="watchlist-name">${item.title}</span><span class="watchlist-cta">→ start</span>`;
    row.addEventListener('click', async () => {
      if (!canWriteScope(activeScope)) return;
      const { error } = await supabase.from('written_media').update({ list_status: 'reading' }).eq('id', item.id);
      if (checkWriteError(error)) return;
      invalidateWrittenMediaCache();
      loadReading();
    });
    el.appendChild(row);
  });
}

document.getElementById('to-read-search').addEventListener('input', e => {
  const q = e.target.value.toLowerCase();
  renderToRead(toReadCache.filter(i => i.title.toLowerCase().includes(q)));
});
```

In `loadReading()`, replace the inline `to-read-list` innerHTML assignment from Task 2 with `toReadCache = toRead; renderToRead(toRead);`.

- [ ] **Step 3: Verify via Playwright**

Switch to Together scope, use the to-read add form to add a webnovel with a tag, confirm it appears in the To Read list. Click it, confirm it moves into Currently Reading with `current_chapter` defaulting to 0. Type into the to-read search box, confirm it filters the list.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "add: to-read quick-add form and start-reading transition"
```

---

## Self-Review Notes

- **Spec coverage:** schema/RLS (Task 1), Reading tab + read path (Task 2), Claude-mediated add flow (Task 3), chapter/page progress + mark-finished (Task 4), pinning (Task 5), ratings/notes via the generalized `kind` param (Task 6), to-read list + tags (Task 7) — every spec section has a task. Tier List/Ratings-tab/Stats integration is explicitly out of scope per the spec's non-goals, so it has no task here by design.
- **Type consistency:** `fetchWrittenMedia()` (Task 2) is the field-name contract every later task relies on (`currentChapter`, `totalChapters`, `currentPage`, `totalPages`, `listStatus`, `pinned`, `rating`, `note`) — Tasks 4–7 all read/write against those names, not the raw `snake_case` DB columns. `setRating`/`setNote`'s new `kind` parameter (Task 6) defaults to `'show'`, so the existing shows-side call sites (star widgets, note buttons on Watching/Tier List/Ratings) don't need any changes — only the Task 6 Step 4 additions pass `'media'` explicitly.
- **Known limitation carried from the spec:** the Reading tab doesn't have per-season-style "seasons" for manhwa/webnovels beyond the optional `total_volumes`/`current_volume` pair — matches the spec's "volumes stay null for books and most webnovels" note, not a gap introduced during implementation.
- **Cross-task correctness dependency found during planning:** Task 1's `ratings` primary-key change (composite → surrogate `id`) would silently turn every existing shows-side rating/note save into a duplicate-row insert instead of an update, since the old `setRating`/`setNote` upserts relied on PostgREST's default (primary-key-based) conflict target. Fixed by folding an explicit `onConflict` into Task 1 itself (Step 4) rather than leaving it until Task 6's generalization — Task 6 now extends that already-correct baseline instead of introducing the fix.
