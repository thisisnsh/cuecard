# Search acquisition changes — October 21, 2026

CueCard already had Instagram, Snapchat, TikTok and other social guides. This change strengthens those established URLs and adds two useful resource collections. Query groups below describe page intent, not measured search volume or ranking forecasts. Search Console and App Store Connect data were not available in this session.

| Query intent | Primary page | What visitors can do |
| --- | --- | --- |
| Free teleprompter / cue cards app | `/` | Understand both modes and download for their device |
| Instagram teleprompter / Reels teleprompter | `/mobile/instagram/` | Follow setup, resolve overlay issues and find a Reel script |
| Snapchat teleprompter | `/mobile/snapchat/` | Record a Snap with floating notes and find a Story script |
| TikTok teleprompter | `/mobile/tiktok/` | Prepare and record a short video with a floating script |
| YouTube teleprompter / Shorts | `/mobile/youtube/` | Choose a Shorts or camera-roll workflow |
| Teleprompter script template / Reel script examples | `/teleprompter-scripts/` | Copy or download four original, editable scripts |
| Cue card template / speech cue cards examples | `/cue-card-templates/` | Download three decks for a wedding, class presentation or talk |
| Cue cards app / digital cue cards | `/cards/` | Learn Cards mode and follow setup for screen, Lock Screen and watch |

The script and card collections serve different needs from product setup and editorial delivery tips. They link to those existing pages, and the homepage, footer, product pages and relevant articles link back. Do not add alternate Instagram or Snapchat landing pages that repeat the existing guide under another keyword-shaped URL.

Implementation includes descriptive social titles and headings, platform-specific introductory copy, earlier setup instructions, compatibility answers, and dated sitemap entries for materially revised guides. Downloads and visible examples come from the same data. The homepage keeps its early app-download section before the new creator-guide links. App Store buttons on the new pages use the existing `product_download_click` measurement; template downloads are not counted as app downloads.

## Validate after publication

1. Confirm that the two resource URLs, their seven text files, and the revised social pages return successful responses on `https://cuecard.dev`. Inspect titles, canonical URLs and rendered body content on the published pages.
2. In Google Search Console, inspect `/`, `/mobile/instagram/`, `/mobile/snapchat/`, `/teleprompter-scripts/` and `/cue-card-templates/`. Confirm crawl access and the Google-selected canonical. Submit `https://cuecard.dev/sitemap.xml` if it is not already registered; request indexing for the new resources.
3. Export a pre-release baseline by query, landing page, country and device. Review the intent groups above after 28 days, then again after 56 days. Separate branded searches from nonbranded discovery. Compare impressions, clicks, CTR and positions alongside sessions and download intent; avoid attributing seasonal changes to this release alone.
4. Verify the existing `product_download_click` event in GA4 DebugView. Compare organic landing-page sessions with sessions containing an app-download click. Template downloads are useful engagement, but are not app installations.
5. Use App Store Connect acquisition reports to assess actual downloads. If campaign attribution is needed, generate a campaign link in App Store Connect and update the shared store URL with that real link. Do not invent campaign tokens or equate a website click with an install.

These account operations remain outstanding; no indexing request, campaign-link creation or analytics configuration was performed. The source changes need deployment before any of them can affect live acquisition.

## Next content work, guided by evidence

- If social guides gain impressions but few clicks, compare the actual query with the title and visible answer before creating more pages.
- If readers arrive but do not download, test the page on the devices they use. Android traffic cannot convert to an Android installation while that version is unavailable.
- Record short, real-device Instagram and Snapchat setup demonstrations and populate the existing tutorial URL fields. Verify the app controls on the device used in the recording.
- Add templates when users request specific scenarios or search data shows a need. Give each one an original, usable example and a relevant product workflow.
- Pursue mentions through useful examples, accurate product information and actual user experience. Do not publish unverified “#1,” “leading,” rating or review claims.

## Sources checked

- [Google: helpful, reliable, people-first content](https://developers.google.com/search/docs/fundamentals/creating-helpful-content)
- [Google: general structured data guidelines](https://developers.google.com/search/docs/appearance/structured-data/sd-policies)
- [Google: software app structured data](https://developers.google.com/search/docs/appearance/structured-data/software-app)
- [CueCard's public App Store listing](https://apps.apple.com/us/app/cuecard-teleprompter/id6757321325)

The public App Store listing confirms the two modes, floating scripts, Apple Watch support and free pricing. Imported card separators and limits were checked in the sibling iOS source. Local web checks do not establish real-device recording compatibility or a ranking improvement.

## Local validation

- `npm run check:seo`: 78 HTML pages, 74 indexable canonical URLs and 18 articles passed; all seven template files exist, and starting cards fit the 120-character limit.
- Chromium: seven representative pages checked at 320, 390, 768 and 1440 pixels, with no horizontal overflow. Final resource and Instagram/Snapchat pages rechecked at narrow and wide sizes; mobile and desktop screenshots inspected.
- All seven browser downloads matched their source examples, including card separators. Resource hero App Store clicks each emitted exactly one download-intent event.
- Both resources and the Instagram/Snapchat guides retained visible app download links without JavaScript. The resources retained their template downloads, and social setup sections followed their heroes. No browser runtime errors were observed.
