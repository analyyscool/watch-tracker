// scripts/supabase-write.mjs
// Usage: node scripts/supabase-write.mjs <table> '<json array of rows>'
// Upserts rows into the given table using the service-role key, bypassing RLS.
import { readFileSync } from 'node:fs';

const SUPABASE_URL = 'https://ppelaixzzgfhqximihpr.supabase.co';
const serviceKey = readFileSync(new URL('../.supabase-service-key', import.meta.url), 'utf8').trim();

const [, , table, rowsJson] = process.argv;
if (!table || !rowsJson) {
  console.error('Usage: node scripts/supabase-write.mjs <table> \'<json array of rows>\'');
  process.exit(1);
}

const rows = JSON.parse(rowsJson);

const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    Prefer: 'resolution=merge-duplicates,return=representation',
  },
  body: JSON.stringify(rows),
});

const body = await res.json();
if (!res.ok) {
  console.error('Supabase write failed:', res.status, body);
  process.exit(1);
}
console.log(JSON.stringify(body, null, 2));
