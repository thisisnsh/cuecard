# CueCard Website

Static site that powers [cuecard.dev](https://cuecard.dev).

Three pages carry the product. `/` is the landing page: it says what CueCard is,
forks to both halves, and holds **the download hub** — every platform CueCard
ships on, as a row apiece with its own button. `/mobile/` is the teleprompter
that floats over every other app on a phone. `/desktop/` is the Mac and Windows
app that keeps speaker notes invisible during screen sharing, along with every
URL it already ranks for: `/zoom/`, `/google-meet/`, `/microsoft-teams/`,
`/google-slides/` and all twelve desktop role pages are exactly where they were.

## Purpose

- Positions both apps, and sends readers between them from the nav, the body
  copy and the footer
- One page per app CueCard is read over (`/mobile/instagram/`, `/mobile/tiktok/`
  …) and per app it hides from (`/zoom/`, `/microsoft-teams/` …)
- One page per role, on each side: `/teachers/` and `/mobile/teachers/`
- A 43-question FAQ at `/faq/`, with every page carrying the subset that fits it
- Hosts the privacy policy (`privacy/`) and terms of service (`terms/`)
- One download hub at `/#download`, generated from `site.downloadGroups`, which
  is also what the header's download menu prints

## Structure

```
cuecard-website/
├── .eleventy.js       # 11ty config (input src/, output _site/)
├── src/
│   ├── index.njk      # The landing page: what CueCard is, and the download hub
│   ├── desktop/       # The Mac and Windows app
│   ├── faq.njk        # The whole FAQ bank, grouped
│   ├── styles.css     # Editorial monochrome: hairlines, micro-labels, no boxes
│   ├── script.js      # Background reel, nav, download menu, FAQ search, releases
│   ├── shortlink.njk  # Generates /ios and /android redirect pages
│   ├── sitemap.xml.njk# Generated from the data files, so it cannot drift
│   ├── CNAME          # Custom domain for GitHub Pages
│   ├── _data/
│   │   ├── site.js            # Every shared constant: URLs, video, downloads,
│   │   │                      #   app lists, and the hand-written download total
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

There is no video *player* anywhere on this site. The film is a fixed layer that
every page scrolls over: a poster frame paints with the first paint, and the
reel fades up over it once it can play. Both are knocked back and blurred behind
a scrim, so they read as atmosphere rather than as something to watch.

It is configured entirely by `video` in `src/_data/site.js`.

**The reel running today is borrowed** — it is the
alldayidreamaboutsports.com promo, standing in until CueCard's own film is cut,
which is what `placeholder: true` records. To swap it in:

1. Encode three files — an MP4, a WebM and a first-frame poster. The recipe in
   `alldayidreamaboutsports.com/scripts/encode-promo.sh` is the one these were
   made with (H.264 ~2.5 Mbps, VP9 ~1.8 Mbps, a WebP still).
2. Host them anywhere with a custom domain and cache rules — an R2 bucket does
   it — and point `video.mp4`, `video.webm`, `video.poster` and `video.origin`
   at them. `posterWidth`/`posterHeight` must match the poster, or the page
   reflows when it loads.
3. Fill in `video.schema` and set `placeholder: false`.

Step 3 is what starts emitting a `VideoObject` on every page. While
`placeholder` is true, nothing is marked up — describing someone else's footage
as CueCard's in structured data would be a lie, and Google reads it as one.

## The download hub

`site.downloadGroups` in `src/_data/site.js` is the one list of everywhere
CueCard can be had, grouped by the machine you are on. It is printed in three
places and edited in one:

- the header's **Download, it's free** menu (`partials/downloadmenu.njk`)
- the `/#download` section on the landing page (`partials/getcuecard.njk`)
- the `ItemList` in the landing page's structured data

Adding a platform means adding an entry there and nothing else.

The **download total** beside it (`site.downloadTotal`, currently `"1,100+"`) is
a hand-written string, and deliberately so: the GitHub API only counts desktop
release assets, so any computed figure would leave out the App Store entirely.
Edit the string and every page follows. The GitHub star count next to it *is*
live, fetched through the Cloudflare proxy in `api/`.

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
  used through the `icon()` macro in `partials/icons.njk`. Every section label
  carries one; add the symbol first, then name it
- The header's action button is identical on every page on purpose. It used to
  be per-page, and the masthead visibly reflowed on every navigation
- Update `assets/site.webmanifest` and the favicons when branding changes
- Keep privacy/terms copies in sync with the legal docs used inside the apps
- `src/CNAME` pins the custom domain. Removing it reverts the site to the
  `github.io` host on the next deploy
- GitHub Pages serves `404.html` natively and handles apex/www plus HTTPS, so
  the site carries no `.htaccess` or `_redirects` file. Add new shortlinks
  (like `/ios` and `/android`) to `src/_data/shortlinks.json` instead
