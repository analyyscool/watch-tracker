# Completed Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "completed" section at the bottom of the page that automatically shows shows where `currentEpisode === totalEpisodes`, keeping them out of the active grid.

**Architecture:** All changes are in `index.html` (single-file app — inline CSS, HTML, JS). The `loadShows()` function splits the `watching` array into `active` and `completed` before rendering. The completed section reuses the `.card` component with minor visual differences. No data.json changes.

**Tech Stack:** Vanilla HTML/CSS/JS, no build step, no test framework.

## Global Constraints

- No external dependencies — vanilla JS only
- No changes to `data.json` schema
- Completed detection: `show.currentEpisode >= show.totalEpisodes` (use `>=` not `===` to be safe against data entry overshoots)
- Follow existing CSS variable conventions (`var(--muted)`, `var(--border)`, etc.)

---

### Task 1: Add CSS and HTML for the completed section

**Files:**
- Modify: `index.html`

**Interfaces:**
- Produces: `#completed-divider` and `#completed` elements available for JS to populate in Task 2

- [ ] **Step 1: Add CSS for `#completed` layout and `.card-pct.done` style**

In `index.html`, find this existing rule:

```css
#watchlist { display: flex; flex-direction: column; }
```

Add immediately after it:

```css
#completed { display: flex; flex-direction: column; gap: 0.625rem; }
.card-pct.done { color: var(--muted); }
```

- [ ] **Step 2: Add completed section HTML**

In `index.html`, find this block:

```html
  <div class="section-divider"><span>watchlist</span></div>
  <div id="watchlist"></div>
</div>
```

Replace with:

```html
  <div class="section-divider"><span>watchlist</span></div>
  <div id="watchlist"></div>

  <div class="section-divider" id="completed-divider" style="display:none"><span>completed</span></div>
  <div id="completed"></div>
</div>
```

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat: add completed section HTML and CSS"
```

---

### Task 2: Update JS to split, count, and render completed shows

**Files:**
- Modify: `index.html` (the `loadShows()` script block)

**Interfaces:**
- Consumes: `#completed-divider` (div, initially `display:none`) and `#completed` (div) from Task 1
- Consumes: `data.watching` array from `data.json`

- [ ] **Step 1: Split watching into active and completed arrays**

In `loadShows()`, find this line:

```js
const watching = data.watching ?? data;
```

Add immediately after it:

```js
const active = watching.filter(s => s.currentEpisode < s.totalEpisodes);
const completed = watching.filter(s => s.currentEpisode >= s.totalEpisodes);
```

- [ ] **Step 2: Update header count to use active shows only**

Find:

```js
const n = watching.length;
countEl.innerHTML = n > 0
  ? `<strong>${n}</strong> show${n === 1 ? '' : 's'} in progress`
  : '';
```

Replace with:

```js
const n = active.length;
countEl.innerHTML = n > 0
  ? `<strong>${n}</strong> show${n === 1 ? '' : 's'} in progress`
  : '';
```

- [ ] **Step 3: Update active grid rendering to use `active` array**

Find:

```js
if (watching.length === 0) {
  empty.style.display = 'block';
} else {
  empty.style.display = 'none';
  watching.forEach(show => {
```

Replace with:

```js
if (active.length === 0) {
  empty.style.display = 'block';
} else {
  empty.style.display = 'none';
  active.forEach(show => {
```

(The rest of the `.forEach` callback is unchanged.)

- [ ] **Step 4: Add completed section rendering**

Find the closing of the `watching.forEach` block — it ends with:

```js
      });
    }

    watchlist.forEach(item => {
```

Insert a new block between the active grid block and the watchlist block:

```js
    const completedEl = document.getElementById('completed');
    const completedDivider = document.getElementById('completed-divider');
    completedEl.innerHTML = '';

    if (completed.length === 0) {
      completedDivider.style.display = 'none';
    } else {
      completedDivider.style.display = '';
      completed.forEach(show => {
        const epLabel = show.totalSeasons > 1
          ? `S${show.currentSeason} · E${show.seasonEpisode}`
          : `E${show.seasonEpisode}`;
        const card = document.createElement('div');
        card.className = 'card';
        card.innerHTML = `
          <div class="card-top">
            <div class="card-title">${show.title}</div>
            <div class="card-right">
              <span class="card-meta">${epLabel}</span>
              <span class="card-pct done">done</span>
            </div>
          </div>
          <div class="card-stats">
            <span class="stat"><strong>${show.totalEpisodes}</strong> episodes</span>
          </div>
          <div class="progress-bar">
            <div class="progress-fill" style="width:100%; background:var(--muted); box-shadow:none"></div>
          </div>
        `;
        completedEl.appendChild(card);
      });
    }

```

- [ ] **Step 5: Verify visually**

Open `index.html` in a browser (open file directly or use a local server). Confirm:
- Witch Hat Atelier does **not** appear in the active grid
- A "completed" section divider appears at the bottom of the page
- Witch Hat Atelier appears there with a full muted-grey progress bar and "done" label (not a percentage)
- The header count reads "12 shows in progress" (not 13)
- Reload button still works

- [ ] **Step 6: Commit and push**

```bash
git add index.html
git commit -m "feat: completed section — auto-detect finished shows"
git push
```
