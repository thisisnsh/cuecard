# CueCard website audit — November 12, 2026

## Recommendation

Make iOS the clear lead product and tell the complete workflow: write, rehearse, record, review. Preserve the strong floating-window, cue-card and Apple Watch positioning. First correct help instructions, then refresh the homepage and product pages, then add a small set of substantive search destinations.

Downloads supplied by the owner: 20K on iOS and 22K+ across platforms. These are downloads, not active users or customers. The current shared `downloadTotal` is still 15K+. Use 22K+ globally and a separately labeled 20K iOS downloads figure on iOS pages; keep a verification date with both values.

## Evidence and limits

Reviewed local website templates and data, the sibling iOS HelpView.swift, WhatsNew.json, ScriptSuggestions.swift and public App Store release history. The live homepage still shows 15K+. The current store history shows 1.15.0 camera controls, 1.14.0 collections and beta AI features, and 1.13.0 images, anchors, reading guide and vertical flipping. Older search snippets show obsolete releases: use the current listing and source rather than snippets.

Baseline `npm run check:seo` passes: 78 HTML pages, 74 indexable URLs, 18 articles. This validates metadata, JSON-LD, sitemap and internal links; it does not establish rankings, usability, device compatibility or conversion. No Search Console, GA4 or App Store Connect performance reports were inspected. Design recommendations below concern content hierarchy; no browser visual or performance audit was performed.

## Correct outdated content first

| Location | Finding | Update |
| --- | --- | --- |
| `src/_data/site.js` | 15K+ downloads | Replace with owner-confirmed 22K+; store iOS figure separately. |
| `src/_data/faq.js` | Save/Open/Saved Notes instructions describe the old navigation | Explain the Library, top Save action, drafts and Save as New using current controls. |
| `src/_data/faq.js` | Version history points to a clock at the top | Current help points to the editor version number at the bottom and the menu’s Version History. |
| `src/_data/faq.js` | Backup uses Choose Notes Folder in Saved Notes | Current path is Library → menu → Choose Storage Folder. Explain what the folder preserves and verify history/image handling against storage code. |
| `src/_data/mobileGuides.js`, `src/_data/speaking.js` | Old save paths and Add Cue wording recur | Align instructions with the Library and + Cue controls. Audit every generated page affected by shared data. |
| `src/_data/faq.js` | Sharing described only as text | Explain TextPack for scripts with images; verify supported import types and limits before replacing existing details. |
| `src/_data/features.js`, `src/_data/site.js` | Recording exists, but newer capabilities are mostly absent | Add collections, images, formatting, anchors, reading guide, mirroring, camera settings and beta AI with accurate requirements. Keep software schema consistent with visible copy. |
| Mobile setup guides | External Camera is the default workflow | Offer Record in CueCard and Float over another app as distinct choices. Explain that the floating window does not open while CueCard’s camera is on. |
| Hardware comparison FAQ | Discusses glass mainly as an alternative | Explain CueCard’s horizontal and vertical text flipping for glass rigs. Distinguish this from mirroring the recorded front camera video. |
| Support page | Primarily contact routing | Put self-service tasks and troubleshooting first; retain direct email and bug reporting. |

Retain the distinction between camera video and screen recording: mobile screen recording can include the floating script. Avoid absolute compatibility guarantees for every third-party camera or streaming app. Do not describe choosing an iCloud folder as full account-based synchronization without verifying its behavior.

## Homepage and design direction

Suggested headline: **Your script. Your voice. Your best take.**

Suggested body: **Write your script, record with a teleprompter or cue cards, and review your takes in one free iPhone and iPad app. Float your notes over other apps, or keep your cue cards on Apple Watch.**

Keep a descriptive teleprompter/iPhone page title and eyebrow for visitors and search engines. Primary action: Download for iPhone & iPad. Secondary action: See how it works. Give desktop a clear navigation link and a dedicated lower section.

Recommended order:
1. Outcome, App Store action, accurately labeled download proof and current app imagery.
2. A short real-device demonstration of writing → recording → reviewing a take.
3. Three concrete choices: record in CueCard, float over another app, speak from cards.
4. Strong differentiators: voice-following beta, Watch, Lock Screen, mirror support and local scripts, with relevant limitations next to the claims.
5. Selected templates and useful setup guides.
6. Short installation FAQ, final App Store action and a compact desktop introduction.

The existing interactive prompter is useful for trying scrolling and cards. Keep it as a clearly identifiable demonstration; new screenshots should show the actual Library, recording camera, Takes and voice-follow controls. Replace obsolete screenshots only when current captures exist. Avoid adding another long feature list to an already long homepage. Use focused visual sections with a screenshot, a short explanation and a relevant guide.

Navigation proposal: iPhone & iPad, Apple Watch, Desktop, Guides, Help. Put templates and editorial posts under Guides. Make Help visible without opening the footer. Keep Android discoverable as coming soon while that remains the shipping state, with no equal-weight primary download action.

## New pages worth creating

These are query-intent hypotheses, not measured search-volume estimates. Reuse existing URLs for overlapping topics.

| Priority | URL | Unique job |
| --- | --- | --- |
| First | `/help/` | Searchable, browsable task index with static links and answers available without JavaScript. |
| First | `/record-video/` | Explain recording with script or cards, camera placement, synchronized controls, Photos and Takes; include a real demonstration. |
| Next | `/voice-following-teleprompter/` | Explain Follow Me AI beta, pauses, setup, privacy, supported devices/languages and fallback to fixed-speed scrolling. |
| Next | `/teleprompter-mirror/` | Set up glass, choose horizontal/vertical flipping, and distinguish text mirroring from camera mirroring. |
| Next | `/whats-new/` | Dated, human-readable release notes linking to the relevant help. |

