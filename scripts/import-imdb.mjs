// scripts/import-imdb.mjs
// Usage: node scripts/import-imdb.mjs <path-to-watchlist.csv> --scope=karl|liisa|together
//
// IMDb's account-settings CSV export ("Export" button on your watchlist
// page) is the only IMDb import this script handles — ratings are
// intentionally NOT imported (Karl: the site's own ratings are correct,
// IMDb's might not be). Unlike Letterboxd, IMDb watchlists mix movies and
// TV shows in one file (Title Type column), and — also unlike Letterboxd —
// carry no episode/season totals for TV, so TV rows go in with
// total_episodes: null and get flagged in the printed review list, same
// place unmatched titles already get flagged.
//
// Category for TV rows can't be reliably told apart (anime vs western)
// from IMDb's columns alone, so every TV row defaults to 'western' and is
// called out at the end for a manual category flip via supabase-write.mjs
// where it should actually be 'anime'.
import { readFileSync } from 'node:fs';

const SUPABASE_URL = 'https://ppelaixzzgfhqximihpr.supabase.co';
const serviceKey = readFileSync(new URL('../.supabase-service-key', import.meta.url), 'utf8').trim();

const args = process.argv.slice(2);
const csvPath = args.find(a => !a.startsWith('--'));
const scope = args.find(a => a.startsWith('--scope='))?.slice('--scope='.length);

if (!csvPath || !scope) {
  console.error('Usage: node scripts/import-imdb.mjs <path-to-watchlist.csv> --scope=karl|liisa|together');
  process.exit(1);
}
if (scope !== 'karl' && scope !== 'liisa' && scope !== 'together') {
  console.error(`Invalid --scope: ${scope} (expected karl, liisa, or together)`);
  process.exit(1);
}

// IMDb watchlist CSV columns (as of 2026): Position,Const,Created,Modified,
// Description,Title,Original Title,URL,Title Type,IMDb Rating,
// Runtime (mins),Year,Genres,Num Votes,Release Date,Directors
//
// Unlike Letterboxd's export, several of these (Description, IMDb Rating,
// Directors) are routinely blank — a naive "split on commas outside
// quotes" regex silently drops empty fields instead of emitting '', which
// shifts every later column left. Parsed char-by-char instead so an empty
// field between two commas still produces an empty string in place.
function parseCsvLine(line) {
  const fields = [];
  let cur = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inQuotes) {
      if (ch === '"' && line[i + 1] === '"') { cur += '"'; i++; }
      else if (ch === '"') { inQuotes = false; }
      else { cur += ch; }
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === ',') {
      fields.push(cur);
      cur = '';
    } else {
      cur += ch;
    }
  }
  fields.push(cur);
  return fields;
}

function parseCsv(text) {
  // IMDb exports CRLF line endings, same gotcha as Letterboxd's importer —
  // normalize first or a stray \r glues onto the last column's header/values.
  const [header, ...lines] = text.replace(/\r\n/g, '\n').trim().split('\n');
  const cols = parseCsvLine(header);
  return lines.filter(l => l.trim()).map(line => {
    const values = parseCsvLine(line);
    return Object.fromEntries(cols.map((c, i) => [c, values[i] ?? '']));
  });
}

const MOVIE_TITLE_TYPES = new Set(['movie', 'tvMovie', 'short', 'video']);
const TV_TITLE_TYPES = new Set(['tvSeries', 'tvMiniSeries', 'tvSpecial']);

function slugify(title) {
  return title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
}

// Title-matching against existing rows must be scoped to the target scope —
// matching against ALL shows would let an imported entry attach to a
// same-titled row that belongs to a different scope, invisible in that
// scope's own view.
async function fetchScopedShows() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/shows?select=id,title&scope=eq.${scope}`, {
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
  });
  if (!res.ok) {
    console.error(`Failed to fetch existing shows (scope=${scope}): ${res.status} ${res.statusText}`);
    console.error(await res.text());
    process.exit(1);
  }
  return res.json();
}

// Used only for the collision pre-flight below — unscoped, so we can catch
// an id collision against a DIFFERENT title living under any scope.
async function fetchAllShowIds() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/shows?select=id,title`, {
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
  });
  if (!res.ok) {
    console.error(`Failed to fetch all show ids: ${res.status} ${res.statusText}`);
    console.error(await res.text());
    process.exit(1);
  }
  return res.json();
}

