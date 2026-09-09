# CueCard Website

Eleventy/Nunjucks static site for [cuecard.dev](https://cuecard.dev).

## Page responsibilities

- `/` introduces the free floating teleprompter and offers equally clear mobile and desktop paths.
- `/mobile/` explains choosing and setting up a mobile recording workflow.
- `/mobile/ios/` covers the iPhone overlay, controls, positioning and troubleshooting.
- `/mobile/ipad/` covers full-screen reading beside a camera and floating notes on iPad.
- Social-app pages under `/mobile/` provide written setup, a sample script and troubleshooting. TikTok, Instagram, Snapchat, YouTube, LinkedIn, Facebook, X and Twitch have distinct workflows. Camera-roll recording is described where it provides the reusable video workflow.
- `/desktop/` covers private speaker notes on Mac and Windows. `/zoom/`, `/google-meet/`, `/microsoft-teams/` and `/google-slides/` retain their dedicated meeting and Slides content.
- Mobile audience pages include a role-specific filming workflow and usable example script. Articles focus on delivery, eye-line and reusing scripts, with links to setup instructions.

All 59 existing sitemap URLs and the `/ios/` and `/android/` shortlinks remain.

## Develop and verify

```sh
npm ci
npm start          # http://localhost:8080/
npm run check      # build, Node regression tests, Python 3 HTML crawl
```

`src/` is the input; `_site/` is generated and ignored by Git. `.eleventy.js` configures filters and static assets. Shared layouts and partials live in `src/_includes/`; page content lives in `src/_data/`. The design uses existing typography, cards, ruled feature rows, device screenshots and an interactive demonstration.

`npm test` covers conditional offers, safe JSON-LD, missing/invalid/valid tutorial links, download events and actual dynamically generated installer cards. The analytics stub runs the website script in a Node VM; it is not an end-to-end browser test.

`tests/check-site.py` checks generated HTML without JavaScript: meaningful single H1s, unique titles/descriptions, self-canonicals, JSON-LD parsing, FAQ parity, availability, internal routes and anchors, and deployment-required files. It also asserts 59 sitemap URLs so a route change receives deliberate review.

## Product facts and structured data

`src/_data/site.js` owns `products.mobile` and `products.desktop`: stable entity IDs, names, price, currency, platform shipping flags, supported OS versions and store/release URLs. Download groups and requirements derive from these facts. The Android display flag in app data only controls coming-soon copy; it does not make Android available.

`lib/content.js` builds software entities from shipping platforms and serializes JSON-LD safely, including feature strings containing quotes or HTML delimiters. Mobile device, social and audience pages describe the same `https://cuecard.dev/#mobileapp` entity. Desktop pages use `https://cuecard.dev/#desktopapp`. Android has no shipping OS, install URL or InStock offer. Breadcrumbs and page-specific FAQs remain separate.

The released iOS/iPadOS minimum was checked on 2026-09-08: the [App Store listing](https://apps.apple.com/us/app/cuecard-teleprompter/id6757321325) and the iOS app target's Debug/Release settings both say 16.6. Project-level settings say 17.0; the app target overrides them. Desktop requirements refer to the separate desktop app, not the iOS app's compatibility on Apple Silicon Macs.

Current CueCard guide labels were checked against sibling app source:

- `cuecard-mobile/ios/CueCard/CueCard/Views/HomeView.swift`: New Note, Import from File, Save as New, green play button.
- `Views/SettingsView.swift`: Start Delay, Scroll Speed (lines/min), Text Size under In-App Prompter and Floating Prompter, Dimension Ratio.
- `Views/TeleprompterView.swift` and `Services/TeleprompterPiPManager.swift`: Start Overlay, play/pause, restart and floating-window behavior. Start Delay begins from fresh full-screen playback; floating play/pause resumes directly.

These are source-verified instructions, not a claim of device testing. Cue tags are visual reminders; they do not pause playback. Scrolling uses a set speed, not speech recognition. A camera recording excludes the screen overlay; a screen recording or screen broadcast can include it.

Third-party controls were checked against [TikTok recording help](https://support.tiktok.com/en/using-tiktok/creating-videos/tiktok-stories) and [Snapchat's camera instructions](https://help.snapchat.com/hc/en-us/articles/7012326414612-How-do-I-create-a-Snap). Instagram's current Help Center page was access-blocked; the guide deliberately describes the Reel camera without asserting a specific button location. Other workflows avoid version-specific control labels. Recheck these flows on devices before release.

## Optional tutorial videos

Edit the matching object in `src/_data/apps.json`, such as `slug: "mobile/tiktok"` or `slug: "mobile/instagram"`:

```json
"tutorial": {
  "youtubeUrl": "",
  "label": "Watch the TikTok tutorial on YouTube"
}
```

Set `youtubeUrl` to the supplied HTTPS YouTube video URL and rebuild. Use “Watch the Instagram tutorial on YouTube” for Instagram. Production tutorial URLs are empty until supplied. The renderer accepts ordinary YouTube watch, Shorts and youtu.be video URLs with a valid video-ID shape; it does not verify video existence. Missing or invalid URLs produce no link, wrapper, disabled button or extra spacing. Once a real tutorial is supplied, update the production-empty assertion in the crawl test as part of that change.

`partials/tutorial-link.njk` renders an accessible link beside the written guide in `partials/setup-guide.njk`. Written instructions remain. `site.demos` retains the existing iPhone, iPad and desktop films, clearly labeled as general product demos. No video player or iframe loads on the page.

## Articles

`src/_data/blogs.json` supports `description` and `modified`. Description falls back to the existing first-paragraph excerpt when omitted. Keep the original `datetime` (publication date); set `modified` only for substantive changes. The post's visible updated date, BlogPosting `dateModified`, and sitemap `lastmod` use it consistently. Article metadata and social descriptions use the explicit description when provided.

## Download measurement

The existing GA4 property receives one `product_download_click` per tagged store, installer or installer-release destination click. A delegated handler in `src/script.js` covers nested icons and installer links created after releases load. It never prevents navigation, waits for delivery, or requires analytics to be available.

Static templates and generated installer links use explicit attributes:

```html
<a href="https://apps.apple.com/app/cuecard-teleprompter/id6757321325"
   data-product-platform="ios"
   data-cta-location="hero"
   data-destination-type="app_store">Get CueCard</a>
```

| Event field | Values |
| --- | --- |
| `product_platform` | `ios`, `macos`, `windows` |
| `cta_location` | `hero`, `navigation`, `download_section`, `article` |
| `page_path` | Current pathname, excluding query and fragment |
| `destination_type` | `app_store`, `installer`, `releases` |

Internal `#download` navigation, Android information pages, extension downloads, source links and release-note links are excluded. The desktop download section includes explicit Mac and Windows installer-release links that work without JavaScript. A click measures download intent; it is not an observed installation. The custom event does not include script text or user-entered content.

With GA4 access:

1. Enable debug mode for a test session using your usual Google Analytics debugger. Inspect DebugView for `product_download_click`; verify exactly one event and the four fields for a tagged App Store link, a desktop installer, and a fallback release link. Verify internal and Android navigation produces none.
2. Register event-scoped custom dimensions for `product_platform`, `cta_location` and `destination_type`; use the existing page path dimension where possible. Inspect the explicit `page_path` parameter in DebugView or exports. [GA4 custom dimension guidance](https://support.google.com/analytics/answer/14240153).
3. Optionally mark `product_download_click` as a key event. Allow normal reporting processing time after configuration.
4. Enhanced-measurement outbound `click` events may also describe the same action. Filter reports to `product_download_click`; do not add outbound clicks to it.
5. Compare date, landing page, page path, device category, country, session source/medium, product platform, CTA location and destination type. Show sessions, users, download-click events and sessions with download intent. Use sessions with intent / sessions for a session conversion rate; raw clicks can include repeat clicks.

For App Store acquisition reporting, create a campaign link in App Store Connect and use its generated URL as the mobile platform's `storeUrl` in `site.js`. Keep its campaign name in the reporting notes. Compare campaign acquisition aggregates with website intent over the same dates; the site cannot match an individual click to an installation. Apple's [campaign-link guidance](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links) explains its attribution rules and reporting requirements.

## Search baseline and follow-up

Account access is required for these operational steps:

- Export Search Console performance by query, page, device and country before launch.
- Record indexing status and Google-selected canonical for the homepage, product overviews, device pages and social guides.
- Group branded, mobile, iPhone, iPad, social-app and desktop queries.
- Record mobile Core Web Vitals when field data is available.
- Compare the first 28 days after launch with a suitable prior period, accounting for seasonality and launch timing.
- Review impressions, clicks, CTR and download intent together. Page overlap alone does not establish ranking cannibalization.

## Release and review

A push to `main` touching this website runs the existing `.github/workflows/deploy-website.yml` and publishes to GitHub Pages. A pull request builds and verifies output without deploying. Keep changes reviewable before merging. The workflow checks `index.html`, `404.html`, `CNAME`, both shortlinks, and the absence of PHP; `npm run check` includes these checks plus the content regressions.

Before release, review `/`, `/mobile/`, `/mobile/ios/`, `/mobile/ipad/`, `/mobile/tiktok/`, `/mobile/instagram/`, `/mobile/snapchat/` and `/desktop/` at narrow and wide widths. Check wrapping, guide readability, menu and download links, keyboard focus, interactive demo controls, existing demo destinations and tutorial spacing with a valid fixture. Repeat guide navigation and download access with JavaScript disabled.

The implementation session had no connected browser, so viewport screenshots and interactive browser checks remain outstanding. GA4, Search Console and App Store Connect reporting setup also remains account-dependent. No device-tested or live-analytics validation is claimed.
