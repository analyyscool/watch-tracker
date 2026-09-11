# Watch Tracker — Todo

Open tasks queued for a future session. Newest at the top.

---

## Long-term aspiration: minimize Claude-mediated actions

- Raised 2026-08-15: in an ideal world, adding shows/books/manga (and other lookups) would run almost entirely through free public APIs the site calls directly, rather than being Claude-mediated (Karl asks Claude, Claude queries Jikan/TMDB/Open Library, Claude inserts into Supabase). Karl explicitly flagged this as a dream/aspiration, not something to build now — no free API covers judgment calls like remake/sequel disambiguation or webnovel/manhwa-without-MAL metadata, so full self-serve isn't realistic yet.
- **Largely built 2026-09-11**: the Add Show/Movie/Reading forms now have a client-side "Find Cover" button (AniList/TMDB/Open Library) that shows candidate thumbnails to pick from, and picking one also auto-fills total episodes/chapters/pages/runtime from that same matched candidate — poster/cover art and totals no longer need to be Claude-mediated for a well-matched title. Genres/studio for shows still aren't auto-filled (only used server-side by the new-season/sequel-add flow, not exposed in the Add form yet). Ongoing-manga chapter counts and book page counts stay best-effort/blank when the source API doesn't have them (AniList only populates chapters once FINISHED). Disambiguation judgment calls (remakes, wrong-series matches) are still the user's call via the candidate picker, not automated — that's inherent to the design, not a gap to close.

## Someday: MangaUpdates as a second chapter-checker source

- Raised 2026-09-11 while fixing the chapter-checker's title-matching bug: the checker's real remaining gap is that licensed titles (Vinland Saga, One Piece's early chapters, The Promised Neverland, Fire Punch, 20th Century Boys, The Fable) get pulled from MangaDex's English catalog once officially published, so those specific titles silently don't get chapter alerts — not a bug (the checker never lowers a stored total, only raises it), just a coverage gap. MangaUpdates tracks release metadata rather than hosting scanlations, so it might not have this gap, but its API's data quality/rate limits are unverified and the actual impact today is small (6 of 10 currently-reading titles, and only for chapter *alerts* — nothing else breaks). Explicitly a "someday, if it starts bugging you" item, not queued.

## Minor: Add form doesn't surface genres/studio

- Raised 2026-09-11, corrected same day: neither the cover-candidate picker's AniList query nor the season-checker's now fetch genres/studio (the season-checker's query was trimmed down when it stopped inserting separate rows for new anime seasons — see below). Small, not urgent; would need a genres/studio field added to `searchAniListCovers`'s query and to the Add Show modal itself.

## IMDb import

- Raised 2026-09-11: mirror the existing Letterboxd importer (CRLF-safe CSV parsing, scope selection, direct Supabase writes) for IMDb — no public API for personal data, but IMDb lets you export your own ratings/watchlist as CSV from account settings, same shape as the Letterboxd flow. Not scoped/designed yet, just logged so it doesn't drift.

## New-season checker: architecture note (2026-09-11)

- Reworked after Karl flagged two real problems: (1) inserting a new show row per anime sequel was wrong — AniList treats each season as a separate entry, but Karl wants ONE row per show with cumulative episodes/seasons, matching how western shows already work here. Anime new-season detection now bumps the SAME row's `total_episodes`/`total_seasons` instead of inserting, same as western. This also answers "how many seasons have I seen" for free: `current_episode`/`total_episodes` is one cumulative pair, so "finished" always means "caught up to what was out at the time," and a later season bump naturally drops the show back into In Progress. (2) The banner's Dismiss button didn't persist anything — now both Dismiss and Add New Season write a key to a `dismissedSeasonNotices` localStorage list, so a specific detected season won't re-nag once handled either way, while a genuinely later new season (different key) still surfaces normally. (3) Visual redesign shipped same day: collapsed "N new seasons available ▸" bar, expands to a quiet single-line-per-notice list — replaced the original boxed-card stack Karl wasn't sold on.

## Next session: manually audit completed anime/western shows for real season progress

- Raised 2026-09-11: many shows already marked finished/`in_tier_pool` in the app may not actually reflect every season Karl has watched — confirmed via a live example, Mushoku Tensei: Jobless Reincarnation is stored at 48/48 episodes (`in_tier_pool: true`) but a newer season exists that Karl hasn't seen. The new-season checker only surfaces shows where AniList reports a sequel relation AniList doesn't already reflect in the stored total — it won't retroactively fix already-wrong totals for shows where the checker hasn't run yet (throttled, requires the tab to be open, and was blocked entirely by the AniList outage same day it was built). Karl wants to go through the list of completed shows together next session and confirm, per show, which season he's actually seen, backfilling `total_episodes`/`total_seasons`/`current_episode` directly rather than waiting for the checker to catch each one individually.

## Someday: Jikan/MAL as a fallback source when AniList is down

- Raised 2026-09-11: AniList's API was down again this session ("temporarily disabled due to severe stability issues" — the same recurring outage documented elsewhere in this project) while trying to verify the new-season checker live. Jikan exposes a `/anime/{id}/relations` endpoint that could serve as a fallback for sequel detection the same way it already backs up AniList for episode-count lookups elsewhere in `CLAUDE.md`'s rules — but Jikan has also had its own outages historically, so this isn't a clean fix, just a second option to try. Not worth building until AniList's downtime has actually blocked something more than once.

## Add Show doesn't offer a "want to watch" choice like Add Movie does

- Raised 2026-09-11 (Karl: "does the add show add to watchlist or watching list thats kinda confusing right now"): confirmed in code — Add Show's submit handler always sets `list_status: 'watching'` unconditionally for anime/western, with no equivalent of Add Movie's explicit Watched/Want-to-Watch choice. The only way to add a show to the actual Watchlist is a separate, less-visible quick-add row living on the Watchlist section itself (title + tags only, no lookup, no cover search) — not reachable through the same "+ Add → Show" flow. Worth adding the same Watched/Want-to-Watch style field Add Movie already has.

## Written media (books, manga, manhwa, webnovels) — follow-ups from the 2026-08-14 implementation session

Core feature (schema, Reading tab, progress controls, pinning, ratings/notes) implemented via `docs/superpowers/plans/2026-08-14-written-media.md` — see that plan/ledger for status. These are extra asks Karl raised mid-implementation, deliberately deferred rather than scope-creeped into the running plan:

- **News-of-new-releases for already-read written media** (a book series' next volume, a manhwa/webnovel's sequel series announced) — the shows/anime half of this (new season/sequel detection via AniList + TMDB) was built 2026-09-11; ongoing-manga chapter detection already existed via MangaDex. This remaining piece is harder: no clean API signal for "sequel volume announced" the way AniList relations or TMDB season counts work for shows — likely needs its own design pass.

---
