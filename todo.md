# Watch Tracker — Todo

Open tasks queued for a future session. Newest at the top.

---

## Long-term aspiration: minimize Claude-mediated actions

- Raised 2026-08-15: in an ideal world, adding shows/books/manga (and other lookups) would run almost entirely through free public APIs the site calls directly, rather than being Claude-mediated (Karl asks Claude, Claude queries Jikan/TMDB/Open Library, Claude inserts into Supabase). Karl explicitly flagged this as a dream/aspiration, not something to build now — no free API covers judgment calls like remake/sequel disambiguation or webnovel/manhwa-without-MAL metadata, so full self-serve isn't realistic yet. Revisit if/when a broader self-serve add form (see below) gets built — that's the natural point to also wire direct API calls into the client instead of going through Claude each time.

## Stuck leftover worktree directory — Karl to remove manually

- `.worktrees\multiuser-supabase-backend` is an empty, orphaned directory (no `.git` file, not in `git worktree list`) left over from the original multi-user-backend session — safe to delete, but locked by something (`rmdir`/`rm -rf` both fail with "Device or resource busy"). Karl tried closing/reloading VS Code and it still didn't release. Next session: remind Karl this is still pending, and try again — possibly check Task Manager for a stray `python.exe` (an old `http.server` instance) holding it as a working directory, since several were started from that exact path in earlier sessions per shell history.

## Letterboxd import for Liisa — ready to run, just needs her export

- `scripts/import-letterboxd.mjs` was built during the original multi-user backend session and works — it just hasn't been run yet. Now that Liisa's account exists (invited this session, her `user_id` is in `profiles`), the only remaining blocker is Liisa actually producing the export: Letterboxd → Settings → Import & Export → Export, then sending Karl the `ratings.csv`. Run as `node scripts/import-letterboxd.mjs <path-to-ratings.csv> <liisa-user-id>`.

## Minor cleanup items flagged by written-media's final review (not blocking, filed for later)

- **No HTML-escaping on user-entered titles** — `${show.title}`/`${m.title}` get interpolated raw into `innerHTML` across both the shows and written-media card renderers (pre-existing pattern, not introduced by the written-media work, but the to-read quick-add form grew the free-text entry surface). Low risk on a two-person private app, but a shared `escapeHTML()` helper applied consistently across both would close it.
- **Manga/manhwa volume progress (`current_volume`/`total_volumes`) is effectively unreachable** — only rendered in the read-only static stat line, never shown or editable when you actually have write access, and nothing in the UI writes `current_volume` except mark-finished. Consider folding volume progress into the chapter stepper's display.
- **`pinned` isn't cleared when unpinning would make sense elsewhere** — the pattern of clearing `pinned` on completion exists for `shows` (`loadShows()`'s stale-pinned cleanup) and was added for `written_media`'s mark-finished too, but there's no single shared helper — each table reimplements it. Worth generalizing if a third pinned table ever shows up.

## Self-serve add form (Liisa can't add shows/media without Claude Code)

- Raised when setting up Liisa's account: right now "Add Show" (and the new "Add book/manga") is Claude-mediated only — Karl asks Claude, Claude looks up data and inserts. Liisa has no Claude Code access, so she can't add anything herself; she'd have to message Karl every time.
- Recommendation at the time (Karl didn't object, but this was never turned into a tracked item): keep Claude-mediated for now since it preserves judgment on remake/sequel disambiguation and manual chapter/page entry, but build a real in-app add form eventually — likely bundled with whichever session tackles the written-media follow-ups above, since both need the same "manual add, no lookup automation" UI shape.

## Written media (books, manga, manhwa, webnovels) — follow-ups from the 2026-08-14 implementation session

Core feature (schema, Reading tab, progress controls, pinning, ratings/notes) implemented via `docs/superpowers/plans/2026-08-14-written-media.md` — see that plan/ledger for status. These are extra asks Karl raised mid-implementation, deliberately deferred rather than scope-creeped into the running plan:

- **Sub-tabs under Reading for Book / Manga / Manhwa / Webnovel** — mirrors the existing Anime/Western/Movies sub-tab pattern on Tier List and Ratings. The Reading tab currently has a single flat list with a "Type" filter dropdown (unwired — see the plan's Task 5 review note that `loadReading()` populates sort/genre/category selects but never applies them); this ask likely folds into finally wiring that filter, or could be real sub-tabs instead — needs a design pass on which.
- **Ongoing/finished/hiatus status marker for manga/manhwa/webnovel** — separate from `list_status` (which tracks Karl's personal reading progress state: reading/completed/plan_to_read). This would track the *series'* own publication status. Needs a new column (e.g. `series_status`) and a design call on how it's sourced (AniList has this for manga) vs. manually entered.
- **Bulk reading-list seed — mostly done, 2 manga still outstanding.** The Poppy War, The Traitor Baru Cormorant, Six of Crows, A Memory Called Empire, Mistborn: The Final Empire (book 1 only, per Karl — trilogies get just the first book), The Blade Itself (same), Mother of Learning, Lord of Mysteries, and Shadow Slave are all seeded (`plan_to_read`, Karl's scope). Still outstanding: **Vagabond** and **Kingdom** (manga) — MAL/Jikan has been down all session over multiple sessions now; try AniList instead (`https://graphql.anilist.co`, `type: MANGA`) next time, same as the cover-art/episode-count backfill was done 2026-08-16.
- **New-chapter release notifications** for manga/manhwa/webnovels Karl is actively reading — bigger idea, needs its own design pass (what counts as "new," how often to check, where notifications surface since this is a browser app with no push infra today).
- **News-of-new-releases for already-read series** (sequels, new seasons/volumes announced) — bigger idea, same caveat as above, likely needs an external content/news API and its own design pass.

## Together tier list isn't actually shared

- Tier placements and ranked-list order still live in each browser's `localStorage`, not Supabase — so a show Karl tiers under "Together" won't show up tiered on Liisa's device, even though the Together *watch list* itself is genuinely shared. Falls short of what Liisa originally asked for ("imagine all da shi weve watched together in there in one place").
- Needs its own schema addition (no `tier`/`rank` column exists on `shows` today) and a design pass on whether tier placement should be single-shared-value or per-person-on-shared-shows — same kind of decision the ratings-on-Together-shows split already made (each person's own rating, not one shared score).

## `shows.id` can't hold the same title in two scopes

- `shows.id` is a bare `text primary key` slugified from the title — so if Karl already has `suzume` under his personal scope and later wants to log it again under Together (e.g. rewatching it with Liisa), the insert collides on the primary key.
- Real gap in the schema design (inherited from the original design spec), not something to patch mid-feature. Fix is a composite key (`primary key (id, scope)`) or a synthetic UUID id with a `unique(slug, scope)` constraint — needs its own migration.

---
