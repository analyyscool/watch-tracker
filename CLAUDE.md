# Watch Tracker — Claude Rules

## Adding a new show

When adding a new show, first ask (if not already clear from context) which
scope it belongs to: Karl's list, Liisa's list, or Together.

Look up the exact episode count before writing the entry, same as before:
- Anime: Jikan API (`https://api.jikan.moe/v4/anime?q=<title>&limit=1`).
- Live-action: TMDB.

Then insert directly into Supabase instead of editing `data.json`:

```bash
node scripts/supabase-write.mjs shows '[{
  "id": "show-slug", "title": "Show Title", "category": "anime",
  "scope": "karl", "poster_url": "...", "studio": "...", "genres": ["..."],
  "total_episodes": 24, "total_seasons": 1, "current_episode": 5,
  "season_episode": 5, "current_season": 1, "list_status": "watching",
  "last_updated": "2026-08-14"
}]'
```

No `git commit` is needed for this action specifically — nothing changed in
the repo, only in Supabase.

## Bumping episode progress and marking shows finished

Progress bumps and marking shows finished are handled in-page now (episode stepper / Mark Finished button) — no longer Claude-mediated.

## Session checkpoints

When the user says "end of session" (or an equivalent closing phrase), run `/capture-workflow` first, then append a new dated entry to `docs/checkpoints.md` summarizing what was done in the session — a few bullet points, newest entry at the bottom. Create the file if it doesn't exist yet.
