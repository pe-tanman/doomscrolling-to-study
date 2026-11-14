// Vercel Function: GET /api/support → public page for the App Store listing.
import { supportHTML } from '../lib/pages.js';

export function GET() {
  return new Response(supportHTML(process.env.SUPPORT_EMAIL), {
    status: 200,
    headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'public, max-age=600, s-maxage=3600' },
  });
}
