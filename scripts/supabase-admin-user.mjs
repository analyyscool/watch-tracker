// scripts/supabase-admin-user.mjs
// Auth Admin API helpers (service-role/secret key, bypasses email flows entirely
// except for `invite` which sends Supabase's own invite email).
// Usage:
//   node scripts/supabase-admin-user.mjs set-password <user-id> <new-password>
//   node scripts/supabase-admin-user.mjs invite <email>
import { readFileSync } from 'node:fs';

const SUPABASE_URL = 'https://ppelaixzzgfhqximihpr.supabase.co';
const serviceKey = readFileSync(new URL('../.supabase-service-key', import.meta.url), 'utf8').trim();

const headers = {
  'Content-Type': 'application/json',
  apikey: serviceKey,
  Authorization: `Bearer ${serviceKey}`,
};

const [, , cmd, ...args] = process.argv;

if (cmd === 'set-password') {
  const [userId, password] = args;
  if (!userId || !password) {
    console.error('Usage: node scripts/supabase-admin-user.mjs set-password <user-id> <new-password>');
    process.exit(1);
  }
  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${userId}`, {
    method: 'PUT',
    headers,
    body: JSON.stringify({ password }),
  });
  const body = await res.json();
  if (!res.ok) { console.error('Failed:', res.status, body); process.exit(1); }
  console.log(`Password set for ${body.email} (${body.id})`);
} else if (cmd === 'invite') {
  const [email] = args;
  if (!email) {
    console.error('Usage: node scripts/supabase-admin-user.mjs invite <email>');
    process.exit(1);
  }
  const res = await fetch(`${SUPABASE_URL}/auth/v1/invite`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ email }),
  });
  const body = await res.json();
  if (!res.ok) { console.error('Failed:', res.status, body); process.exit(1); }
  console.log(`Invite sent to ${email}, user id: ${body.id}`);
} else {
  console.error('Unknown command. Use "set-password" or "invite".');
  process.exit(1);
}
