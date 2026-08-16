# Watch Tracker — Todo

Open tasks queued for a future session. Newest at the top.

---

## Long-term aspiration: minimize Claude-mediated actions

- Raised 2026-08-15: in an ideal world, adding shows/books/manga (and other lookups) would run almost entirely through free public APIs the site calls directly, rather than being Claude-mediated (Karl asks Claude, Claude queries Jikan/TMDB/Open Library, Claude inserts into Supabase). Karl explicitly flagged this as a dream/aspiration, not something to build now — no free API covers judgment calls like remake/sequel disambiguation or webnovel/manhwa-without-MAL metadata, so full self-serve isn't realistic yet. Revisit if/when a broader self-serve add form (see below) gets built — that's the natural point to also wire direct API calls into the client instead of going through Claude each time.

## Stuck leftover worktree directory — Karl to remove manually

- `.worktrees\multiuser-supabase-backend` is an empty, orphaned directory (no `.git` file, not in `git worktree list`) left over from the original multi-user-backend session — safe to delete, but locked by something (`rmdir`/`rm -rf` both fail with "Device or resource busy"). Karl tried closing/reloading VS Code and it still didn't release. Next session: remind Karl this is still pending, and try again — possibly check Task Manager for a stray `python.exe` (an old `http.server` instance) holding it as a working directory, since several were started from that exact path in earlier sessions per shell history.

## Letterboxd import for Liisa — ready to run, just needs her export

- `scripts/import-letterboxd.mjs` was built during the original multi-user backend session and works — it just hasn't been run yet. Now that Liisa's account exists (invited this session, her `user_id` is in `profiles`), the only remaining blocker is Liisa actually producing the export: Letterboxd → Settings → Import & Export → Export, then sending Karl the `ratings.csv`. Run as `node scripts/import-letterboxd.mjs <path-to-ratings.csv> <liisa-user-id>`.

## Written media (books, manga, manhwa, webnovels) — follow-ups from the 2026-08-14 implementation session

Core feature (schema, Reading tab, progress controls, pinning, ratings/notes) implemented via `docs/superpowers/plans/2026-08-14-written-media.md` — see that plan/ledger for status. These are extra asks Karl raised mid-implementation, deliberately deferred rather than scope-creeped into the running plan:

- **News-of-new-releases for already-read series** (sequels, new seasons/volumes announced) — bigger idea, same caveat as above, likely needs an external content/news API and its own design pass.

---
