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

## Marking a show finished

When the user says they finished a show, do NOT remove it from `watching`. Instead:
- In `watching`, set `currentEpisode`/`seasonEpisode` to `totalEpisodes` (and `currentSeason` to `totalSeasons` if applicable), and update `lastUpdated`. This is what makes it appear in the app's "Completed" section (which reads full metadata — studio, genres, episode count — from the `watching` entry).
- Also add a matching `{ id, title, posterUrl }` entry to `watched` (used for the tier-list poster grid).

Do not backfill this for shows that were already finished before this rule was adopted — they only need to live in `watched`/tierlist, no need to touch `watching` for those.

## Session checkpoints

When the user says "end of session" (or an equivalent closing phrase), run `/capture-workflow` first, then append a new dated entry to `docs/checkpoints.md` summarizing what was done in the session — a few bullet points, newest entry at the bottom. Create the file if it doesn't exist yet.
