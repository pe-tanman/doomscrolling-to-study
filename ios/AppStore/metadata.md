# App Store Connect: Upscroll 1.0.0 (web wrapper build, branch `sideload`)

Paste these into App Store Connect ▸ your app.

## App information
- **Name:** Upscroll
- **Subtitle (30):** Learn Japanese while you scroll
- **Bundle ID:** com.upscroll.app
- **Primary category:** Education · **Secondary:** Entertainment
- **Content rights:** Apple asks "Does your app contain, show, or access third-party content?" → **Yes**, then "Do you have all necessary rights?" Only you can answer this, and it has to be true. This build shows the YouTube mobile website and reads its captions, and YouTube hasn't given permission for that. Answering "No" or being unable to show rights usually means rejection under 5.2.2.
- **Age rating:** "Unrestricted Web Access": **Yes**. The app shows the full YouTube mobile site, including search, so expect **18+** unless that changes.
- **Privacy Policy URL:** https://upscroll-lesson.vercel.app/api/privacy
- **Support URL:** https://upscroll-lesson.vercel.app/api/support
- **Price:** Free

## Version 1.0.0
**Promotional text (170):**
Turn your scrolling into Japanese practice. Real Japanese words appear right in the subtitles, and quick cards help them stick.

**Description:**
Upscroll turns short videos into Japanese lessons.

Scroll your own Shorts feed like always. As the videos play, Upscroll swaps a few words in the subtitles for Japanese and pauses for a quick card when a new word appears. Hear it, read it, pick the meaning, say it out loud.

• Words in context: learn つかれた from someone who is actually tired
• Picture questions: "what's this?" in Japanese, about what's on screen
• Phrases and patterns: build real sentences, not just single words
• Spaced review: words come back just before you'd forget them
• Kana practice for beginners, with romaji help
• Your journey: a map of places in Japan that unlocks as you learn
• A daily screen-time limit that ends with a recap of what you learned

No account needed. Sign in with email only if you want cloud save.

Upscroll is not affiliated with or endorsed by YouTube or Google.

**Keywords (100):**
japanese,learn japanese,hiragana,katakana,kana,vocabulary,jlpt,shorts,language,study,flashcards,anime

**What's New:** First release.

## App Privacy (nutrition label)
Data used to track you: **None**.
Data linked to you:
- **Contact Info ▸ Email Address**: App Functionality (only if the user signs in for cloud save)
- **User Content ▸ Other User Content** (learning progress): App Functionality
Data not linked to you:
- **Identifiers ▸ Device ID** (random per-install id, for daily usage limits): App Functionality
- **Usage Data ▸ Other Usage Data** (caption lines of watched Shorts, chosen words, video frames sent to the lesson server): App Functionality
Not collected by Upscroll: YouTube/Google credentials (sign-in happens on Google's own pages, and cookies stay on the device), location, contacts, identifiers, audio.

## App Review information
**Sign-in required:** No. (YouTube sign-in and cloud save are both optional.)

**Notes for the reviewer** (keep these accurate; misleading notes violate guideline 2.3.1):
Upscroll is a Japanese learning app. It shows the YouTube Shorts mobile website in a web view and adds a learning layer: some words in the captions are swapped for Japanese, and short practice cards appear between clips. Swipe through Shorts as usual and tap the あ button for the learning dashboard. Signing in to YouTube is optional (Settings ▸ YouTube). Account deletion for cloud save: Settings ▸ Account ▸ Delete account.

## Screenshots
Required: 6.9" (1320 × 2868). The iPhone 18 Pro simulator gives 1206 × 2622, which has the same aspect ratio. Scale with:
`sips -z 2868 1320 shot.png --out shot-6.9.png`
- Don't show the YouTube logo, its interface, or other creators' videos. Apple rejects screenshots with third-party trademarks or content (2.3.7, 5.2.1).
- Use your own footage or Upscroll lesson videos behind the learning layer, or the native screens: word card, picture question, journey map, words dashboard, review.
- Use a clean simulator (Device ▸ Erase All Content and Settings) so test data like "493/20 min" doesn't show.
