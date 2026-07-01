# Bigger Cards + Pin/Prioritize Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the currently-watching cards taller and let the user pin up to 3 active shows so they always sort to the top.

**Architecture:** Single-file static site (`index.html`) — all HTML/CSS/JS inline, no build step, no backend. Pin state is stored client-side in `localStorage`. Changes are CSS-only for the sizing task, and additive JS (new helper functions + template changes) for the pinning task. No `data.json` schema changes.

**Tech Stack:** Vanilla HTML/CSS/JS, no framework, no test runner. "Tests" in this project mean loading the page in a browser (via a local static server) and visually/programmatically verifying behavior with Playwright.

## Global Constraints

- No `data.json` schema changes (per spec).
- Pin state lives only in `localStorage` key `pinnedShows` (JSON array of show id strings, index 0 = highest priority, max length 3).
- Pin button only appears on active (in-progress) cards, not completed cards.
- Max 3 pins; a 4th attempt shows `showToast('Max 3 pinned — unpin one first')` and does not change state.
- Card height increases ~40-50%; poster width scales from 56px to 84px to preserve aspect ratio.
- Pinned cards get a 3px `var(--accent)` left border; no numbered badge.

---

## Test Setup (used by every task below)

All manual verification in this plan uses a local static server + Playwright. From the repo root:

```bash
python -m http.server 8791
```

Then use the Playwright MCP tools (`browser_navigate` to `http://localhost:8791/index.html`, `browser_take_screenshot`, `browser_evaluate` for reading `localStorage` or clicking elements) to verify each task. Stop the server (kill the process) when done with each task's verification.

---

### Task 1: Card height & poster resize (CSS only)

**Files:**
- Modify: `index.html` (`.card-poster`, `.card-top`, `.card-stats` rules inside the `<style>` block)

**Interfaces:**
- Consumes: nothing new
- Produces: no new JS symbols; purely visual change other tasks don't depend on

- [ ] **Step 1: Edit `.card-poster` width**

Find this block:

```css
  .card-poster {
    width: 56px;
    height: auto;
    object-fit: cover;
    flex-shrink: 0;
    background: var(--surface2);
  }
```

Replace with:

```css
  .card-poster {
    width: 84px;
    height: auto;
    object-fit: cover;
    flex-shrink: 0;
    background: var(--surface2);
  }
```

- [ ] **Step 2: Edit `.card-top` padding**

Find:

```css
  .card-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1.15rem 1.25rem 0.5rem;
    gap: 1rem;
  }
```

Replace with:

```css
  .card-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 2rem 1.25rem 1rem;
    gap: 1rem;
  }
```

- [ ] **Step 3: Edit `.card-stats` padding**

Find:

```css
  .card-stats {
    display: flex;
    gap: 1.5rem;
    padding: 0.35rem 1.25rem 1rem;
  }
```

Replace with:

```css
  .card-stats {
    display: flex;
    gap: 1.5rem;
    padding: 0.75rem 1.25rem 1.75rem;
  }
```

- [ ] **Step 4: Verify in browser**

Run:

```bash
python -m http.server 8791
```

Navigate to `http://localhost:8791/index.html` with Playwright and take a full-page screenshot.

Expected: active and completed cards are visibly taller than before (roughly 40-50% more vertical space), posters are wider (84px) and still fill the card's height without distortion, no layout overlap or clipping.

Stop the server (kill the process) after verifying.

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "style: increase card height and poster size"
```

---

### Task 2: Pin button, storage, and toggle interaction

**Files:**
- Modify: `index.html` (`<style>` block — new `.pin-btn` rules; `<script>` block — new storage helpers, new `togglePin` function, active-card template change)

**Interfaces:**
- Consumes: `showToast(msg)` (existing, defined at top of `<script>` block)
- Produces: `getPinned(): string[]`, `setPinned(ids: string[]): void`, `togglePin(id: string): void` — Task 3 reads `getPinned()` inside `loadShows()`'s sort and to decide the `pinned` CSS class on each card.

- [ ] **Step 1: Add `.pin-btn` CSS**

Find the `.card-pct` rule:

```css
  .card-pct {
    font-size: 0.62rem;
    letter-spacing: 0.04em;
    color: var(--accent);
    min-width: 2.2rem;
    text-align: right;
    font-variant-numeric: tabular-nums;
  }
