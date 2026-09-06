# CueCard Website

Static site that powers [cuecard.dev](https://cuecard.dev).

**The phone is the product.** `/` is CueCard Teleprompter on iPhone and iPad —
the floating prompter, the App Store artwork, the demos. `/mobile/` and the
pages beneath it are the same argument per device and per app you film in.
`/desktop/` is the Mac and Windows app that keeps speaker notes invisible
during screen sharing; it is kept whole because it ranks, but on every phone
page it appears as one card rather than half the page. Every URL that existed
before still exists: `/zoom/`, `/google-meet/`, `/microsoft-teams/`,
`/google-slides/` and all twenty-four role pages are exactly where they were,
with `/mobile/ipad/` and `/mobile/twitch/` added.

## The two section designs

Everything on the site is one of two objects, which is what keeps thirty-odd
pages looking like one site:

- **Ledger** — an eyebrow label on a hairline, a heading, one short lede, then
  ruled rows. `partials/rows.njk` (numbered features), `partials/applist.njk`
  (apps), `partials/rolegrid.njk` (roles), `partials/getcuecard.njk`
  (downloads) and `partials/faq.njk` are all this.
- **Card** — a bordered panel on tinted paper, for things that are objects
  rather than lists. `partials/deck.njk` (the live prompter),
  `partials/shots.njk` (the App Store artwork), `partials/watch.njk` (the demo
  links), `partials/crosspanel.njk` and `partials/bigscreen.njk` (the other
  half of the product, and the iPad) are all this.

Sections alternate between plain paper and a tint — pass `solid` — and that
alternation is the whole page rhythm. Sections are short on purpose: each says
one thing, and none of them gets a screen and a half to say it.

## Purpose

- Leads with the phone everywhere, and still sends readers to the desktop app
  from the nav strip, one card per page and the footer
- One page per app CueCard is read over (`/mobile/instagram/`, `/mobile/tiktok/`
  …) and per app it hides from (`/zoom/`, `/microsoft-teams/` …)
- One page per role, on each side: `/teachers/` and `/mobile/teachers/`
- A 44-question FAQ at `/faq/`; every other page carries a short curated subset
  (`faq.home`, `faq.desktopShort`) rather than the whole bank
- Hosts the privacy policy (`privacy/`) and terms of service (`terms/`)
- A download section at the foot of every page, generated from
  `site.downloadGroups`, which is also what the header's download menu prints

## Structure

```
cuecard-website/
├── .eleventy.js       # 11ty config (input src/, output _site/)
├── src/
│   ├── index.njk      # The landing page: what CueCard is, and where to get it
│   ├── desktop/       # The Mac and Windows app
│   ├── faq.njk        # The whole FAQ bank, grouped
│   ├── styles.css     # Editorial, on paper: hairlines, micro-labels, two
│   │                  #   section designs, one accent (the cue colour)
│   ├── script.js      # Prompter backdrop, corner clock, the live prompter,
│   │                  #   nav, download menu, FAQ search, releases
│   ├── shortlink.njk  # Generates /ios and /android redirect pages
│   ├── sitemap.xml.njk# Generated from the data files, so it cannot drift
│   ├── CNAME          # Custom domain for GitHub Pages
│   ├── _data/
│   │   ├── site.js            # Every shared constant: URLs, downloads, the
│   │   │                      #   Slides extension, the three demo links, the
│   │   │                      #   App Store artwork, app lists, and the
│   │   │                      #   hand-written download total
│   │   ├── features.js        # Feature rows, mobile and desktop
│   │   ├── faq.js             # The FAQ bank and the helpers that slice it
│   │   └── *.json             # Page content: apps, platforms, roles, blogs
│   ├── _includes/
│   │   ├── layouts/           # base.njk carries the head and the JSON-LD graph
│   │   └── partials/          # prompter-bg, hero, deck, shots, watch, rows,
│   │   │                      #   applist, crosspanel, bigscreen, rolegrid,
│   │   │                      #   faq, getcuecard, extension, footer
│   ├── assets/        # Favicons, manifest, and the two App Store strips
│   │                  #   (promo-mobile.jpg, promo-ipad.jpg) the site shows
│   ├── privacy.njk    # Privacy policy
│   └── terms.njk      # Terms of service
└── _site/             # Build output (gitignored)
```

The site is fully static — no PHP, no server-side anything — so it can be served
by any static host.

## The backdrop, the clock and the live prompter

There is no video anywhere on this site — no player, no poster, no reel. What
sits behind the page instead is the app:

- **`partials/prompter-bg.njk`** is a fixed page of prompter script that drifts
  upward as you scroll, with one line lit at a time. The lines are written by
  `initPrompterBackdrop()` in `script.js`, not by the template, and that is
  deliberate: copy set at three per cent contrast has no business being in the
  HTML, where a crawler reads it as hidden text. With no JavaScript the page is
  simply white, which is what it should be anyway.
- **The clock** in the same partial is the one the app puts above the script.
  It counts how long you have been on the page and stops when you press it.
- **`partials/deck.njk`** is the live prompter in the hero: the same script the
  App Store film uses, scrolling at real lines per minute, cues in the cue
  colour, clock counting. Pause, restart and the speed slider all work. Set
  `heroDeck = true` on a page to get it.

`prefers-reduced-motion` removes the backdrop and leaves the prompter still.

## The screenshots and the demos

`site.shots` holds the two App Store strips (iPhone and iPad) and
`partials/shots.njk` prints them full width, directly under the hero — "what
does it actually look like" is the second question everybody has.

`site.demos` holds three YouTube links, one per device, and
`partials/watch.njk` draws each as the device it was filmed on with a play mark
over it. **Nothing is embedded**: an iframe would drag a third-party player
onto every page it appeared on, and a link costs nothing. Pass `demoIds` to
show a subset, in order.

`partials/bigscreen.njk` is the "it's on iPad too" card that every phone page
carries, with the iPad film beside it.

## The downloads

`site.downloadGroups` in `src/_data/site.js` is the one list of everywhere
CueCard can be had, grouped by the machine you are on. It is printed in three
places and edited in one:

- the header's **Download** menu (`partials/downloadmenu.njk`)
- the `#download` section that closes every page (`partials/getcuecard.njk`);
  the desktop pages close with `partials/download.njk` instead, which lists the
  actual installers for a release
- the `ItemList` in the landing page's structured data

Adding a platform means adding an entry there and nothing else. An entry with
`soon: true` prints as a flat "Coming soon" row rather than a button, which is
what Android is until it ships — it is never described as a beta anywhere.

**The browser extension is not in that list.** It is not a version of CueCard;
it is the piece that makes Google Slides work. It lives in `site.extension` and
is printed by `partials/extension.njk` on `/google-slides/` and nowhere else,
with a link to that page from the download menu and the download section.

## The download total

`site.downloadTotal` (currently `"1,100+"`) is a hand-written string, and
deliberately so: the GitHub API only counts desktop release assets, so any
computed figure would leave out the App Store entirely. Edit the string and
every page follows. The GitHub star count next to it *is* live, fetched through
the Cloudflare proxy in `api/`.

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
  app lists, the artwork, the demo links and the year. Change it there, not in
  a template
- Page titles in the `_data/*.json` files lead with the phrase people search
  for and end with the brand, never the other way round. The front-matter
  fields that read them are piped through `| safe`, because without it a `&`
  in a title is escaped twice and ships as `&amp;amp;`
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
