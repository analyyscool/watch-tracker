// scripts/import-letterboxd.mjs
// Usage: node scripts/import-letterboxd.mjs <path-to-ratings.csv> <liisa-user-id>
import { readFileSync } from 'node:fs';

const SUPABASE_URL = 'https://ppelaixzzgfhqximihpr.supabase.co';
const serviceKey = readFileSync(new URL('../.supabase-service-key', import.meta.url), 'utf8').trim();

const [, , csvPath, userId] = process.argv;
if (!csvPath || !userId) {
  console.error('Usage: node scripts/import-letterboxd.mjs <path-to-ratings.csv> <liisa-user-id>');
  process.exit(1);
}

// Letterboxd ratings.csv columns: Date,Name,Year,Letterboxd URI,Rating
function parseCsv(text) {
  const [header, ...lines] = text.trim().split('\n');
  const cols = header.split(',');
  return lines.map(line => {
    // naive split is fine here — Letterboxd quotes titles containing commas
    const matches = [...line.matchAll(/"([^"]*)"|([^,]+)/g)].map(m => m[1] ?? m[2] ?? '');
    return Object.fromEntries(cols.map((c, i) => [c, matches[i] ?? '']));
  });
}

// This script only ever imports Liisa's Letterboxd data, so title-matching
// against existing rows must be scoped to scope='liisa'. Matching against
// ALL shows would let Liisa's rating attach to a same-titled row Karl
// already has under scope='karl', invisible in her own view.
async function fetchLiisaShows() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/shows?select=id,title&scope=eq.liisa`, {
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
  });
  if (!res.ok) {
    console.error(`Failed to fetch existing shows (scope=liisa): ${res.status} ${res.statusText}`);
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

function slugify(title) {
  return title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
}

const rows = parseCsv(readFileSync(csvPath, 'utf8'));
const existingLiisaShows = await fetchLiisaShows();
const unmatched = [];
const toInsertShows = [];
const toInsertRatings = [];

for (const row of rows) {
  const title = row.Name;
  const rating = parseFloat(row.Rating);
  let match = existingLiisaShows.find(s => s.title.toLowerCase() === title.toLowerCase());
  if (!match) {
    const id = slugify(`${title}-${row.Year || ''}`);
    match = { id, title };
    toInsertShows.push({ id, title, category: 'movie', scope: 'liisa', list_status: null, in_tier_pool: true });
    unmatched.push(title);
  }
  if (!isNaN(rating)) {
    toInsertRatings.push({ show_id: match.id, user_id: userId, rating });
  }
}

// Pre-flight collision check: two different titles can slugify to the same
// id (e.g. two movies that reduce to the same id after stripping
// punctuation). Because the insert below uses merge-duplicates, an
// undetected collision would silently overwrite an existing row's
// scope/category/list_status — including rows belonging to Karl or
// 'together'. Check against the FULL (unscoped) id list, not just
// scope=liisa, and refuse to insert any colliding slug.
if (toInsertShows.length) {
  const allShows = await fetchAllShowIds();
  const allById = new Map(allShows.map(s => [s.id, s.title]));
  const blocked = [];
  const safeToInsertShows = [];
  for (const show of toInsertShows) {
    const existingTitle = allById.get(show.id);
    if (existingTitle !== undefined && existingTitle.toLowerCase() !== show.title.toLowerCase()) {
      blocked.push({ id: show.id, newTitle: show.title, existingTitle });
    } else {
      safeToInsertShows.push(show);
    }
  }
  if (blocked.length) {
    console.error(`Refusing to insert ${blocked.length} show(s) whose id collides with a different existing title:`);
    blocked.forEach(b => console.error(`  - id "${b.id}": import title "${b.newTitle}" vs existing "${b.existingTitle}"`));
    console.error('These were skipped. Resolve manually (e.g. adjust the slug) and re-run.');
  }
  toInsertShows.length = 0;
  toInsertShows.push(...safeToInsertShows);
  // Ratings for blocked shows still reference their (unsaved) generated id,
  // which no longer exists — drop those ratings too so we don't insert
  // orphaned/mismatched rating rows.
  const blockedIds = new Set(blocked.map(b => b.id));
  if (blockedIds.size) {
    for (let i = toInsertRatings.length - 1; i >= 0; i--) {
      if (blockedIds.has(toInsertRatings[i].show_id)) toInsertRatings.splice(i, 1);
    }
  }
}

if (toInsertShows.length) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/shows`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, Prefer: 'resolution=merge-duplicates' },
    body: JSON.stringify(toInsertShows),
  });
  if (!res.ok) {
    console.error(`Failed to insert new shows: ${res.status} ${res.statusText}`);
    console.error(await res.text());
    process.exit(1);
  }
}
if (toInsertRatings.length) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/ratings`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, Prefer: 'resolution=merge-duplicates' },
    body: JSON.stringify(toInsertRatings),
  });
  if (!res.ok) {
    console.error(`Failed to insert ratings: ${res.status} ${res.statusText}`);
    console.error(await res.text());
    process.exit(1);
  }
}

console.log(`Imported ${toInsertRatings.length} ratings, created ${toInsertShows.length} new show rows.`);
if (unmatched.length) {
  console.log('\nCreated as new (no existing title match — review these for accuracy):');
  unmatched.forEach(t => console.log(`  - ${t}`));
}