```

Add immediately after it:

```css

  .pin-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    background: none;
    border: none;
    padding: 0;
    cursor: pointer;
    color: var(--muted);
    transition: color 0.15s;
  }

  .pin-btn:hover { color: var(--accent); }
  .pin-btn.pinned { color: var(--accent); }
```

- [ ] **Step 2: Add storage helpers and `togglePin`**

Find the `showToast` function in the `<script>` block:

```js
  // Toast
  function showToast(msg) {
    const t = document.createElement('div');
    t.className = 'toast';
    t.textContent = msg;
    document.body.appendChild(t);
    requestAnimationFrame(() => requestAnimationFrame(() => t.classList.add('show')));
    setTimeout(() => {
      t.classList.remove('show');
      setTimeout(() => t.remove(), 300);
    }, 2500);
  }
```

Add immediately after it:

```js

  // Pinning
  function getPinned() {
    return JSON.parse(localStorage.getItem('pinnedShows') || '[]');
  }

  function setPinned(ids) {
    localStorage.setItem('pinnedShows', JSON.stringify(ids));
  }

  function togglePin(id) {
    const pinned = getPinned();
    const idx = pinned.indexOf(id);
    if (idx !== -1) {
      pinned.splice(idx, 1);
      setPinned(pinned);
    } else if (pinned.length >= 3) {
      showToast('Max 3 pinned — unpin one first');
      return;
    } else {
      pinned.push(id);
      setPinned(pinned);
    }
    loadShows();
  }
```

- [ ] **Step 3: Add the pin button to the active-card template**

Inside `loadShows()`, find the active-card `card.innerHTML` block:

```js
        card.innerHTML = `
          ${show.posterUrl ? `<img class="card-poster" src="${show.posterUrl}" alt="" onerror="this.remove()">` : ''}
          <div class="card-body">
            <div class="card-top">
              <div class="card-title">${show.title}</div>
              <div class="card-right">
                <span class="card-meta">${epLabel}</span>
                <span class="card-pct">${pct}%</span>
              </div>
            </div>
```

Replace with (adds the pin button before `card-meta`, reading `pinned` — introduced in Step 4 below — to decide the `pinned` class and icon fill):

```js
        const isPinned = pinned.includes(show.id);
        card.innerHTML = `
          ${show.posterUrl ? `<img class="card-poster" src="${show.posterUrl}" alt="" onerror="this.remove()">` : ''}
          <div class="card-body">
            <div class="card-top">
              <div class="card-title">${show.title}</div>
              <div class="card-right">
                <button class="pin-btn${isPinned ? ' pinned' : ''}" onclick="togglePin('${show.id}')" aria-label="${isPinned ? 'Unpin' : 'Pin'} ${show.title}">
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="${isPinned ? 'currentColor' : 'none'}" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path>
                    <circle cx="12" cy="10" r="3"></circle>
                  </svg>
                </button>
                <span class="card-meta">${epLabel}</span>
                <span class="card-pct">${pct}%</span>
              </div>
            </div>
```

- [ ] **Step 4: Read `pinned` once per render**

Find, near the top of `loadShows()`:

```js
    const watching = data.watching ?? data;
    const active = watching
      .filter(s => s.currentEpisode < s.totalEpisodes)
      .sort((a, b) => (1 - a.currentEpisode / a.totalEpisodes) - (1 - b.currentEpisode / b.totalEpisodes));
```

Replace with:

```js
    const watching = data.watching ?? data;
    const pinned = getPinned();
    const active = watching
      .filter(s => s.currentEpisode < s.totalEpisodes)
      .sort((a, b) => (1 - a.currentEpisode / a.totalEpisodes) - (1 - b.currentEpisode / b.totalEpisodes));
