# Watch Progress Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a static single-page app that displays in-progress TV shows/anime with episode position and a visual progress bar, backed by a `data.json` file that Claude edits directly.

**Architecture:** Two files — `index.html` (all HTML/CSS/JS) and `data.json` (show data). The page fetches `data.json` on load and renders a card grid. Claude reads and writes `data.json` directly to update progress or add/remove shows.

**Tech Stack:** Plain HTML5, CSS custom properties, vanilla JS (fetch API). Google Fonts (Bebas Neue, Syne, DM Mono). No build tools.

## Global Constraints

- No build tooling — plain HTML/CSS/JS only
- No external JS libraries or frameworks
- Font stack: Bebas Neue, Syne, DM Mono (same Google Fonts import as anime-tierlist)
- Dark theme using same CSS variables as anime-tierlist (`--bg: #0b0b10`, etc.)
- `data.json` must be served over HTTP (not `file://`) for `fetch()` to work — use any local server (e.g. VS Code Live Server, `python -m http.server`)

---

### Task 1: Scaffold data.json with sample shows

**Files:**
- Create: `data.json`

**Interfaces:**
- Produces: JSON array read by `index.html` JS in Task 3

- [ ] **Step 1: Create data.json**

```json
[
  {
    "id": "attack-on-titan",
    "title": "Attack on Titan",
    "totalEpisodes": 87,
    "currentEpisode": 34,
    "currentSeason": 2,
    "totalSeasons": 4,
    "posterUrl": ""
  },
  {
    "id": "blue-lock",
    "title": "Blue Lock",
    "totalEpisodes": 24,
    "currentEpisode": 10,
    "currentSeason": 1,
    "totalSeasons": 1,
    "posterUrl": ""
  },
  {
    "id": "severance",
    "title": "Severance",
    "totalEpisodes": 19,
    "currentEpisode": 7,
    "currentSeason": 2,
    "totalSeasons": 2,
    "posterUrl": ""
  }
]
```

- [ ] **Step 2: Commit**

```bash
git add data.json
git commit -m "feat: add data.json with sample shows"
```

---

### Task 2: HTML skeleton and complete CSS

**Files:**
- Create: `index.html`

**Interfaces:**
- Consumes: `data.json` (fetched in Task 3)
- Produces: `<div id="grid">` container that Task 3 JS populates; `.card` CSS classes ready for dynamically inserted cards

- [ ] **Step 1: Create index.html with full HTML structure and CSS**

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Currently Watching</title>
<link href="https://fonts.googleapis.com/css2?family=Bebas+Neue&family=Syne:wght@700;800&family=DM+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :root {
    --bg:       #0b0b10;
    --surface:  #13131a;
    --surface2: #1a1a24;
    --border:   #22222e;
    --border2:  #2e2e3e;
    --text:     #e6e6f0;
    --muted:    #52526a;
    --accent:   #0a84ff;
    --accent2:  #bf5af2;
  }

  html { scroll-behavior: smooth; }

  body {
    background-color: var(--bg);
    background-image:
      radial-gradient(ellipse 80% 50% at 50% -10%, rgba(10,132,255,0.06) 0%, transparent 60%),
      url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='300' height='300'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.75' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='300' height='300' filter='url(%23n)' opacity='0.035'/%3E%3C/svg%3E");
    color: var(--text);
    font-family: 'DM Mono', monospace;
    min-height: 100vh;
    padding: 2.5rem 1rem 5rem;
  }

  .container { max-width: 1000px; margin: 0 auto; }

  /* ── Header ── */
  header {
    text-align: center;
    margin-bottom: 2.5rem;
  }

  .header-eyebrow {
    font-size: 0.65rem;
    letter-spacing: 0.3em;
    text-transform: uppercase;
    color: var(--muted);
    margin-bottom: 0.6rem;
  }

  header h1 {
    font-family: 'Bebas Neue', sans-serif;
    font-size: clamp(3rem, 8vw, 6rem);
    letter-spacing: 0.08em;
    line-height: 1;
    background: linear-gradient(160deg, #fff 20%, #8888aa 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
  }

  .header-actions {
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 0.75rem;
    margin-top: 1.4rem;
  }

  .btn {
    font-family: 'DM Mono', monospace;
    font-size: 0.7rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    border: 1px solid var(--border2);
    background: var(--surface);
    color: var(--muted);
    padding: 0.45rem 1rem;
    border-radius: 4px;
    cursor: pointer;
    transition: border-color 0.15s, color 0.15s;
  }

  .btn:hover { border-color: var(--accent); color: var(--text); }

  .btn-primary {
    border-color: var(--accent);
    color: var(--accent);
  }

  .btn-primary:hover {
    background: rgba(10,132,255,0.1);
    color: var(--text);
  }

  /* ── Grid ── */
  #grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: 1.25rem;
  }

  /* ── Card ── */
  .card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 1.25rem 1.25rem 1rem;
    transition: border-color 0.15s;
  }

  .card:hover { border-color: var(--border2); }

  .card-title {
    font-family: 'Syne', sans-serif;
    font-weight: 700;
    font-size: 1rem;
    color: var(--text);
    margin-bottom: 0.35rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .card-meta {
    font-size: 0.68rem;
    letter-spacing: 0.08em;
    color: var(--muted);
    margin-bottom: 1rem;
    text-transform: uppercase;
  }

  /* ── Progress bar ── */
  .progress-wrap {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }

  .progress-bar {
    flex: 1;
    height: 4px;
    background: var(--surface2);
    border-radius: 2px;
    overflow: hidden;
  }

  .progress-fill {
    height: 100%;
    border-radius: 2px;
    background: linear-gradient(90deg, var(--accent), var(--accent2));
    transition: width 0.3s ease;
  }

  .progress-label {
    font-size: 0.65rem;
    letter-spacing: 0.05em;
    color: var(--muted);
    min-width: 2.8rem;
    text-align: right;
  }

  /* ── Empty state ── */
  #empty {
    display: none;
    text-align: center;
    padding: 4rem 1rem;
    color: var(--muted);
  }

  #empty p {
    font-size: 0.8rem;
    letter-spacing: 0.1em;
    text-transform: uppercase;
  }

  /* ── Modal ── */
  .modal-backdrop {
    display: none;
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.7);
    z-index: 100;
    align-items: center;
    justify-content: center;
  }

  .modal-backdrop.open { display: flex; }

  .modal {
    background: var(--surface);
    border: 1px solid var(--border2);
    border-radius: 10px;
    padding: 1.75rem;
    width: min(400px, 90vw);
  }

  .modal h2 {
    font-family: 'Syne', sans-serif;
    font-size: 1rem;
    font-weight: 700;
    margin-bottom: 1.25rem;
    color: var(--text);
  }

  .modal p {
    font-size: 0.75rem;
    color: var(--muted);
    line-height: 1.6;
    margin-bottom: 1.25rem;
  }

  .modal-close {
    width: 100%;
    text-align: center;
  }
