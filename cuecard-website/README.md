# CueCard Website

Static site that powers [cuecard.dev](https://cuecard.dev).

The site leads with **CueCard Mobile** — the teleprompter that floats over
every other app on a phone. The Mac and Windows app, which keeps speaker notes
invisible during screen sharing, keeps its own home at `/desktop/` along with
every URL it already ranks for. Nothing was retired in that move: `/zoom/`,
`/google-meet/`, `/microsoft-teams/`, `/google-slides/` and all twelve desktop
role pages are exactly where they were.

## Purpose

- Positions both apps, and sends readers between them from the nav, the body
  copy and the footer
- One page per app CueCard is read over (`/mobile/instagram/`, `/mobile/tiktok/`
  …) and per app it hides from (`/zoom/`, `/microsoft-teams/` …)
- One page per role, on each side: `/teachers/` and `/mobile/teachers/`
- A 43-question FAQ at `/faq/`, with every page carrying the subset that fits it
- Hosts the privacy policy (`privacy/`) and terms of service (`terms/`)
- Provides download links to GitHub Releases and the App Store

## Structure

```
cuecard-website/
├── .eleventy.js       # 11ty config (input src/, output _site/)
├── src/
│   ├── index.njk      # The mobile app, and the bridge to the desktop one
│   ├── desktop/       # The Mac and Windows app
│   ├── faq.njk        # The whole FAQ bank, grouped
│   ├── styles.css     # Editorial monochrome: hairlines, micro-labels, no boxes
│   ├── script.js      # Background reel, video facade, nav, FAQ search, releases
│   ├── shortlink.njk  # Generates /ios and /android redirect pages
│   ├── sitemap.xml.njk# Generated from the data files, so it cannot drift
│   ├── CNAME          # Custom domain for GitHub Pages
│   ├── _data/
│   │   ├── site.js            # Every shared constant: URLs, video, app lists
│   │   ├── features.js        # Feature rows, mobile and desktop
│   │   ├── faq.js             # The FAQ bank and the helpers that slice it
│   │   └── *.json             # Page content: apps, platforms, roles, blogs
│   ├── _includes/
│   │   ├── layouts/           # base.njk carries the head and the JSON-LD graph
│   │   └── partials/          # hero, rows, applist, rolegrid, faq, cta, footer
│   ├── assets/        # Favicons, manifest, screenshots, poster
│   ├── privacy.njk    # Privacy policy
│   └── terms.njk      # Terms of service
└── _site/             # Build output (gitignored)
```

The site is fully static — no PHP, no server-side anything — so it can be served
by any static host.

## The background reel

Every page scrolls over a fixed background layer. Today that layer is a still
(`src/assets/cuecard-poster.png`), blurred and knocked back so it reads as
atmosphere behind the type.

To turn the video on, drop `promo.mp4` and `promo.webm` into `src/assets/` and
set `video.enabled: true` in `src/_data/site.js`. Until then no `<video>` element
is emitted at all, so there is nothing to 404. The poster stays underneath the
video either way, which is what the crossfade fades up from.

## The demo videos

`src/_data/site.js` holds two YouTube entries, `youtube.mobile` and
`youtube.desktop`. They drive the play buttons, the poster frames and the
`VideoObject` blocks. `youtube.mobile` is marked `placeholder: true` and
currently points at the existing reel — swap its `id`, `title`, `uploadDate` and
`duration` and every page follows.

## Local Preview

```bash
npm ci
npm start
```

Then open the URL 11ty prints (`http://localhost:8080/` by default). The dev
server rebuilds on save.

## Build & Deploy

**Pushing does not publish.** A push to `main` (or a pull request) runs
`.github/workflows/deploy-website.yml` as CI: it installs, builds and verifies
the output, and stops there. Nothing reaches cuecard.dev.

Publishing is a deliberate action: **Actions → Deploy Website → Run workflow**,
leaving the `publish` input on. That is the only event that reaches the deploy
job.

To build locally:

```bash
npm ci
npm run build   # writes _site/
```

## Notes

- `src/_data/site.js` is the single source of truth for URLs, store links, the
  app lists and the year. Change it there, not in a template
- Icons live in `src/_includes/partials/icon-sprite.njk` as `<symbol>`s and are
  used through the `icon()` macro in `partials/icons.njk`
- Update `assets/site.webmanifest` and the favicons when branding changes
- Keep privacy/terms copies in sync with the legal docs used inside the apps
- `src/CNAME` pins the custom domain. Removing it reverts the site to the
  `github.io` host on the next deploy
- GitHub Pages serves `404.html` natively and handles apex/www plus HTTPS, so
  the site carries no `.htaccess` or `_redirects` file. Add new shortlinks
  (like `/ios` and `/android`) to `src/_data/shortlinks.json` instead
