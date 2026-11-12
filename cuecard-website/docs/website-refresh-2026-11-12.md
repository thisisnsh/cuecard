# iOS website refresh — November 12, 2026

Implemented locally from the website audit. Nothing has been deployed or pushed.

## Shipped in the source

- Homepage now leads with writing, recording and reviewing on iOS. The existing interactive prompter and screenshots remain. Desktop stays accessible in navigation and its own section.
- Owner-provided download figure: 22K+ total. Shared data records the verification date; the figure is not presented as active users. The separate iOS figure was removed at the owner’s request.
- Help center at `/help/`, with 11 articles, browser-local text search, visible result counts, an empty state, keyboard access, a topic sidebar and a compact footer. All guides and links remain usable without JavaScript. Search queries are not sent to an external search service or logged by the new code.
- Product guides at `/record-video/`, `/voice-following-teleprompter/` and `/teleprompter-mirror/`. The What’s New page was removed at the owner’s request.
- Three articles: `/blog/record-video-while-reading-iphone/`, `/blog/voice-following-vs-fixed-speed/`, `/blog/review-video-takes/`.
- Two older creator posts rewritten at their existing URLs; stale Library, Save, Watch and voice-following statements corrected in other articles and shared page data.
- Product-walkthrough and course-introduction text templates added to the existing script collection. Nine template downloads in total.
- Guides navigation, support shortcuts, product-to-help links, shared software descriptions, sitemap entries and modification metadata updated.

## Validation

- `npm run check:seo`: passed, 96 HTML pages, 92 indexable URLs, 21 articles; metadata, JSON-LD, sitemap, template files and internal links validated.
- `node --check src/script.js` and `git diff --check`: passed.
- Chromium via the existing local Playwright installation: 11 representative routes at 320, 390, 768 and 1440 pixels; no horizontal overflow or browser runtime errors.
- Help search: matching results, zero results, clear/reset, and keyboard navigation from search into a result passed. All 11 article links remain visible without JavaScript; enhanced search is hidden without it.
- Mobile navigation and no-JavaScript Help/product content passed.
- Homepage and all three new product hero CTAs each emit exactly one existing `product_download_click` event with the iOS platform.
- New downloadable templates return text successfully. Desktop/mobile screenshots of homepage, help, recording, guides and templates were inspected.

An initial keyboard test assumed that searching “camera” would make the recording article the first result; the getting-started article also matches. The test was corrected to follow the focused matching result and passed. There was no navigation defect.

## Product evidence and remaining external work

Instructions were checked against sibling iOS source, especially HelpView, SettingsView, TeleprompterView, NoteFolder, TextPack and VoiceFollower. Public App Store / iTunes lookup reported 1.15.0. Voice-following uses on-device speech recognition; Suggestions and Help use an Apple Intelligence model and require its separate availability. No real-device recording, Watch, permissions or AI session was performed here.

Current App Store screenshot assets were inspected, but they still depict older controls and lack the new Library/Takes/AI views. Those downloaded candidates were not retained. Existing imagery remains; a fresh real-device screenshot/demo set is still needed for a later visual update. Do not label the existing images as screenshots of every new feature.

No low-traffic pages were deleted without traffic/backlink evidence. No Search Console indexing requests, analytics account changes, campaign-link creation, localization or production publication were performed. After normal deployment, check live URLs and compare acquisition against the baseline described in `docs/seo-growth.md`.

## Maintaining the new content

- `src/_data/helpArticles.json`: help titles, categories, descriptions, Markdown bodies and actual revision dates.
- `src/_data/productGuides.json`: product guide copy.
- `src/help/` and `src/guides/`: generated layouts and breadcrumbs.
- `src/_data/resources.js`: displayed and downloaded examples share this source.
- `src/script.js`: Help filtering runs only on the Help index.

Keep steps and feature requirements aligned with the app when controls move. Update revision dates only when content changes.
