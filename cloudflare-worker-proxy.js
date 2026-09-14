// CORS proxy for watch-tracker's chapter-check feature (checkNewChapters).
// MangaDex and MangaUpdates both block direct browser-side requests via CORS
// (confirmed live: MangaDex omits Access-Control-Allow-Origin for third-party
// origins, MangaUpdates' preflight returns a flat 403) -- this Worker sits in
// front of both, adding the CORS headers browsers require, and forwards the
// request through unchanged otherwise.
//
// Locked to exactly these two hosts via the path prefix -- /mangadex/... and
// /mangaupdates/... -- so this can't be used as an open relay to arbitrary
// destinations even though its URL is public.
const ALLOWED = {
  mangadex: 'https://api.mangadex.org',
  mangaupdates: 'https://api.mangaupdates.com',
};

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

function withCors(response) {
  const headers = new Headers(response.headers);
  for (const [k, v] of Object.entries(CORS_HEADERS)) headers.set(k, v);
  return new Response(response.body, { status: response.status, headers });
}

export default {
  async fetch(request) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);
    const [, prefix, ...rest] = url.pathname.split('/');
    const base = ALLOWED[prefix];
    if (!base) {
      return withCors(new Response('Unknown proxy target. Use /mangadex/... or /mangaupdates/...', { status: 404 }));
    }

    const targetUrl = `${base}/${rest.join('/')}${url.search}`;
    // MangaDex rejects requests with no real User-Agent (confirmed live:
    // "You must set an appropriate User-Agent header") -- Workers' fetch()
    // doesn't send one by default the way curl or a browser would.
    const init = {
      method: request.method,
      headers: { 'Content-Type': 'application/json', 'User-Agent': 'watch-tracker-proxy/1.0 (personal use)' },
    };
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      init.body = await request.text();
    }

    const res = await fetch(targetUrl, init);
    return withCors(res);
  },
};