```

(The sort itself is updated in Task 3 — this step only makes `pinned` available to the template from Task 2 Step 3.)

- [ ] **Step 5: Verify in browser**

Run:

```bash
python -m http.server 8791
```

With Playwright:
1. Navigate to `http://localhost:8791/index.html`.
2. Click the pin icon on the first active card. Screenshot or `browser_evaluate` to confirm the button now has class `pinned` and `localStorage.getItem('pinnedShows')` contains that show's id.
3. Click it again — confirm it's removed from `localStorage` and the class is gone.
4. Pin 3 different shows, then attempt to pin a 4th. Confirm a toast reading "Max 3 pinned — unpin one first" appears (screenshot) and `localStorage.getItem('pinnedShows')` still has only 3 ids.
5. Unpin one of the 3, then pin the 4th — confirm it succeeds.

Expected: all five checks pass as described above.

Stop the server (kill the process) after verifying.

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat: add pin button with localStorage-backed toggle (max 3)"
```

---

### Task 3: Pin-priority sort + pinned card border

**Files:**
- Modify: `index.html` (`<style>` block — new `.card.pinned` rule; `<script>` block — sort comparator and card class in both active-card and completed-card render loops)

**Interfaces:**
- Consumes: `getPinned()`, `pinned` array (from Task 2)
- Produces: nothing new for later tasks (this is the last task in the plan)

- [ ] **Step 1: Add `.card.pinned` border CSS**

Find:

```css
  .card:hover {
    border-color: var(--border2);
    box-shadow: var(--card-shadow-hv);
  }
```

Add immediately after it:

```css

  .card.pinned { border-left: 3px solid var(--accent); }
```

- [ ] **Step 2: Update the active-show sort to prioritize pinned ids**

Find (this is the block Task 2 Step 4 already touched to add `const pinned = getPinned();`):

```js
    const watching = data.watching ?? data;
    const pinned = getPinned();
    const active = watching
      .filter(s => s.currentEpisode < s.totalEpisodes)
      .sort((a, b) => (1 - a.currentEpisode / a.totalEpisodes) - (1 - b.currentEpisode / b.totalEpisodes));
```

Replace with:

```js
    const watching = data.watching ?? data;
    const pinned = getPinned();
    const active = watching
      .filter(s => s.currentEpisode < s.totalEpisodes)
      .sort((a, b) => {
        const pa = pinned.indexOf(a.id), pb = pinned.indexOf(b.id);
        if (pa !== -1 || pb !== -1) {
          if (pa === -1) return 1;
          if (pb === -1) return -1;
          return pa - pb;
        }
        return (1 - a.currentEpisode / a.totalEpisodes) - (1 - b.currentEpisode / b.totalEpisodes);
      });
```

- [ ] **Step 3: Add the `pinned` class to the active card element**

Find, in the active-card render loop (added by Task 2 Step 3):

```js
        const isPinned = pinned.includes(show.id);
        card.innerHTML = `
```

The line immediately above it is:

```js
        const card = document.createElement('div');
        card.className = 'card';
```

Replace those two lines with:

```js
        const card = document.createElement('div');
        const isPinned = pinned.includes(show.id);
        card.className = 'card' + (isPinned ? ' pinned' : '');
```

And remove the now-duplicate `const isPinned = pinned.includes(show.id);` line that follows (the one directly before `card.innerHTML = \`` from Task 2 Step 3), since it's now declared above.

- [ ] **Step 4: Verify in browser**

Run:

```bash
python -m http.server 8791
```

With Playwright:
1. Navigate to `http://localhost:8791/index.html`.
2. Pin two shows that are not currently at the top of the percent-remaining sort (e.g. one with a low percent-remaining and one with a high one).
3. Reload (click the "Reload" button or re-navigate).
4. Screenshot: confirm both pinned shows appear at the very top of the active list, in the order they were pinned, each with a visible accent-colored left border. Confirm the remaining shows below are still sorted by percent-remaining as before.

Expected: pinned shows always render first in pin order; unpinned shows keep the existing percent-remaining sort below them; pinned cards show the accent left border.

Stop the server (kill the process) after verifying.

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "feat: sort pinned shows to top and add pinned card border"
```
