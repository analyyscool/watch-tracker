# Watch Tracker — Todo

Open tasks queued for a future session. Newest at the top.

---

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

- **"Anime-end-point" note for manga/manhwa marked reading at a chapter that isn't real personal progress** — Haikyu!!, Hunter x Hunter, The Fable, Blue Lock, and Vinland Saga were seeded with `current_chapter` set to wherever their anime adaptation currently ends, not chapters Karl has actually read. Needs a small UI marker (e.g. a badge/note on the card) distinguishing "caught up via anime" from real manual reading progress, so it's not misread as him having read that far. Could be a new boolean column (`chapter_from_anime` or similar) or just a `tags` entry — needs a quick design call.
- **Sub-tabs under Reading for Book / Manga / Manhwa / Webnovel** — mirrors the existing Anime/Western/Movies sub-tab pattern on Tier List and Ratings. The Reading tab currently has a single flat list with a "Type" filter dropdown (unwired — see the plan's Task 5 review note that `loadReading()` populates sort/genre/category selects but never applies them); this ask likely folds into finally wiring that filter, or could be real sub-tabs instead — needs a design pass on which.
- **Cover-image API fetch for written media**, same pattern as Jikan (anime) / TMDB (shows). Jikan already covers manga (and sometimes manhwa) — the `CLAUDE.md` add-flow docs written this session already say to use it, so this may already partly work; open question is books (no established source yet — Google Books API is a candidate, not committed to) and manhwa/webnovels not on MAL.
- **Ongoing/finished/hiatus status marker for manga/manhwa/webnovel** — separate from `list_status` (which tracks Karl's personal reading progress state: reading/completed/plan_to_read). This would track the *series'* own publication status. Needs a new column (e.g. `series_status`) and a design call on how it's sourced (Jikan has this for manga) vs. manually entered.
- **Bulk reading-list seed** — Karl provided a second list of titles to add (novels: Red Rising [already added], The Poppy War, The Traitor Baru Cormorant, Mistborn, The First Law trilogy, Six of Crows, A Memory Called Empire; manga: Vagabond, 20th Century Boys [already added], Vinland Saga [already added], Berserk [already added], Kingdom, Tokyo Ghoul [already added], The Promised Neverland [already added]; webnovels/manhwa: Omniscient Reader's Viewpoint [already added], Tower of God [already added], Mother of Learning, Lord of Mysteries, Shadow Slave). Needs states confirmed per-title (reading/plan-to-read/skip) the same way the first batch was, then seeded via `scripts/supabase-write.mjs written_media`.
- **New-chapter release notifications** for manga/manhwa/webnovels Karl is actively reading — bigger idea, needs its own design pass (what counts as "new," how often to check, where notifications surface since this is a browser app with no push infra today).
- **News-of-new-releases for already-read series** (sequels, new seasons/volumes announced) — bigger idea, same caveat as above, likely needs an external content/news API and its own design pass.

## Together tier list isn't actually shared

- Tier placements and ranked-list order still live in each browser's `localStorage`, not Supabase — so a show Karl tiers under "Together" won't show up tiered on Liisa's device, even though the Together *watch list* itself is genuinely shared. Falls short of what Liisa originally asked for ("imagine all da shi weve watched together in there in one place").
- Needs its own schema addition (no `tier`/`rank` column exists on `shows` today) and a design pass on whether tier placement should be single-shared-value or per-person-on-shared-shows — same kind of decision the ratings-on-Together-shows split already made (each person's own rating, not one shared score).

## `shows.id` can't hold the same title in two scopes

- `shows.id` is a bare `text primary key` slugified from the title — so if Karl already has `suzume` under his personal scope and later wants to log it again under Together (e.g. rewatching it with Liisa), the insert collides on the primary key.
- Real gap in the schema design (inherited from the original design spec), not something to patch mid-feature. Fix is a composite key (`primary key (id, scope)`) or a synthetic UUID id with a `unique(slug, scope)` constraint — needs its own migration.

---
