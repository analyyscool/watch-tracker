# Ratings, Notes, Movies Grid, Stats, Sort/Filter — Design Spec
**Date:** 2026-08-12

## Overview

Four additions to the watch tracker, designed and built together:

1. Half-star (0–5, 0.5 steps) ratings for movies, Letterboxd-style
2. Freeform notes on any watched show
3. A new Movies tab (poster grid with ratings/notes, separate from the existing Tier List → Movies sub-tab)
4. A new Stats tab (aggregate counts/hours/genre breakdown)
5. Sort/filter controls on the Watching and Completed sections

(Numbered as five items above but treated as one build since they share data model and UI patterns.)

## Data Model

Add to `data.json` entries:

- `rating` (number, 0–5 in 0.5 steps) — only ever set on `watched` entries with `category: "movie"`.
- `note` (string) — freeform, may be set on any `watched` entry regardless of category.
- `runtimeMinutes` (number) — per-episode runtime for `category: "western"` entries; total film length for `category: "movie"` entries. Not stored for `category: "anime"` — stats math assumes a flat 20 min/episode for anime instead.

All three fields are optional and additive; entries without them behave as before. Existing western TV shows (Mr. Robot, Loki, Avatar: The Last Airbender) and all 13 movie entries get `runtimeMinutes` backfilled via TMDB lookup as part of this build, matching the existing episode-count research pattern in `CLAUDE.md`.

## Interaction Model: browser-local + export-to-Claude

Ratings and notes are edited directly in the browser (star clicks, note textareas) and saved instantly to `localStorage` (`watchRatings: { [id]: number }`, `watchNotes: { [id]: string }`) — same pattern as tier placements and pinned shows. Nothing here touches `data.json` automatically.

A **"Copy Ratings & Notes"** button (in the Movies tab) exports all rated/noted shows as a paste-able text block:

```
RATINGS & NOTES EXPORT

your-name: 4.5 stars
  "Gorgeous, but the pacing drags in act two"
suzume: 5 stars
avatar-last-airbender: (no rating)
  "Rewatch of the whole series, still holds up"
```

Only shows with a rating and/or note appear in the export. The user pastes this into a Claude session; `CLAUDE.md` gets a new rule describing how to parse it and merge `rating`/`note` into the matching `watched` entries in `data.json`, then commit. Entries not mentioned in the block are left untouched.

## Movies Tab

New top-level tab (`Watching | Tier List | Movies | Stats`). Poster grid of every `watched` entry with `category: "movie"`:

- Poster, title
- 10-segment star widget under the poster (click anywhere across a star = half or full, mirroring Letterboxd's click-left-half/right-half interaction)
- Collapsible note textarea (click a "+ note" affordance to expand; saved on blur)
- Sort control: rating (desc) / title (A–Z) / date added — persisted in `localStorage`

This is separate from Tier List → Movies, which keeps its existing relative S–F ranking behavior unchanged.

## Completed Section (existing, inside Watching tab)

Every card in the existing "completed" grid (all categories, not just movies) gets the same collapsible note affordance as the Movies tab, reusing the same component. No star rating here — ratings stay movie-only per the original request.

## Sort/Filter — Watching & Completed sections

A control row above each grid:

- **Watching**: sort by % complete / last updated / alphabetical, plus genre filter and studio filter dropdowns (options populated from what's actually present in the section)
- **Completed**: sort by last updated / alphabetical (no % complete — always 100%), plus the same genre/studio filters

Selected sort and filter values persist per-section in `localStorage` so they survive a reload.

## Stats Tab

New top-level tab. Read-only, computed entirely from `data.json` on load — no new stored state:

- Show counts: watching / completed / watchlist
- Total episodes watched (sum of `currentEpisode` across watching + `totalEpisodes` across completed-only-in-`watched` movies count as 1 "watch")
- Total hours watched — anime episodes at a flat 20 min, western/movie using `runtimeMinutes` (falls back to 20 min if a western entry is missing it, since not every existing show will have real data on day one)
- Genre breakdown (count per genre, across watching + watched)
- Studio breakdown (top studios by count)
- Category split (anime / western / movie counts)

Explicitly **not** building a "watched over time" trend — `lastUpdated` reflects last-touch date, not a real watch log, so a time-series chart built on it would look precise but be misleading. Flagging this instead of building it.

## Out of scope

- No rating/notes editing from the Tier List view.
- No automatic sync of ratings/notes to `data.json` — export-and-paste only, consistent with how the rest of this app already works.
- No per-episode runtime tracking beyond the single `runtimeMinutes` value per show.