Update `/teleprompter/`, `/cards/`, `/mobile/`, `/mobile/ios/`, `/mobile/ipad/` and `/watch/` before adding alternate pages with nearly identical keywords. Keep social-app guides at their existing URLs. Collections, formatting and Takes need help coverage first; standalone marketing pages can follow if they have enough distinct content and demand.

## Help that resolves a task

Build the first help collection around these concrete articles:

- Getting started: create a script, save it, rehearse and record a first take.
- Record video: permissions, camera controls, pause versus stop, where videos save, and why the script is absent from camera footage.
- Floating window not appearing: correct reading mode, CueCard camera state, Picture in Picture configuration and tested recovery steps.
- Find and manage Takes: Photos access, in-app playback, tags, notes, favorites and albums. State clearly that deleting a take deletes it from Photos too.
- Follow Me AI: enable it, activate it each session, first-word timer behavior, pause/resume, unsupported or unavailable states and fixed-speed fallback.
- Suggestions AI: supported-device requirements, review/accept/reject flow and Settings. Do not imply every iOS 17 device supports it; source gates Apple Intelligence model features on iOS 26 and availability.
- Library and collections: create, rename, organize, duplicate, save and recover a version.
- Storage and sharing: choose a folder, preserve scripts before uninstalling, import text and share images with TextPack.
- Mirror and reading guide: horizontal/vertical flips, anchor jumps and reading-line placement.
- Cards on Lock Screen and Watch: setup, independent Watch decks and image/length limitations.
- Camera settings: actual supported resolution/frame-rate combinations, dynamic range, codec, stabilization and front-camera mirroring; explain device fallback and next-take changes.

Each article needs: a one-sentence answer, supported app/device requirements, exact numbered steps, current screenshots where they disambiguate controls, expected result, symptom-specific fixes, related links and an escalation path. Include a genuinely checked version/date. Verify Follow Me speech availability separately from the Apple Intelligence model availability used by Suggestions and Help.

Keep `/faq/` focused on concise pre-installation questions and link detailed answers into Help. Keep `/support/` as contact/escalation plus common problems. Never recommend reinstalling before explaining preservation of local scripts. Use the existing iOS HelpView as a content inventory, but verify behavior in implementation and on a device rather than blindly copying short in-app explanations.

## Blog and resource work

Publish practical articles with an original script, setup or comparison:

1. **Record a video while reading a script on iPhone** — compare CueCard recording and another camera app; link the recording product page and detailed help.
2. **Voice-following vs fixed-speed teleprompters** — show when each works better, using a sample script with pauses; link the beta requirements.
3. **Mirror your iPhone or iPad for teleprompter glass** — illustrated orientation examples and a short setup test; avoid duplicating the product page’s overview.
4. **Turn one script into several video takes** — use collections, tags and review notes with a concrete example.

Refresh existing eye-line, script-reuse, privacy and creator articles before adding more overlapping posts. Extend `/teleprompter-scripts/` and `/cue-card-templates/` with original examples such as a product demo, course introduction and interview answer where user demand supports them.

Review older promotional posts such as “Deliver Flawless Sales Demos,” “The Ultimate Tool for Seamless Meetings” and the generic product introduction for overlap with existing product/role pages. Rewrite useful pages around actual examples. Consolidate only after checking traffic, backlinks and intent; redirect retired URLs to a close replacement and update internal links and the sitemap. Age alone is not a reason to delete a page. Do not produce another batch of interchangeable profession pages.

Localization is a later opportunity: the app supports five languages, but translated help needs maintained screenshots, correct localized control names and proper language URLs. Prioritize locales using actual acquisition/support data.

## Order and measurement

1. Correct counts and stale setup instructions; synchronize shared descriptions and visible FAQs.
2. Publish the Help hub and highest-impact recording, storage, Takes and floating-window guides.
3. Refresh homepage hierarchy and real screenshots; update the established product pages.
4. Add recording, voice-following and mirror destinations plus a small editorial batch.
5. Use Search Console and acquisition reports to decide consolidation, additional templates and localization.

Preserve the existing product_download_click event. Compare organic landing-page sessions and App Store click-through by page, country and device against a pre-change baseline, then review after 28 and 56 days. App Store Connect measures installs; website outbound clicks do not. Consider help search success, no-result queries and contact clicks, collecting no script contents or sensitive free-text support data.

For implementation, run `npm run check:seo`; inspect affected pages on narrow and wide screens, keyboard navigation, search with/without JavaScript, screenshots and download tracking. Validate real recording, Watch and AI instructions on supported devices. Update sitemap modification dates only for actual changes. No production changes or publishing were performed in this audit.

## Sources

- Website: https://cuecard.dev/
- Current public release history: https://apps.apple.com/jm/app/cuecard-teleprompter/id6757321325
- Google guidance on useful original content: https://developers.google.com/search/docs/fundamentals/creating-helpful-content
- Local product help: `../cuecard-mobile/ios/CueCard/CueCard/Views/HelpView.swift`
- AI model availability: `../cuecard-mobile/ios/CueCard/CueCard/Services/ScriptSuggestions.swift`
- Existing acquisition work and measurement gaps: `docs/seo-growth.md`
