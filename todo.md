# Watch Tracker — Todo

Open tasks queued for a future session. Newest at the top.

---

## Long-term aspiration: minimize Claude-mediated actions

- Raised 2026-08-15: in an ideal world, adding shows/books/manga (and other lookups) would run almost entirely through free public APIs the site calls directly, rather than being Claude-mediated (Karl asks Claude, Claude queries Jikan/TMDB/Open Library, Claude inserts into Supabase). Karl explicitly flagged this as a dream/aspiration, not something to build now — no free API covers judgment calls like remake/sequel disambiguation or webnovel/manhwa-without-MAL metadata, so full self-serve isn't realistic yet.
- **Largely built 2026-09-11**: the Add Show/Movie/Reading forms now have a client-side "Find Cover" button (AniList/TMDB/Open Library) that shows candidate thumbnails to pick from, and picking one also auto-fills total episodes/chapters/pages/runtime from that same matched candidate — poster/cover art and totals no longer need to be Claude-mediated for a well-matched title. Genres/studio for shows still aren't auto-filled (only used server-side by the new-season/sequel-add flow, not exposed in the Add form yet). Ongoing-manga chapter counts and book page counts stay best-effort/blank when the source API doesn't have them (AniList only populates chapters once FINISHED). Disambiguation judgment calls (remakes, wrong-series matches) are still the user's call via the candidate picker, not automated — that's inherent to the design, not a gap to close.

## Someday: MangaUpdates as a second chapter-checker source

- Raised 2026-09-11 while fixing the chapter-checker's title-matching bug: the checker's real remaining gap is that licensed titles (Vinland Saga, One Piece's early chapters, The Promised Neverland, Fire Punch, 20th Century Boys, The Fable) get pulled from MangaDex's English catalog once officially published, so those specific titles silently don't get chapter alerts — not a bug (the checker never lowers a stored total, only raises it), just a coverage gap. MangaUpdates tracks release metadata rather than hosting scanlations, so it might not have this gap, but its API's data quality/rate limits are unverified and the actual impact today is small (6 of 10 currently-reading titles, and only for chapter *alerts* — nothing else breaks). Explicitly a "someday, if it starts bugging you" item, not queued.

## Minor: Add form doesn't surface genres/studio

- Raised 2026-09-11: the new cover-candidate picker (AniList/TMDB/Open Library) already receives genres/studio for anime from the same query used by the new-season-sequel-add flow, but the Add Show form itself has no genre/studio fields to fill — so this data is fetched and then discarded for manual adds. Small, not urgent; would need new fields added to the Add Show modal first.

## Written media (books, manga, manhwa, webnovels) — follow-ups from the 2026-08-14 implementation session

Core feature (schema, Reading tab, progress controls, pinning, ratings/notes) implemented via `docs/superpowers/plans/2026-08-14-written-media.md` — see that plan/ledger for status. These are extra asks Karl raised mid-implementation, deliberately deferred rather than scope-creeped into the running plan:

- **News-of-new-releases for already-read written media** (a book series' next volume, a manhwa/webnovel's sequel series announced) — the shows/anime half of this (new season/sequel detection via AniList + TMDB) was built 2026-09-11; ongoing-manga chapter detection already existed via MangaDex. This remaining piece is harder: no clean API signal for "sequel volume announced" the way AniList relations or TMDB season counts work for shows — likely needs its own design pass.

---
