# Bigger Cards + Pin/Prioritize — Design Spec

**Date:** 2026-07-01
**Status:** Approved

## Overview

Two changes to the active shows grid:

1. Increase card height (~40-50% taller) so posters and content have more room.
2. Add a per-card pin button letting the user prioritize up to 3 active shows, which always sort to the top of the list.

No `data.json` schema changes. Pin state lives entirely in the browser (`localStorage`), since the site is static and `data.json` is only ever edited by Claude on request — a click interaction can't reasonably round-trip through that.

## Card Height

Increase vertical padding in `.card-top` (currently `1.15rem 1.25rem 0.5rem`) and `.card-stats` (currently `0.35rem 1.25rem 1rem`) to grow total card height by roughly 40-50%.

The poster (`.card-poster`) stretches to fill the card's height already (flex `align-items: stretch` default). Its width increases from `56px` to `84px` to preserve the ~2:3 portrait aspect ratio of the source poster images as the card grows taller — otherwise a taller, still-56px-wide poster would look stretched/cropped oddly.

Applies to both active and completed cards, since they share the same `.card` markup — keeps the two sections visually consistent.

## Pin / Prioritize

### Storage

`localStorage` key `pinnedShows`: a JSON array of show `id` strings, in pin order. Index 0 is highest priority (rendered first). Max length 3.

```js
function getPinned() {
  return JSON.parse(localStorage.getItem('pinnedShows') || '[]');
}
function setPinned(ids) {
  localStorage.setItem('pinnedShows', JSON.stringify(ids));
}
```

### Trigger

A pin-icon button is added inside `.card-right`, before the `%` label, on **active cards only** (completed cards don't get one — prioritizing only applies to shows still in progress).

- Unpinned: outline pin icon, `var(--muted)` color.
- Pinned: filled pin icon, `var(--accent)` color.

Clicking the button:
- If the show is not pinned and `pinnedShows.length < 3`: append its id to the array, re-render.
- If the show is not pinned and `pinnedShows.length === 3`: call `showToast('Max 3 pinned — unpin one first')`, no state change.
- If the show is already pinned: remove its id from the array, re-render.

The button uses `event.stopPropagation()` / is a plain `<button>` so it doesn't trigger any other card interaction (none currently exist, but keeps it isolated).

### Sort Order

In `loadShows()`, after computing `active` (currently sorted by percent-remaining ascending), reorder so that:

1. Shows whose id is in `pinnedShows` come first, in the order they appear in `pinnedShows` (index 0 first).
2. All other active shows follow, in the existing percent-remaining sort.

```js
const pinned = getPinned();
active.sort((a, b) => {
  const pa = pinned.indexOf(a.id), pb = pinned.indexOf(b.id);
  if (pa !== -1 || pb !== -1) {
    if (pa === -1) return 1;
    if (pb === -1) return -1;
    return pa - pb;
  }
  return (1 - a.currentEpisode / a.totalEpisodes) - (1 - b.currentEpisode / b.totalEpisodes);
});
```

### Pinned Card Visual

Pinned cards get a 3px accent-colored left border (`border-left: 3px solid var(--accent)`), in addition to the filled pin icon. No numbered badge — pin order is implied by list position, not labeled.

### Persistence Notes

- Pins are per-browser/device; they don't sync and aren't part of `data.json` or git.
- If a pinned show's id is later removed from `data.json` (e.g. a show is deleted), it simply disappears from the pinned array's effective set on next render — no cleanup step needed since sorting only checks `indexOf` against currently-loaded shows.
