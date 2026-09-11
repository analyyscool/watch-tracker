# Watch Tracker — Todo

Open tasks queued for a future session. Newest at the top.

---

## Long-term aspiration: minimize Claude-mediated actions

- Raised 2026-08-15: in an ideal world, adding shows/books/manga (and other lookups) would run almost entirely through free public APIs the site calls directly, rather than being Claude-mediated (Karl asks Claude, Claude queries Jikan/TMDB/Open Library, Claude inserts into Supabase). Karl explicitly flagged this as a dream/aspiration, not something to build now — no free API covers judgment calls like remake/sequel disambiguation or webnovel/manhwa-without-MAL metadata, so full self-serve isn't realistic yet.
- **Partially built 2026-09-11**: the Add Show/Movie/Reading forms now have a client-side "Find Cover" button (AniList/TMDB/Open Library, same keys/pattern as the new-season checker) that shows candidate thumbnails to pick from — poster/cover art no longer needs to be Claude-mediated. Episode/chapter counts, genres, studio, and disambiguation judgment calls are still manual/Claude-mediated — those still need the kind of judgment no free API provides.

## Written media (books, manga, manhwa, webnovels) — follow-ups from the 2026-08-14 implementation session

Core feature (schema, Reading tab, progress controls, pinning, ratings/notes) implemented via `docs/superpowers/plans/2026-08-14-written-media.md` — see that plan/ledger for status. These are extra asks Karl raised mid-implementation, deliberately deferred rather than scope-creeped into the running plan:

- **News-of-new-releases for already-read written media** (a book series' next volume, a manhwa/webnovel's sequel series announced) — the shows/anime half of this (new season/sequel detection via AniList + TMDB) was built 2026-09-11; ongoing-manga chapter detection already existed via MangaDex. This remaining piece is harder: no clean API signal for "sequel volume announced" the way AniList relations or TMDB season counts work for shows — likely needs its own design pass.

---
