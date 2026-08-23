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

For manga/manhwa, also set `series_status` from AniList's `status` field —
maps `FINISHED`→`"finished"`, `RELEASING`→`"ongoing"`, `HIATUS`→`"hiatus"`,
`CANCELLED`→`"cancelled"`. This tracks the *series'* own publication state
(shown as a small badge next to the category label), separate from
`list_status` which tracks the user's personal reading progress. Note
AniList's `HIATUS` value is unreliable for long-dormant series (e.g.
*Vagabond* has been inactive since 2015 but AniList still reports
`RELEASING`) — cross-check with a web search if a series is known to be
stalled and AniList disagrees. Leave `series_status` `null` for books and
webnovels (no reliable source).

Then insert directly into Supabase:

```bash
node scripts/supabase-write.mjs written_media '[{
  "title": "Title", "category": "manga",
  "scope": "karl", "author": "...", "cover_url": "...", "genres": ["..."],
  "total_chapters": 100, "current_chapter": 5,
  "total_volumes": 12, "current_volume": 1,
  "series_status": "ongoing",
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

## Updating existing rows with supabase-write.mjs

To patch just a few fields on an existing row (e.g. backfilling
`total_episodes` or `genres`), pass `id` plus only the changed fields —
`Prefer: resolution=merge-duplicates` means columns you omit are left alone,
so this is safe for nullable columns.

However, the row's `NOT NULL` columns (`title`, `category`, `scope` on both
`shows` and `written_media`) must be included in *every* payload, even when
you're not changing them. PostgREST's upsert validates the INSERT branch's
required columns before `ON CONFLICT DO UPDATE` kicks in, so a payload of
just `{"id": "...", "total_episodes": 24}` fails with a `23502` NOT NULL
violation rather than silently updating just that field. Always send
`{"id": "...", "title": "...", "category": "...", "scope": "...", <changed
fields>}`.

## Bumping episode progress and marking shows finished

Progress bumps and marking shows finished are handled in-page now (episode stepper / Mark Finished button) — no longer Claude-mediated.

## New-chapter checking (manga/manhwa)

Handled in-page, not Claude-mediated: whenever the Reading tab renders, `checkNewChapters()` polls MangaDex (not AniList — AniList's `chapters` field is only populated once a series is `FINISHED`, so it's useless for the ongoing titles this feature cares about) for each actively-reading manga/manhwa's live chapter count, throttled to once per 6 hours via a `lastChapterCheck` localStorage timestamp. If MangaDex's count exceeds the stored `total_chapters`, it bumps the stored total (so the same new chapters aren't re-announced next check) and shows a dismissible banner. MangaDex's raw top search hit is often a colorized/spinoff edition that lags behind the real release (e.g. "Hunter x Hunter (Official Colored)" outranks the base series) — the code prefers an exact title match over the top hit to avoid pulling a stale count from the wrong edition.

## Auditing self-added entries for missing metadata

The website's own "+ Add Show", "+ Add Movie", and "+ Add Reading" modals
are explicitly no-lookup manual entry (the modal hint says as much) — they
only save what the user typed, so anything added that way is missing
whatever the user didn't fill in themselves: usually poster/cover art,
genres, studio, and sometimes runtime.

When asked to check for missing metadata (e.g. "check for items added on
the website", "anything missing images/genres?"), query both tables for
gaps rather than guessing which entries were self-added:

```bash
KEY=$(cat .supabase-service-key)
curl -s "https://ppelaixzzgfhqximihpr.supabase.co/rest/v1/shows?select=id,title,category,poster_url,genres,studio,runtime_minutes&or=(poster_url.is.null,genres.is.null)" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
curl -s "https://ppelaixzzgfhqximihpr.supabase.co/rest/v1/written_media?select=id,title,category,cover_url,genres&cover_url=is.null" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```

For each gap found, backfill using the same lookup sources and caveats as
the "Adding a new show" / "Adding a book, manga, manhwa, or webnovel"
sections above (AniList → Jikan fallback for anime/manga, TMDB for
live-action, Open Library for books) — including checking AniList/Jikan
uptime first, since both have been flaky. Report anything that couldn't be
confidently matched (ambiguous title, no source found) instead of guessing
— a wrong cover/genre is worse than a missing one. Write confirmed results
directly to Supabase per the usual `supabase-write.mjs` commands; no `git
commit` needed since nothing in the repo changes.

## Session checkpoints

When the user says "end of session" (or an equivalent closing phrase), run `/capture-workflow` first, then append a new dated entry to `docs/checkpoints.md` summarizing what was done in the session — a few bullet points, newest entry at the bottom. Create the file if it doesn't exist yet.