</style>
</head>
<body>
<div class="container">
  <header>
    <p class="header-eyebrow">in progress</p>
    <h1>Currently Watching</h1>
    <div class="header-actions">
      <button class="btn btn-primary" id="btn-add">+ Add Show</button>
      <button class="btn" id="btn-reload">↺ Reload</button>
    </div>
  </header>

  <div id="grid"></div>
  <div id="empty"><p>No shows in progress — tell Claude to add one.</p></div>
</div>

<!-- Add Show modal (informational only) -->
<div class="modal-backdrop" id="modal">
  <div class="modal">
    <h2>Add a Show</h2>
    <p>
      Tell Claude what you want to add in this session —<br>
      e.g. <em>"Add Vinland Saga, I'm on S1E5"</em><br><br>
      Claude will look up the metadata and update <code>data.json</code> for you.
      Then hit <strong>Reload</strong> to see it appear.
    </p>
    <div class="modal-close">
      <button class="btn" id="btn-close">Got it</button>
    </div>
  </div>
</div>

<script>
  // Render
  async function loadShows() {
    const res = await fetch('data.json?t=' + Date.now());
    const shows = await res.json();
    const grid = document.getElementById('grid');
    const empty = document.getElementById('empty');

    grid.innerHTML = '';

    if (shows.length === 0) {
      empty.style.display = 'block';
      return;
    }

    empty.style.display = 'none';

    shows.forEach(show => {
      const pct = Math.round((show.currentEpisode / show.totalEpisodes) * 100);
      const card = document.createElement('div');
      card.className = 'card';
      card.innerHTML = `
        <div class="card-title">${show.title}</div>
        <div class="card-meta">Season ${show.currentSeason} &middot; Episode ${show.currentEpisode}</div>
        <div class="progress-wrap">
          <div class="progress-bar">
            <div class="progress-fill" style="width:${pct}%"></div>
          </div>
          <span class="progress-label">${pct}%</span>
        </div>
      `;
      grid.appendChild(card);
    });
  }

  // Controls
  document.getElementById('btn-reload').addEventListener('click', loadShows);

  document.getElementById('btn-add').addEventListener('click', () => {
    document.getElementById('modal').classList.add('open');
  });

  document.getElementById('btn-close').addEventListener('click', () => {
    document.getElementById('modal').classList.remove('open');
  });

  document.getElementById('modal').addEventListener('click', e => {
    if (e.target === e.currentTarget) e.currentTarget.classList.remove('open');
  });

  loadShows();
</script>
</body>
</html>
```

- [ ] **Step 2: Verify in browser**

Start a local server in the project directory:
```bash
python -m http.server 8080
```
Open `http://localhost:8080` — you should see:
- Dark background with noise texture and blue glow
- "Currently Watching" header with two buttons
- Three cards (Attack on Titan, Blue Lock, Severance), each with title, season/episode label, and progress bar filled to the correct percentage
- Hovering a card subtly brightens its border
- Clicking "↺ Reload" re-fetches and re-renders (no visible change since data hasn't changed)
- Clicking "+ Add Show" opens the modal with instructions; clicking "Got it" or the backdrop closes it

- [ ] **Step 3: Verify empty state**

Temporarily replace `data.json` contents with `[]`, refresh the browser. You should see "No shows in progress — tell Claude to add one." Restore the original `data.json`.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat: build watch tracker UI with card grid and progress bars"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Covered |
|---|---|
| In-progress shows only | ✅ data.json holds only active shows; finished shows removed by Claude |
| Current episode + season per card | ✅ `card-meta` renders `Season X · Episode Y` |
| Visual progress bar | ✅ `.progress-fill` width driven by `currentEpisode / totalEpisodes * 100` |
| Percentage display | ✅ `.progress-label` shows rounded pct |
| Add Show UI | ✅ modal explains the Claude workflow |
| Reload button | ✅ re-fetches `data.json` with cache-busting param |
| Dark theme matching anime-tierlist | ✅ same CSS variables, same fonts |
| Claude edits data.json | ✅ plain JSON, Claude reads/writes directly |
| posterUrl field | ✅ in data structure, not displayed (unused field — YAGNI) |

**Placeholder scan:** None found — all steps contain exact code.

**Type consistency:** `show.currentEpisode`, `show.totalEpisodes`, `show.currentSeason` used consistently in data.json and JS rendering.

**Edge cases covered:** Empty array shows empty state; `pct` uses `Math.round` to avoid decimal percentages.
