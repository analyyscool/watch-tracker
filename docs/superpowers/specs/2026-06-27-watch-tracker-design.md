# Watch Progress Tracker — Design Spec
**Date:** 2026-06-27

## Overview

A standalone static web app for tracking TV shows and anime that are currently in progress (started but not finished). Progress updates are made by telling Claude in a session; Claude reads and writes the data file directly.

## Architecture

- **`index.html`** — single file, reads `data.json` on load, renders cards, no build step
- **`data.json`** — persisted list of in-progress shows, edited by Claude
- No server, no framework, no dependencies beyond Google Fonts
- Open `index.html` in a browser; refresh after Claude updates `data.json`

## Data Structure

`data.json` is an array of show objects:

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
  }
]
```

- `totalEpisodes` is the full series total — drives the progress percentage
- `currentEpisode` is the global episode count (not per-season)
- `posterUrl` is optional; left empty if not provided
- Only in-progress shows live in the file — finished shows are removed

## UI

- Dark theme, consistent with `anime-tierlist` aesthetic (same font stack: Bebas Neue, Syne, DM Mono)
- **Header:** "Currently Watching" title + "Add Show" button
- **Cards grid:** one card per show, containing:
  - Show title
  - "Season X · Episode Y" label
  - Visual progress bar (filled = % watched)
  - Percentage number (e.g. "39%")
- **Add Show form:** inline form triggered by the button — user types title, hits confirm
- Cards ordered by insertion order (no sorting/filtering)
- Reload button or browser refresh picks up latest `data.json`

## Claude Update Workflow

Claude handles all data mutations in a session:

| User says | Claude does |
|---|---|
| "I watched up to S2E8 of Attack on Titan" | Updates `currentEpisode` and `currentSeason` in `data.json` |
| "Add Vinland Saga, I'm on S1E5" | Web-searches metadata, writes new entry with researched `totalEpisodes`/`totalSeasons`, sets current position |
| "I finished Blue Lock" | Removes the entry from `data.json` |
| "Fix the total for Vinland Saga, it's 48 eps" | Corrects `totalEpisodes` in the entry |

When adding a show, Claude flags if metadata confidence is low so the user can override manually.

## Constraints

- No build tooling — plain HTML/CSS/JS
- No backend, no database
- No completed/plan-to-watch states — in-progress only
- Manual overrides via Claude conversation only
