// Local dev server: `npm run dev` (loads ../.env) → http://localhost:8787/api/lesson
// `node dev.js --mock`: fake Jev answers, no TypeSafe key needed (never used by the deployed function).
import http from 'node:http';
import { POST } from './api/lesson.js';
import { POST as reactionPOST } from './api/reaction.js';
import { POST as picturePOST } from './api/picture.js';
import { POST as ttsPOST } from './api/tts.js';
import { POST as phrasePOST } from './api/phrase.js';
import { POST as pathPOST } from './api/path.js';
import { POST as grammarPOST } from './api/grammar.js';
import { GET as lessonsGET } from './api/lessons.js';
import { GET as feedGET } from './api/feed.js';
import { GET as playerGET } from './api/player.js';
import { lesson } from './lib/lesson.js';
import { verify } from './lib/auth.js';

const port = Number(process.env.PORT) || 8787;
const mock = process.argv.includes('--mock');

const fakeFetch = async (_url, init) => {
  const q = JSON.parse(init.body).questions;
  const answers = Object.fromEntries(Object.keys(q).map((k, n) => [k, { type: 'noul', noul: k.startsWith('sense') ? 0.9 : 0.5 + ((n * 37) % 50) / 100 }]));
  return new Response(JSON.stringify({ model: 'mock-jev', answers, usage: { input_tokens: 0, output_tokens: 0 } }));
};

async function mockPOST(request) {
  const body = await request.text();
  const denied = verify(request.headers, body);
  if (denied) return new Response(JSON.stringify({ error: denied.error }), { status: denied.status });
  return new Response(JSON.stringify(await lesson(JSON.parse(body), { apiKey: 'mock', fetchImpl: fakeFetch })));
}

http.createServer(async (req, res) => {
  const t = Date.now();
  res.on('finish', () => console.log(`${req.method} ${req.url} ${res.statusCode} ${Date.now() - t}ms`));
  if (req.url === '/health') return res.end(JSON.stringify({ ok: true, key: Boolean(process.env.TYPESAFE_API_KEY), signed: Boolean(process.env.DS_APP_SECRET), speech: Boolean(process.env.FAL_KEY || process.env.GEMINI_API_KEY) }));
  const isReaction = req.url?.startsWith('/api/reaction');
  const isPicture = req.url?.startsWith('/api/picture');
  const isTTS = req.url?.startsWith('/api/tts');
  const isPhrase = req.url?.startsWith('/api/phrase');
  const isPath = req.url?.startsWith('/api/path');
  const isGrammar = req.url?.startsWith('/api/grammar');
  if (req.url?.startsWith('/api/feed') && req.method === 'GET') {
    const r = await feedGET(new Request(`http://localhost${req.url}`)); res.setHeader('content-type', 'application/json'); return res.end(await r.text());
  }
  if (req.url?.startsWith('/api/player') && req.method === 'GET') {
    const r = playerGET(); res.setHeader('content-type', 'text/html; charset=utf-8'); return res.end(await r.text());
  }
  if (req.url?.startsWith('/api/lessons') && req.method === 'GET') {
    const r = lessonsGET(); res.setHeader('content-type', 'application/json'); return res.end(await r.text());
  }
  if (!req.url?.startsWith('/api/lesson') && !isReaction && !isPicture && !isTTS && !isPhrase && !isPath && !isGrammar) { res.statusCode = 404; return res.end('not found'); }
  if (req.method !== 'POST') { res.statusCode = 405; return res.end(); }

  let data = '';
  for await (const c of req) data += c;
  const request = new Request(`http://localhost${req.url}`, { method: 'POST', headers: req.headers, body: data });
  const response = await (isGrammar ? grammarPOST : isPhrase ? phrasePOST : isPath ? pathPOST : isTTS ? ttsPOST : isPicture ? picturePOST : isReaction ? reactionPOST : (mock ? mockPOST : POST))(request);
  res.statusCode = response.status;
  res.setHeader('content-type', response.headers.get('content-type') || 'application/json');
  res.end(Buffer.from(await response.arrayBuffer()));
}).listen(port, () => console.log(`lesson server on http://localhost:${port} ${mock ? '(MOCK Jev)' : `(TypeSafe key ${process.env.TYPESAFE_API_KEY ? 'set' : 'MISSING'})`}, signing ${process.env.DS_APP_SECRET ? 'required' : 'OFF (no DS_APP_SECRET)'}`));
