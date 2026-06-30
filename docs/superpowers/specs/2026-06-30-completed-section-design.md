# Completed Section — Design Spec

**Date:** 2026-06-30  
**Status:** Approved

## Overview

Add a "completed" section at the bottom of the watch tracker page, below the watchlist. Shows where `currentEpisode === totalEpisodes` are automatically rendered there instead of the active grid. No data.json schema changes required.

## Detection

In `loadShows()`, after fetching `data.watching`, split into two arrays before rendering:

- `active` — shows where `currentEpisode < totalEpisodes`
- `completed` — shows where `currentEpisode === totalEpisodes`

The existing rendering logic for the active grid operates on `active` only. A new rendering block handles `completed`.

## Page Layout

```
[active cards grid]
── watchlist ──────────────────
[watchlist rows]
── completed ──────────────────
[completed cards]
```

The completed section is hidden entirely (both divider and card container) when there are no completed shows.

## Completed Card Appearance

Same `.card` component as active cards, with three differences:

1. **Progress bar** — full width (100%) but `background: var(--muted)` instead of the blue-purple gradient. Signals archived/done rather than active.
2. **Right-side label** (`card-pct`) — shows `done` in `var(--muted)` color instead of a percentage in accent blue.
3. **Stats row** — single stat: `X episodes`. No "X left" stat (it would always be 0).

## Header Count

The "N shows in progress" count in the header uses `active.length`, not `watching.length`. Completed shows are not counted.

## HTML Structure (new elements)

```html
<div class="section-divider" id="completed-divider"><span>completed</span></div>
<div id="completed"></div>
```

Added after `#watchlist`, hidden via `display: none` when empty.

## CSS

One new rule: `.card-pct.done { color: var(--muted); }` — or apply inline via style. No new layout classes needed; the muted progress bar color is set inline on the `.progress-fill` element.
