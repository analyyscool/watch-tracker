# Recommendations (Anime + Manga/Manhwa) — Design

## Purpose

A new "Recommendations" tab that suggests anime and manga/manhwa you don't
already have tracked, based on your ratings — both "if you liked X, try Y"
pairings (AniList's own community `recommendations` data) and genre/studio
affinity matches (reusing the scoring engine built for the watchlist-ranking
feature). Western TV, live-action movies, and books are explicitly out of
scope for this spec — see "Deferred scope" below.

## Deferred scope

- **Western TV + live-action movies**: a separate subsystem (TMDB's
  `/tv/{id}/recommendations` and `/movie/{id}/recommendations` endpoints,
  different response shape, different rate limits) — a follow-up project
  once this one ships, not part of this spec.
- **Books**: no free API provides "similar books" recommendations. Open
  Library has no such endpoint; Google Books' anonymous quota was already
  rejected project-wide (see `CLAUDE.md`'s written-media lookup section).
  Not building this without a real source — same "don't guess" stance
  already established elsewhere in this project.

## Data model

Two new Supabase tables:

```sql
create table recommendations_cache (
  scope show_scope not null,
  -- 'anime' caches against `shows` (category='anime'); 'manga' caches
  -- against `written_media` rows of EITHER category='manga' OR
  -- category='manhwa' — both use AniList type MANGA, so they share one
  -- cache bucket and seed pool rather than being split further.
  category text not null,  -- 'anime' | 'manga'
  data jsonb not null,      -- array of recommendation objects, see below
  updated_at timestamptz not null default now(),
  primary key (scope, category)
);

create table dismissed_recommendations (
  scope show_scope not null,
  external_id text not null,  -- AniList media id, stable across refreshes
  primary key (scope, external_id)
);

alter table recommendations_cache enable row level security;
alter table dismissed_recommendations enable row level security;

create policy "recommendations_cache readable by authenticated" on recommendations_cache
  for select using (auth.role() = 'authenticated');
create policy "recommendations_cache writable by owner or together" on recommendations_cache
  for all using (
    auth.role() = 'authenticated'
    and (scope = 'together' or scope::text = (select lower(display_name) from profiles where id = auth.uid()))
  );

create policy "dismissed_recommendations readable by authenticated" on dismissed_recommendations
  for select using (auth.role() = 'authenticated');
create policy "dismissed_recommendations writable by owner or together" on dismissed_recommendations
  for all using (
    auth.role() = 'authenticated'
    and (scope = 'together' or scope::text = (select lower(display_name) from profiles where id = auth.uid()))
  );

grant select, insert, update, delete on public.recommendations_cache, public.dismissed_recommendations
  to service_role, authenticated, anon;
```

This is what makes the feature cross-device: cache and dismissals live in
Supabase, not `localStorage`, so a refresh or dismiss on one device is
visible on another — the same gap just identified in the tier-list system
(see `todo.md`), deliberately not repeated here.

Each object inside `recommendations_cache.data` (a JSON array):

```json
{
  "anilistId": 12345,
  "title": "...",
  "coverUrl": "...",
  "genres": ["..."],
  "studio": "...",
  "reason": "because_rated",
  "reasonDetail": "Vinland Saga",
  "sourceRating": 5.0
}
```

`reason` is `"because_rated"` (seeded from a specific top-rated title, via
AniList's `recommendations` field) or `"affinity"` (genre/studio-search
fallback). `studio`/`sourceRating` are only meaningful for `because_rated`
anime entries.

## Computation pipeline

Runs client-side, triggered when the Recommendations tab opens (if the
scope+category's cache is older than 7 days) or via a manual "Refresh"
button (bypasses the throttle).

1. **Build the "already have" set** — every `shows`/`written_media` row in
   the active scope, any `list_status`/`in_tier_pool` state (watching,
   watchlist, finished, dropped). Dedup against this set is unconditional.
2. **Seed list** — for the `anime` category, `shows` rows rated ≥ 4.0; for
   `manga`, `written_media` rows of category `manga` OR `manhwa` rated
   ≥ 4.0 (both feed the same seed pool — see data-model note above).
   Capped to the 10 highest-rated. For the `together` scope, average both
   raters' scores per item first (mirrors the existing `allRatings` data
   already fetched per row).
3. **Recommendations-field pass** — for each seed, resolve it to an AniList
   media id via title search (same lookup style as the existing cover-art
   matching), then query its `recommendations` field. Aggregate candidates
   across all seeds, dedupe against "already have" and
   `dismissed_recommendations`, rank by (number of seeds recommending it,
   the recommending seed's own rating), keep the top 15.
4. **Genre-affinity fallback** — if step 3 yields fewer than 15, fill the
   remainder via `Page{ media(genre_in: topGenres, sort: SCORE_DESC) }`
   using the same top-genre data the watchlist-ranking feature's
   `computeAffinity` already derives. Same dedup rules apply.
5. **Persist** — upsert the combined list into `recommendations_cache` for
   this scope+category, then render.

**Known limitation**: step 3's title→AniList-id resolution can pick the
wrong edition/entry for an ambiguous title (the same single-top-hit risk
already documented for sequel detection in `CLAUDE.md`). Accepted as a
known tradeoff, not solved with disambiguation UI in this pass.

## Rendering & interactions

A new top-level "Recommendations" tab (alongside TV/Movies, Reading,
Stats), with Anime/Manga sub-tabs inside — same sub-tab pattern as the
existing Stats tab's Watching/Reading split.

Each card: cover art, title, genres, a reason label ("Because you rated
*Vinland Saga* ★4.5" or "Matches your Suspense/Madhouse taste"), and two
actions:

- **+ Add to Watchlist** — inserts into `shows`/`written_media` with
  `list_status: 'watchlist'`/`'plan_to_read'` (same insert shape as the
  existing Add Show/Reading modals).
- **Dismiss (✕)** — writes `{ scope, external_id: anilistId }` to
  `dismissed_recommendations`, removes the card client-side immediately.

A manual "Refresh" button forces recomputation regardless of the 7-day
throttle.

## Error handling

- A seed whose title search fails to resolve, or whose `recommendations`
  fetch fails, is skipped silently — doesn't block the other seeds (same
  "one failure doesn't block the batch" pattern as the existing
  chapter/sequel checkers).
- If AniList fails wholesale during a recompute, fall back to Jikan's
  `/anime/{id}/recommendations` / `/manga/{id}/recommendations` for the
  seed step — mirrors the existing AniList→Jikan fallback already built
  for sequel detection.
- If both AniList and Jikan fail, keep serving the last cached result
  (stale beats empty) with a small "couldn't refresh, showing last known
  recommendations" note instead of an error state.
- Below the existing `MIN_RATED_FOR_AFFINITY` threshold (5 rated items,
  from the watchlist-ranking feature), show an empty state — "Rate a few
  more shows to get personalized recommendations" — rather than computing
  from too little data.
- Supabase write failures (cache upsert, dismiss insert) use the existing
  `checkWriteError` toast pattern.

## Testing approach

No test framework in this project — verification is via Playwright driving
the real page with mocked Supabase (`shows`, `written_media`, plus the two
new tables) and mocked AniList/Jikan fetch responses. Cases to cover:

- Dedup never surfaces a title already present in `shows`/`written_media`
  for the scope, regardless of its status.
- Dismissing a card removes it immediately and it does not reappear on a
  forced re-render from the same (mocked) cache state.
- A cache hit (updated_at < 7 days) skips all network calls entirely.
- The genre-affinity fallback correctly fills remaining slots when the
  recommendations-field pass returns fewer than 15 candidates.
- Together-scope seed selection correctly averages both raters' scores
  before ranking.
