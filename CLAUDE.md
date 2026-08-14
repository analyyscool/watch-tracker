# Watch Tracker — Claude Rules

## Adding a new show

When adding a new show, first ask (if not already clear from context) which
scope it belongs to: Karl's list, Liisa's list, or Together.

Look up the exact episode count before writing the entry:
- Anime: query the Jikan API (`https://api.jikan.moe/v4/anime?q=<title>&limit=1`)
  — it wraps MyAnimeList and gives `episodes`, `status`, poster
  (`images.jpg.large_image_url`), `studios[0].name`, and `genres[].name` in
  one call. Jikan rate-limits aggressively; space out calls (one at a time)
  if adding several shows.
- Live-action: TMDB (`https://www.themoviedb.org/tv/<id>-<slug>`) for
  episode/season counts, poster, network, and genres.

Flag to the user if a season is ongoing and the total is not yet confirmed.

`category` is one of `"anime"`, `"western"`, or `"movie"` (used by the Tier
List / Ratings tab's Anime/Western/Movies sub-tabs). Movies are bucketed by
*format*, not origin — an anime film like *Suzume* is `"movie"`, not
`"anime"`.

`runtime_minutes` is required for `category: "western"` or `category:
"movie"` entries — the per-episode runtime for western, the total film
length for movies. Look this up the same way as episode counts (web search
or TMDB). It's not needed for anime: the Stats tab's watch-time calculation
assumes a flat 20 min/episode for anime instead.

Then insert directly into Supabase:

```bash
node scripts/supabase-write.mjs shows '[{
  "id": "show-slug", "title": "Show Title", "category": "anime",
  "scope": "karl", "poster_url": "...", "studio": "...", "genres": ["..."],
  "total_episodes": 24, "total_seasons": 1, "current_episode": 5,
  "season_episode": 5, "current_season": 1, "list_status": "watching",
  "runtime_minutes": null,
  "last_updated": "2026-08-14"
}]'
```

(`runtime_minutes` is only required for `category: "western"` or
`category: "movie"` — omit or leave `null` for anime.)

No `git commit` is needed for this action specifically — nothing changed in
the repo, only in Supabase.

## Bumping episode progress and marking shows finished

Progress bumps and marking shows finished are handled in-page now (episode stepper / Mark Finished button) — no longer Claude-mediated.

## Session checkpoints

When the user says "end of session" (or an equivalent closing phrase), run `/capture-workflow` first, then append a new dated entry to `docs/checkpoints.md` summarizing what was done in the session — a few bullet points, newest entry at the bottom. Create the file if it doesn't exist yet.
