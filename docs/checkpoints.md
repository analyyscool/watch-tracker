# Session Checkpoints

A running log of what was done each session, written when Karl says "end of session." Newest entry at the bottom.

---

## 2026-07-02

- Sorted "currently watching" cards by percent remaining; marked Samurai Champloo finished.
- Added poster images for all shows (MyAnimeList/Jikan for anime, TMDB for live-action), plus a pin/prioritize feature (max 3, sorts to top) via a 3-task subagent-driven-development plan.
- Verified every show's episode/season totals against MyAnimeList and corrected 5: Hell's Paradise, Classroom of the Elite, Fire Force, Apothecary Diaries (Season 2 was missing entirely), Kaiji. Updated `CLAUDE.md` so future episode-count lookups query Jikan/TMDB directly instead of a generic web search.
- Removed the "+1 ep" quick-bump button (added no real value over asking Claude directly, per feedback).
- Added a second "Tier List" tab: drag-and-drop S/A/B/C/D/F tiers plus a separate Ranked List mode, both backed by `localStorage`. Seeded the backlog with 72 previously-watched shows (posters fetched from MAL/TMDB) in a new `data.json` `"watched"` array, merged with the existing "completed" shows.
- Fixed mobile touch support: replaced native HTML5 drag-and-drop (no touch equivalent) with the Pointer Events API. Found and fixed a real bug along the way — reparenting the dragged element mid-drag broke pointer capture and silently dropped the `pointerup` event (documented in project memory: `pointer-events-reparent-bug.md`).
- Added a "Copy Export" button (tier list / ranked list to clipboard as text), since both are `localStorage`-only with no other backup path.
- Added tap-to-pick / tap-to-place for the tier list (solves dragging into a tier that's scrolled off-screen), up/down arrow buttons for the ranked list (solves imprecise drag-to-position across 72 items), and auto-scroll near the viewport top/bottom edges during any drag.
- Captured 2 memories from this session: a feedback note on skipping the full `subagent-driven-development` pipeline for small solo projects, and the Pointer Events reparent-bug technical note.

## 2026-07-02 (cont.)

- Brainstormed tier-list feature ideas (Karl asked "any other feature ideas?"); shortlisted an Anilist/MAL score badge as the pick to build.
- Implemented it: fetched MAL scores for all 72 tier-list pool shows via Jikan, with year/exact-title disambiguation to avoid remake/franchise mismatches (caught and fixed bad matches for Berserk 1997 vs. the 2016 remake, One Piece TV vs. a movie, and JoJo's Bizarre Adventure 2012 vs. a 1993 OVA). Added `malScore` to `data.json` and a score-badge UI element to both the Tier List and Ranked List views. Verified visually via Playwright — worked correctly.
- Karl reviewed it live and didn't like it ("i dont really vibe with it"). Reverted both commits (`git revert`) to remove the feature entirely; `data.json`/`index.html` are back to pre-feature state.
- Captured 1 feedback memory: for effort-heavy or visually-opinionated features, show a quick low-fidelity preview before the full build — even when told "implement without input needed," since that grants a decision-checkpoint skip, not an aesthetic one.

## 2026-07-23

- Bumped progress across several shows: Moriarty the Patriot to ep 8, then ep 19/24 (clarified "5 to go" meant overall, not season 1), then finished; Dragon Ball (Fan Cut) to ep 45, then 55, then 65 of 82.
- Marking Moriarty finished surfaced a data-model gap: it was moved out of `watching` entirely, which meant it dropped out of the app's "Completed" section (that section is derived from `watching` entries where `currentEpisode >= totalEpisodes`, not from the `watched` array — confirmed by checking how Samurai Champloo/Witch Hat Atelier still appear there). Fixed by keeping the entry in `watching` maxed out *and* adding it to `watched`.
- Codified this as a new rule in `CLAUDE.md`: finishing a show updates it in `watching` to totalEpisodes (drives the Completed section) and also adds it to `watched` (drives the tier-list grid) — never remove it from `watching`. No backfill needed for shows already finished before this rule.
- Investigated a reported "Moriarty poster missing" issue: verified the `posterUrl` against Jikan's API (exact match) and confirmed the image loads (200 OK) — likely a stale screenshot/cache, no data fix needed.
- Ran `/capture-workflow`: no new promotable memories this session — the finished-show rule went straight into project `CLAUDE.md` rather than through memory first.

## 2026-08-12

- Finished Loki (S2E12/12, added to `watched`); bumped Dragon Ball Z Kai (Recut) to ep 17/47.
- Split the Tier List into Anime/Western/Movies sub-tabs, each with independent tier placement and ranked-list state (separate `localStorage` keys, one-time migration of existing placements into the Anime tab). Added a `category` field to every `watching`/`watched` entry and backfilled all ~90 existing entries (movies bucketed by format regardless of origin — anime films like *Suzume* are `"movie"`, not `"anime"`).
- Built four more features in one pass (design spec first, then direct implementation — skipped the full plan/subagent pipeline given project scale, per existing memory): half-star (0–5, Letterboxd-style) ratings for movies; freeform notes on any watched show (Completed cards, Tier List chips, and the new Movies tab all share one note-editing modal); a dedicated Movies tab (poster grid, sortable by rating/A–Z/added); a Stats tab (episode/hour totals, genre/studio/category breakdowns, with explicit captions where the underlying data is partial); and sort/filter controls (% complete, last updated, A–Z, genre, studio) on both Watching and Completed. Ratings/notes live in `localStorage` only, synced to `data.json` via a new "Copy Ratings & Notes" export button (same paste-to-Claude pattern as the existing tier-list export) — `CLAUDE.md` now documents how to merge that block in.
- Researched real per-episode/per-film runtimes (web search) for the 3 western shows and 13 movies to back the Stats tab's hours-watched figure; anime uses a flat 20 min/episode assumption since it's not tracked per-show.
- Caught a design gap myself before building: notes were originally scoped to "Completed section + Movies tab" only, which would've left the ~60 older `watched`-only anime entries (never passed through `watching`) with no way to get a note at all, since they only ever render as Tier List chips. Fixed by adding the same note affordance to chips too, with care to stop the note icon's `pointerdown` from bubbling into the chip's own drag/pick handler.
- Follow-up fix: pinned shows in the Watching tab now always lead the list and are exempt from genre/studio filters — filters only narrow down the non-pinned remainder.
- Tested everything live via Playwright (star half-fill precision, note modal on all three surfaces, sort/filter persistence, drag-and-pick unaffected by the new note icon, export clipboard contents, stats math, pinned-first-with-filter behavior) — all passed.
- Ran `/capture-workflow`: no new promotable memories this session — nothing was written to `collaboration-preferences.md` or project memory to promote, and this session's decisions (notes-coverage fix, pinned-filter behavior) are watch-tracker-specific rather than repeatable cross-project patterns.
