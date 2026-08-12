# Watch Tracker — Todo

Open tasks queued for a future session. Newest at the top.

---

## Rename "Movies" tab to "Ratings" + extend ratings to Anime/Western

- The current top-level "Movies" tab (poster grid, half-star ratings, notes, Copy Ratings & Notes export) should be renamed to "Ratings" — it's a rating system, not just a movie browser, and "Movies" collides in name with Tier List's Movies sub-tab even though they're different concepts (absolute score vs. relative S–F rank).
- Extend the same rating/notes UI to Anime and Western shows too, not just Movies — likely as sub-tabs within "Ratings" mirroring the Tier List's Anime/Western/Movies pattern (reuse `renderStars`/`noteButtonHTML`/the export flow, just filtered by category like the Tier List sub-tabs already are).
- Decide whether `rating` becomes valid on any `watched` entry regardless of category (currently the data model and `CLAUDE.md` document ratings as movie-only) — this needs a design pass, not just a rename.

## Backend (Supabase) for progress updates — narrow scope first

- Move the two highest-friction Claude-mediated actions into real in-page writes: bumping episode progress, and marking a show finished. Estimated ~2–4 hours: create a Supabase project + `shows` table mirroring the current `data.json` shape, migrate existing data in, swap the ~6 `fetch('data.json')` call sites in `index.html` for Supabase queries, wire the progress-bump/mark-finished UI to write directly.
- Fuller scope (optional, do only if the narrow version proves worth it): also move ratings/notes off `localStorage` into Supabase, removing the export-and-paste-to-Claude step entirely (~half a day extra, includes a migration path for whatever's already sitting in localStorage e.g. existing ratings/notes at time of migration).
- Keep "Add a new show" Claude-mediated even after this — that's the one action that benefits from judgment (remake/sequel disambiguation, right poster), not just a database write.
- Note: the Supabase anon key will end up in `index.html`, which is a public GitHub repo. That's expected/fine for Supabase's client-side model (gated by row-level-security policies, not key secrecy) — just be deliberate about setting up RLS rather than assuming the key needs to be hidden.

---
