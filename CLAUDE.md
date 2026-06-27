# Watch Tracker — Claude Rules

## Auto-commit after data.json edits

Whenever you update `data.json` (adding, removing, or updating a show), immediately run:

```bash
git add data.json && git commit -m "update: <short description of change>" && git push
```

Do this automatically — do not ask the user to run it.

## Research episode counts when adding a new show

When adding a new show to `data.json`, always web-search the exact episode count before writing the entry. Look up:
- Total episodes per season
- Total seasons (confirmed and announced)
- Total episode count across all seasons

Use the researched numbers for `totalEpisodes`, `totalSeasons`, and to calculate `currentEpisode` (global episode number across seasons). Flag to the user if a season is ongoing and the total is not yet confirmed.
