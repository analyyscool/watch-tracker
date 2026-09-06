# Spin the Wheel — movie decider

**Date:** 2026-09-06
**Status:** approved, ready for implementation
**Scope:** single feature, `index.html` only. No Supabase schema changes.

## Purpose

A "Spin the Wheel" sub-tab under TV / Movies that picks a movie to watch,
styled after spinthewheel.com. Replaces the first-cut single-set version
(commit not yet made) with a multi-wheel model, a 3-reel slot machine, a
50% no-match mechanic, and synthesized sound.

## Placement

- Sub-tab `data-tab="spinwheel"` in `#tvmovies-subtabs`, between
  "Movie Watchlist" and "Tier List".
- `<div id="view-spinwheel">`, wired into `activateSubtab()`,
  `rerenderActiveTab()`, and `TOPTAB_GROUPS.tvmovies`.
- `renderSpinWheelTab()` is the entry point; re-fires on scope switch
  (only the auto wheel depends on scope).

## Data model

One global `localStorage` key `spinwheel:v1`:

```js
{
  wheels: [
    {
      id: 'w_<rand>',
      name: 'Date night',
      entries: [
        { type: 'watchlist', showId: 'm3' },
        { type: 'custom', title: 'Some Movie', runtimeMinutes: 120 } // runtime optional
      ]
    }
  ],
  lastWheelId: '__watchlist__',   // reopen last-used wheel
  soundOn: true
}
```

- Named wheels are **global** — not per scope (Karl / Liisa / Together).
- The auto **"Movie Watchlist"** wheel is **not stored**. It is synthesized
  on every render from the active scope's `category:'movie'`,
  `listStatus:'watchlist'` shows, under reserved id `__watchlist__`.
- `watchlist` entries whose `showId` no longer resolves (movie watched or
  deleted) are dropped silently at render time.
- Corrupt / missing localStorage → treat as `{ wheels: [], lastWheelId:
  '__watchlist__', soundOn: true }`. All reads wrapped in try/catch.

## Tab layout

1. **Wheel selector** — pill row: `Movie Watchlist`, then each named wheel,
   then `＋ New wheel` (prompts for a name, creates an empty wheel, selects
   it).
2. **Three side-by-side slot windows**, a **SPIN** button, a **mute
   toggle**.
3. **Editor** — shown only for named wheels, collapsible ("Edit wheel"):
   - rename (inline), delete (confirm)
   - entry list, each with an ✕ remove button
   - "add from watchlist" — dropdown of the current scope's watchlist
     movies not already on this wheel
   - "add custom movie" — title input + optional runtime input + Add
   The auto wheel has no editor.

Long titles in three narrow columns: reduce font size, allow 2 lines,
clip beyond that.

## 3-reel mechanic

On SPIN:

- `isMatch = Math.random() < 0.5`
- **Match** — pick one random entry `winner`; all three reels animate to
  `winner`; on settle, open the result popup.
- **No match** — choose three entries that are **not all identical** (retry
  the random draw until they differ; guaranteed possible because a spin
  needs >= 2 entries). Reels settle mismatched; show a short
  "No match — spin again!" shake. SPIN stays enabled, no popup.
- Reels stop left → right with ~0.4s stagger.
- Spin disabled (with a hint) when the resolved wheel has < 2 entries.
- Each reel is an independent vertical strip of ~40 random entry labels
  ending on the chosen one; `transition: transform` easing over ~2.4s +
  per-reel stagger. The landing value is chosen up front — animation is
  cosmetic.

## Sound (Web Audio, no asset files)

- Lazy-create a single `AudioContext` on the first SPIN click (satisfies
  the autoplay-requires-gesture rule).
- **Reel tick** — short blip, throttled while a reel is spinning.
- **Reel stop** — a low thunk per reel as it settles.
- **Match** — ascending 3-note chime.
- **No match** — short descending "womp".
- All gated on `soundOn`; toggle persists to `spinwheel:v1`.
- If `AudioContext` is unavailable / throws, sound silently no-ops.

## Post-spin popup (match only)

Reuses `.modal-backdrop` / `.modal` styling. Shows winner poster (if a
`watchlist` entry with `posterUrl`), title, runtime. Actions:

- **Watch this one** — close.
- **Spin again** — close, re-spin the same wheel.
- **Remove from wheel** — remove that entry from the current wheel;
  **hidden** on the auto Movie Watchlist wheel.
- **Mark watched** — `watchlist` entries only, and only when
  `canWriteScope(activeScope)`; calls the existing `markMovieWatched(id)`
  then re-renders. Hidden for `custom` entries.

Backdrop click / Watch this one both dismiss. After dismiss,
`refreshSpinStage()` re-enables the SPIN button.

## Custom (non-watchlist) movies

Pure wheel entries: `{ type: 'custom', title, runtimeMinutes? }`. Never
written to Supabase. No "promote to watchlist" action (would bypass the
metadata-lookup ritual in `CLAUDE.md` and create half-populated rows).

## Files touched

- `index.html` only: the existing ~180-line spin module is replaced by the
  expanded version (~400 lines), plus CSS for three reels, the wheel
  selector, and the editor. Commit normally (repo change, unlike the
  Supabase-only flows).

## Testing (Playwright + mocked Supabase, per memory note)

- Auto wheel renders from mocked `showsCache`; scope switch re-renders it.
- Create / rename / delete a named wheel; selector updates; `lastWheelId`
  persists across reload.
- Add a watchlist entry and a custom entry; both appear as reel fodder;
  reload → still there.
- Stub `Math.random` to force match → popup with correct winner; force
  no-match → no popup, shake shown, SPIN still enabled.
- Remove-from-wheel drops the entry and persists.
- Mark-watched calls `markMovieWatched` (mocked) and re-renders.
- Mute toggle persists; no `AudioContext` errors in console.
- `< 2` entries → SPIN disabled with hint.

## Out of scope

- Per-wheel adjustable match odds (fixed 50%).
- Sharing / syncing wheels between users (localStorage only).
- Promoting custom entries to the real watchlist.
