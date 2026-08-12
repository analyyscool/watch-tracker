# Tier List Categories — Design Spec
**Date:** 2026-08-12

## Overview

The Tier List / Ranked List view currently pools every finished show (anime and western TV, plus movies) into one shared S–F tier list and one shared ranked list. This splits that single pool into three independent lists — Anime, Western, Movies — each with its own tiers/ranking, while keeping everything else about the tier-list mechanics (drag/tap placement, ranked-list drag/arrows, export) unchanged.

## Data Model

Add a `category` field to every entry in `data.json`'s `watched` array, and to `watching` entries (so shows that finish later already carry a category):

```json
{ "id": "your-name", "title": "Your Name.", "posterUrl": "...", "category": "movie" }
```

- `"anime"` — anime/anime-adjacent TV series
- `"western"` — non-anime TV series (e.g. Mr. Robot, Loki, Avatar: The Last Airbender)
- `"movie"` — any movie regardless of origin (anime films like *Your Name.* and *Suzume* count as `movie`, not `anime`)

**Backfill:** all existing `watched` entries get classified in this pass. A few ambiguous titles (live-action vs. anime adaptation, etc.) are flagged for the user to confirm rather than guessed silently.

**Going forward:** the "marking a show finished" and "adding a new show" rules in `CLAUDE.md` are updated so Claude sets `category` whenever a show is added to `watched`.

## UI

Inside the existing `Tier List` tab, add a sub-tab row above the mode toggle: `Anime | Western | Movies`. Default: `Anime`.

- Switching sub-tabs filters `getWatchedShows()` by `category` and re-renders both the tier grid and ranked list for that category alone.
- Each sub-tab keeps independent placement state — no show appears in more than one category's list, and moving between sub-tabs never mixes pools.
- The pool/untiered zone, tier zones, and ranked-list zone are shared DOM elements that get re-rendered per active sub-tab (not duplicated three times in the DOM).

## State (localStorage)

Current keys (`watchTierState`, `watchRankOrder`) become per-category:

- `watchTierState:anime`, `watchTierState:western`, `watchTierState:movie`
- `watchRankOrder:anime`, `watchRankOrder:western`, `watchRankOrder:movie`

**One-time migration on load:** if the legacy `watchTierState` / `watchRankOrder` keys exist and the new `:anime` keys don't, copy the legacy state into the `:anime` keys, then leave the legacy keys in place (harmless, unread going forward). Western and Movies start from an empty pool.

## Export

`Copy Export` exports whichever sub-tab is currently active, with the category name in the header line (e.g. `ANIME TIER LIST`, `MOVIES RANKED LIST`) instead of the generic `TIER LIST` / `RANKED LIST`.

## Out of scope

- No changes to the `watching` tab, watchlist, or completion logic.
- No new category values beyond the three above (e.g. no separate "OVA" or "special" bucket).
- No UI for editing a show's category after the fact — corrections happen via `data.json` through Claude, same as everything else in this app.
