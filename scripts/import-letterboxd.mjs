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

async function fetchAllShows() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/shows?select=id,title`, {
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
  });
  return res.json();
}

function slugify(title) {
  return title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
}

const rows = parseCsv(readFileSync(csvPath, 'utf8'));
const existingShows = await fetchAllShows();
const unmatched = [];
const toInsertShows = [];
const toInsertRatings = [];

for (const row of rows) {
  const title = row.Name;
  const rating = parseFloat(row.Rating);
  let match = existingShows.find(s => s.title.toLowerCase() === title.toLowerCase());
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

if (toInsertShows.length) {
  await fetch(`${SUPABASE_URL}/rest/v1/shows`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, Prefer: 'resolution=merge-duplicates' },
    body: JSON.stringify(toInsertShows),
  });
}
if (toInsertRatings.length) {
  await fetch(`${SUPABASE_URL}/rest/v1/ratings`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, Prefer: 'resolution=merge-duplicates' },
    body: JSON.stringify(toInsertRatings),
  });
}

console.log(`Imported ${toInsertRatings.length} ratings, created ${toInsertShows.length} new show rows.`);
if (unmatched.length) {
  console.log('\nCreated as new (no existing title match — review these for accuracy):');
  unmatched.forEach(t => console.log(`  - ${t}`));
}
