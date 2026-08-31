# CueCard Website

Static site that powers [cuecard.dev](https://cuecard.dev) and mirrors the information from the desktop app landing page.

## Purpose

- Showcases CueCard’s positioning, features, and FAQ
- Hosts the privacy policy (`privacy/`) and terms of service (`terms/`)
- Embeds the product demo video from YouTube
- Provides download links to GitHub Releases

## Structure

```
cuecard-website/
├── .eleventy.js       # 11ty config (input src/, output _site/)
├── src/
│   ├── index.njk      # Landing page content
│   ├── styles.css     # Syne/Inter themed layout
│   ├── script.js      # Lightweight interactions (FAQ toggles, animations)
│   ├── shortlink.njk  # Generates /ios and /android redirect pages
│   ├── CNAME          # Custom domain for GitHub Pages
│   ├── _data/         # Page content: professions, apps, blogs, shortlinks
│   ├── _includes/     # Layouts and partials
│   ├── assets/        # Favicons, manifest, images
│   ├── privacy.njk    # Privacy policy
│   └── terms.njk      # Terms of service
└── _site/             # Build output (gitignored)
```

The site is fully static — no PHP, no server-side anything — so it can be served by any static host.

## Local Preview

```bash
npm ci
npm start
```

Then open the URL 11ty prints (`http://localhost:8080/` by default). The dev
server rebuilds on save.

## Build & Deploy

Deployment is automatic: `.github/workflows/deploy-website.yml` builds the site
and publishes `_site/` to GitHub Pages on every push to `main` that touches
`cuecard-website/`. Pull requests build the site but do not deploy.

To build locally:

```bash
npm ci
npm run build   # writes _site/
```

## Notes

- Update `site.webmanifest` and favicons in `assets/` when branding changes
- Remember to keep privacy/terms copies in sync with legal docs used inside the desktop app
- `src/CNAME` pins the custom domain. Removing it reverts the site to the
  `github.io` host on the next deploy
- GitHub Pages serves `404.html` natively and handles apex/www plus HTTPS, so
  the site carries no `.htaccess` or `_redirects` file. Add new shortlinks
  (like `/ios` and `/android`) to `src/_data/shortlinks.json` instead
