# Watch Tracker — Todo

Open tasks queued for a future session. Newest at the top.

---

## Create Liisa's Supabase Auth account

- Her account was intentionally left uncreated at launch (per project decision — she starts empty). Invite her user via Supabase Dashboard → Authentication → Users → Invite user, then run an `insert into profiles (id, display_name) values ('<her-uuid>', 'Liisa');` with her real UUID (mirrors what was done for Karl's profile row during the original migration).

## Password-based auth instead of magic-link-every-time

- Currently sign-in is passwordless (magic link) — Karl wants an actual password so he doesn't need to confirm via email each time. Supabase Auth supports email+password natively; this is a UI change (password field on the sign-in prompt) plus switching `signInWithOtp` to `signInWithPassword`/`signUp`, not a schema change. Note: `supabase-js`'s session persistence already means magic-link sign-in should be rare per device — worth checking whether the actual friction is session expiry/persistence not working as expected, versus genuinely wanting password auth, before assuming this is the fix needed.

## Signed-out view should show only a sign-in prompt, not empty data

- Right now a signed-out visitor sees the full four-tab UI (Watching/Tier List/Ratings/Stats) rendering as if it's real, just empty — misleading, since it's not "there's nothing here" but "you're not logged in." Should gate the whole app behind a simple "please sign in" screen when `currentProfile` is null, rather than letting the existing tabs render emptily.

## New content type: written media (books, manga, manhwa, webnovels)

- New idea (not yet designed): a section for tracking reading, parallel to the existing anime/western/movie tracking. Needs its own brainstorm — likely a new `category` value or a wholly separate content type or "media_type" dimension (books/manga have different progress units — pages/chapters, not episodes — so `total_episodes`/`current_episode` probably don't map cleanly and this may need its own columns or its own table rather than overloading `shows`). Scope this properly next session rather than bolting it on quickly.

## Together tier list isn't actually shared

- Tier placements and ranked-list order still live in each browser's `localStorage`, not Supabase — so a show Karl tiers under "Together" won't show up tiered on Liisa's device, even though the Together *watch list* itself is genuinely shared. Falls short of what Liisa originally asked for ("imagine all da shi weve watched together in there in one place").
- Needs its own schema addition (no `tier`/`rank` column exists on `shows` today) and a design pass on whether tier placement should be single-shared-value or per-person-on-shared-shows — same kind of decision the ratings-on-Together-shows split already made (each person's own rating, not one shared score).

## `shows.id` can't hold the same title in two scopes

- `shows.id` is a bare `text primary key` slugified from the title — so if Karl already has `suzume` under his personal scope and later wants to log it again under Together (e.g. rewatching it with Liisa), the insert collides on the primary key.
- Real gap in the schema design (inherited from the original design spec), not something to patch mid-feature. Fix is a composite key (`primary key (id, scope)`) or a synthetic UUID id with a `unique(slug, scope)` constraint — needs its own migration.

---
