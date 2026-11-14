// Public pages the App Store listing links to: privacy policy and support.
// Contact address comes from SUPPORT_EMAIL (Vercel env) so it isn't hard-coded in the repo.
const css = `body{font:17px/1.55 -apple-system,system-ui,sans-serif;max-width:720px;margin:0 auto;padding:24px 16px 64px;color:#1d1d1f;background:#fff}
h1{font-size:28px}h2{font-size:20px;margin-top:32px}a{color:#5b3fd6}li{margin:6px 0}
@media (prefers-color-scheme:dark){body{background:#111;color:#eee}a{color:#a99bff}}`;

const page = (title, body) => `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><style>${css}</style></head>
<body>${body}</body></html>`;

const contact = (email) => email
  ? `<a href="mailto:${email}">${email}</a>`
  : 'the support link on Upscroll’s App Store page';

export function privacyHTML(email) {
  return page('Upscroll Privacy Policy', `
<h1>Upscroll Privacy Policy</h1>
<p>Last updated: November 14, 2026</p>
<p>Upscroll teaches Japanese while you watch short videos. This policy explains what the app collects, why, and your choices.</p>

<h2>No account needed</h2>
<p>You can use Upscroll without an account. Your words, progress, streak and settings are stored on your iPhone.</p>

<h2>Optional cloud save</h2>
<p>If you sign in with your email address, we store that email address and your learning progress (words, review schedule, journey and settings) with our database provider, Supabase, so you can restore it on another device. You can delete your account and this data at any time in the app: <em>Settings → Account → Delete account</em>.</p>

<h2>Learning features that use our server</h2>
<ul>
<li><strong>Smart word picks, phrases, grammar and your learning path</strong>: the text of subtitle lines, the candidate words, your learning goal and progress summary are sent to our lesson server and processed by TypeSafe (AI model provider) to choose what to teach. They are not linked to your name or email.</li>
<li><strong>Natural voice</strong>: Japanese words and lines to be read aloud are sent to Google (Gemini text-to-speech). Generated audio may be cached on our server (Vercel) so it can be replayed.</li>
<li><strong>Picture questions</strong>: on Shorts without speech, a still frame of the video on screen is sent to TypeSafe to describe what is shown. Frames are not stored.</li>
</ul>
<p>Our server keeps short-lived technical logs (such as IP address and request time) to prevent abuse and rate-limit requests.</p>

<h2>Microphone and speech recognition</h2>
<p>When you tap the mic to practise saying a phrase, Upscroll uses Apple’s speech recognition. It runs on your iPhone when the device supports it; otherwise Apple processes the audio under <a href="https://www.apple.com/legal/privacy/">Apple’s Privacy Policy</a>. Upscroll does not record or store your voice.</p>

<h2>YouTube</h2>
<p>Upscroll shows YouTube Shorts inside the app. If you sign in to YouTube there, your Google sign-in and YouTube cookies are stored only in the app on your iPhone; Upscroll never sees your password and doesn’t send your cookies to our server. You can sign out at any time in <em>Settings → YouTube → Sign out</em>, which deletes them.</p>
<p>To build subtitles and questions, the app reads the caption tracks and titles of the Shorts you watch. Caption lines are sent to our lesson server as described above. Your watch history isn’t stored on our server.</p>
<p>YouTube’s own handling of data is described in the <a href="https://policies.google.com/privacy">Google Privacy Policy</a>.</p>

<h2>What we don’t do</h2>
<ul>
<li>No advertising, ad tracking or data selling.</li>
<li>No third-party analytics SDKs.</li>
<li>No tracking across other companies’ apps or websites.</li>
</ul>

<h2>Children</h2>
<p>Upscroll is not directed to children under 13 and we do not knowingly collect their personal information.</p>

<h2>Changes and contact</h2>
<p>We’ll update this page if anything changes. Questions or requests: ${contact(email)}.</p>`);
}

export function supportHTML(email) {
  return page('Upscroll Support', `
<h1>Upscroll Support</h1>
<p>Upscroll teaches Japanese while you scroll short videos: real words swap into the subtitles, and quick cards help you remember them.</p>
<h2>Common questions</h2>
<ul>
<li><strong>Do I need an account?</strong> No. Sign in with email only if you want cloud save across devices.</li>
<li><strong>How do I delete my account?</strong> Settings → Account → Delete account. Your cloud data is deleted.</li>
<li><strong>Why don’t some videos have subtitles?</strong> Word-swap subtitles appear on Upscroll lessons and selected videos. Other videos play normally.</li>
<li><strong>The mic doesn’t work.</strong> Allow Microphone and Speech Recognition for Upscroll in the iPhone Settings app.</li>
</ul>
<h2>Contact</h2>
<p>Email ${contact(email)}. We usually reply within a few days.</p>
<p><a href="privacy">Privacy Policy</a></p>`);
}
