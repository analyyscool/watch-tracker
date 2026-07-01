# Watch Tracker — Claude Rules

## Auto-commit after data.json edits

Whenever you update `data.json` (adding, removing, or updating a show), immediately run:

```bash
git add data.json && git commit -m "update: <short description of change>" && git push
```

Do this automatically — do not ask the user to run it.

## Research episode counts when adding a new show

When adding a new show to `data.json`, look up the exact episode count before writing the entry:
- For anime, query the Jikan API (`https://api.jikan.moe/v4/anime?q=<title>&limit=1`) — it wraps MyAnimeList and gives `episodes`, `status`, poster (`images.jpg.large_image_url`), `studios[0].name`, and `genres[].name` in one call. Jikan rate-limits aggressively; space out calls (one at a time) if adding several shows.
- For live-action, use TMDB (`https://www.themoviedb.org/tv/<id>-<slug>`) for episode/season counts, poster, network, and genres.

Fill in from the lookup:
- `totalEpisodes`, `totalSeasons`, and `currentEpisode` (global episode number across seasons)
- `posterUrl` from the lookup's poster image
- `studio` (single string, e.g. `studios[0].name` or the network)
- `genres` (array of strings)
- `lastUpdated` set to today's date (`YYYY-MM-DD`)

Flag to the user if a season is ongoing and the total is not yet confirmed.

## Bumping episode progress

When the user asks to bump/update progress on a show, update `currentEpisode`, `seasonEpisode` (and `currentSeason` if it rolled over), and `lastUpdated` (today's date) for that show in `data.json`, then commit per the rule above.

## Session checkpoints

When the user says "end of session" (or an equivalent closing phrase), run `/capture-workflow` first, then append a new dated entry to `docs/checkpoints.md` summarizing what was done in the session — a few bullet points, newest entry at the bottom. Create the file if it doesn't exist yet.
