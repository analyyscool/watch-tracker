# Watch Tracker — Claude Rules

## Adding a new show

When adding a new show, first ask (if not already clear from context) which
scope it belongs to: Karl's list, Liisa's list, or Together.

Look up the exact episode count before writing the entry:
- Anime: query AniList's GraphQL API (`https://graphql.anilist.co`, POST,
  `Media(search:$s,type:ANIME){episodes status studios(isMain:true){nodes{name}}
  genres coverImage{extraLarge}}`) — first-party API (not a proxy scraping
  MAL like Jikan is), so it doesn't inherit MAL's frequent outages. Gives
  episode count, status, main studio, genres, and cover art in one call, no
  key needed. Jikan (`https://api.jikan.moe/v4/anime?q=<title>&limit=1`) is
  the fallback if AniList doesn't have a title — check with `curl -s -o
  /dev/null -w '%{http_code}' 'https://api.jikan.moe/v4/anime?q=test&limit=1'`
  first (a 504 means MAL itself is down, not just Jikan).
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

## Adding a book, manga, manhwa, or webnovel

When adding a written-media entry, first ask (if not already clear from
context) which scope it belongs to: Karl's list, Liisa's list, or Together.

Look up chapter/volume counts before writing the entry:
- Manga and manhwa: query AniList's GraphQL API (`https://graphql.anilist.co`,
  POST, `Media(search:$s,type:MANGA){chapters volumes status genres
  coverImage{extraLarge}}`) — covers manhwa (Korean `countryOfOrigin: KR`)
  as well as manga, and doesn't depend on MAL's uptime. When a title has
  multiple candidates (e.g. a common word like "Leviathan"), run a broader
  `Page(perPage:8){media(search:$s,type:MANGA){...countryOfOrigin}}` query
  and pick by `countryOfOrigin`/format rather than trusting the single top
  match — caught a wrong-series match this way once already. `authors` isn't
  in this schema; still needs a manual search or the user. Jikan
  (`https://api.jikan.moe/v4/manga?q=<title>&limit=1`) is the fallback for
  titles AniList doesn't have.
- Books, and manhwa/webnovels with an officially published ebook/print
  edition (many web serials get one later, e.g. via Aethon Books or
  self-pub): cover art via Open Library
  (`https://openlibrary.org/search.json?title=<title>&limit=3` → check
  `author_name` matches the real author before trusting `cover_i`, since
  common titles collide with unrelated books — then
  `https://covers.openlibrary.org/b/id/<cover_i>-L.jpg`) — free, no API
  key, no quota wall. (Google Books was tried first and rejected: its
  anonymous/no-key quota is effectively zero.) Chapter/page counts still
  need to come from the user or a manual search — Open Library is
  cover-art-only here.
- Manhwa/webnovels with no AniList entry and no published edition on Open
  Library: no reliable free source for cover art — ask the user for author,
  chapter/page count (or leave null if unknown/ongoing), and cover art URL
  if they have one.

`category` is one of `"book"`, `"manga"`, `"manhwa"`, or `"webnovel"`.
`total_pages`/`current_page` are only meaningful for `"book"`; the rest use
`total_chapters`/`current_chapter` (plus `total_volumes`/`current_volume`
when the source has volumes).

Then insert directly into Supabase:

```bash
node scripts/supabase-write.mjs written_media '[{
  "title": "Title", "category": "manga",
  "scope": "karl", "author": "...", "cover_url": "...", "genres": ["..."],
  "total_chapters": 100, "current_chapter": 5,
  "total_volumes": 12, "current_volume": 1,
  "list_status": "reading",
  "last_updated": "2026-08-14"
}]'
```

No `git commit` is needed for this action — nothing changed in the repo,
only in Supabase.

**Not idempotent:** unlike `shows`, which upserts on a caller-supplied slug
`id`, `written_media` rows get a generated UUID primary key. Re-running the
same `supabase-write.mjs written_media` insert command creates a duplicate
row instead of updating the existing one. If a re-run is a risk (retrying
after an error, re-pasting a command), query for an existing row by title
first, or pass an explicit `id` in the payload.

## Bumping episode progress and marking shows finished

Progress bumps and marking shows finished are handled in-page now (episode stepper / Mark Finished button) — no longer Claude-mediated.

## Session checkpoints

When the user says "end of session" (or an equivalent closing phrase), run `/capture-workflow` first, then append a new dated entry to `docs/checkpoints.md` summarizing what was done in the session — a few bullet points, newest entry at the bottom. Create the file if it doesn't exist yet.