const rows = parseCsv(readFileSync(csvPath, 'utf8'));
const existingScopedShows = await fetchScopedShows();
const newMovies = [];
const newTvForReview = [];
const skipped = [];
const toInsertShows = [];

for (const row of rows) {
  const title = row.Title;
  const titleType = row['Title Type'];
  if (!title || !titleType) continue;
  if (existingScopedShows.some(s => s.title.toLowerCase() === title.toLowerCase())) continue;

  const runtime = parseInt(row['Runtime (mins)'], 10);
  const genres = row.Genres ? row.Genres.split(',').map(g => g.trim()).filter(Boolean) : null;
  const id = slugify(`${title}-${row.Year || ''}`);

  if (MOVIE_TITLE_TYPES.has(titleType)) {
    toInsertShows.push({
      id, title, category: 'movie', scope, list_status: 'watchlist', in_tier_pool: false,
      runtime_minutes: Number.isFinite(runtime) ? runtime : null,
      genres,
    });
    newMovies.push(title);
  } else if (TV_TITLE_TYPES.has(titleType)) {
    toInsertShows.push({
      id, title, category: 'western', scope, list_status: 'watchlist', in_tier_pool: false,
      runtime_minutes: Number.isFinite(runtime) ? runtime : null,
      genres,
    });
    newTvForReview.push(title);
  } else {
    skipped.push(`${title} (${titleType})`);
  }
}

// Pre-flight collision check: two different titles can slugify to the same
// id. Because the insert below uses merge-duplicates, an undetected
// collision would silently overwrite an existing row's scope/category/
// list_status — including rows belonging to a different scope. Check
// against the FULL (unscoped) id list and refuse to insert any colliding
// slug — same safeguard as the Letterboxd importer.
let finalToInsert = toInsertShows;
if (toInsertShows.length) {
  const allShows = await fetchAllShowIds();
  const allById = new Map(allShows.map(s => [s.id, s.title]));
  const blocked = [];
  finalToInsert = [];
  for (const show of toInsertShows) {
    const existingTitle = allById.get(show.id);
    if (existingTitle !== undefined && existingTitle.toLowerCase() !== show.title.toLowerCase()) {
      blocked.push({ id: show.id, newTitle: show.title, existingTitle });
    } else {
      finalToInsert.push(show);
    }
  }
  if (blocked.length) {
    console.error(`Refusing to insert ${blocked.length} show(s) whose id collides with a different existing title:`);
    blocked.forEach(b => console.error(`  - id "${b.id}": import title "${b.newTitle}" vs existing "${b.existingTitle}"`));
    console.error('These were skipped. Resolve manually (e.g. adjust the slug) and re-run.');
  }
}

if (finalToInsert.length) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/shows`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, Prefer: 'resolution=merge-duplicates' },
    body: JSON.stringify(finalToInsert),
  });
  if (!res.ok) {
    console.error(`Failed to insert new shows: ${res.status} ${res.statusText}`);
    console.error(await res.text());
    process.exit(1);
  }
}

console.log(`Imported ${finalToInsert.length} watchlist entries to scope "${scope}" (${newMovies.length} movies, ${newTvForReview.length} TV shows).`);
if (newTvForReview.length) {
  console.log('\nTV shows inserted as category "western" by default — flip any of these to "anime" via supabase-write.mjs if wrong:');
  newTvForReview.forEach(t => console.log(`  - ${t}`));
}
if (skipped.length) {
  console.log('\nSkipped (unrecognized Title Type, e.g. video game or single episode):');
  skipped.forEach(s => console.log(`  - ${s}`));
}
