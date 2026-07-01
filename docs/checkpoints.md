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
