// Site-wide constants. Anything that appears on more than one page and would
// be a bug to get out of step lives here, so a change lands everywhere at once.
//
// Three pages carry the product. / is the landing page - what CueCard is, the
// fork between the two halves, and the download hub. /mobile/ is the phone
// teleprompter. /desktop/ is the Mac and Windows app, with every URL it already
// ranked for left exactly where it was.

const year = new Date().getFullYear();

const site = {
  name: "CueCard",
  shortName: "CueCard",
  tagline: "The teleprompter that floats over everything",
  url: "https://cuecard.dev",
  email: "support@cuecard.dev",
  github: "https://github.com/thisisnsh/cuecard",
  issues: "https://github.com/ThisIsNSH/CueCard/issues",
  releases: "https://github.com/thisisnsh/cuecard/releases",
  year,

  // Stores. Android is not out: it is announced as coming soon everywhere
  // rather than linked as if it were shipping, and never as a beta.
  ios: "https://apps.apple.com/app/cuecard-teleprompter/id6757321325",
  android: "https://play.google.com/apps/testing/com.thisisnsh.cuecard.android",
  androidComingSoon: true,

  requiresMobile: "iOS 17.0 or later",
  requiresMobileShort: "iOS 17+",
  requiresDesktop: "macOS 13 or later, Windows 10 or later",
  requiresDesktopShort: "macOS · Windows",

  // ── The background reel ─────────────────────────────────────────────────
  // A fixed layer the whole page scrolls over. There is no video player
  // anywhere on the site any more: this reel *is* the film, and the page reads
  // on top of it.
  //
  // `placeholder` is the honest flag. While it is true these are borrowed
  // files and nothing is marked up as a VideoObject, because structured data
  // that describes someone else's footage is a lie. Drop CueCard's own three
  // files in, point the URLs at them, fill in `schema`, set placeholder to
  // false — and every page starts declaring the video to search engines.
  video: {
    enabled: true,
    placeholder: true,
    origin: "https://download.alldayidreamaboutsports.com",
    mp4: "https://download.alldayidreamaboutsports.com/promo.mp4",
    webm: "https://download.alldayidreamaboutsports.com/promo.webm",
    poster: "https://download.alldayidreamaboutsports.com/promo-f1.webp",
    posterWidth: 1440,
    posterHeight: 810,
    schema: {
      name: "CueCard — a teleprompter that floats over every other app",
      description:
        "CueCard on iPhone and on the desktop: a floating teleprompter window that stays on top of the camera, Instagram or TikTok while you record, and speaker notes that stay out of the screen share while you present.",
      uploadDate: "2026-01-01",
      duration: "PT1M4S",
    },
  },

  // ── Where CueCard can actually be had ───────────────────────────────────
  // One list, used in two places: the header's download menu and the download
  // section that closes every page. They cannot drift apart because there is
  // only one of them.
  //
  // The browser extension is not a version of CueCard - it is the piece that
  // makes Google Slides work - so it is not in here. It lives on
  // /google-slides/, in site.extension.
  //
  // An `href` starting with "/" is a page on this site; anything else is a
  // store and opens in a new tab.
  downloadGroups: [
    {
      id: "phone",
      label: "On your phone",
      icon: "phone",
      note: "Floats on top of whatever you are filming in.",
      items: [
        {
          name: "iPhone and iPad",
          icon: "apple",
          meta: "iOS 17 or later",
          cta: "App Store",
          href: "https://apps.apple.com/app/cuecard-teleprompter/id6757321325",
          more: "/mobile/ios/",
        },
        {
          // Android is not out. It is listed so the page is honest about what
          // is coming, and it is a link to its own page rather than a store.
          name: "Android",
          icon: "android",
          meta: "In development",
          cta: "Coming soon",
          soon: true,
          href: "/mobile/android/",
        },
      ],
    },
    {
      id: "computer",
      label: "On your computer",
      icon: "monitor",
      note: "Speaker notes that stay out of the screen share.",
      items: [
        {
          name: "macOS",
          icon: "apple",
          meta: "macOS 13 or later",
          cta: "Download",
          href: "/desktop/#download",
          more: "/desktop/",
        },
        {
          name: "Windows",
          icon: "windows",
          meta: "Windows 10 or later",
          cta: "Download",
          href: "/desktop/#download",
          more: "/desktop/",
        },
      ],
    },
  ],

  // ── The Google Slides extension ─────────────────────────────────────────
  // Not a version of CueCard: a bridge. It reads the speaker notes out of the
  // deck you are presenting and hands them to the desktop app, live. It is
  // shown on /google-slides/ and nowhere else, because on any other page it
  // reads as a fourth platform, which it is not.
  extension: {
    page: "/google-slides/",
    note: "Sends your Google Slides speaker notes to the desktop app as you advance.",
    items: [
      {
        name: "Chrome",
        icon: "chrome",
        meta: "Also Edge, Brave and Arc",
        cta: "Web Store",
        href: "https://chromewebstore.google.com/detail/mfphcgcbbahhahofibnenonbgjnabamg",
      },
      {
        name: "Firefox",
        icon: "firefox",
        meta: "Firefox 109 or later",
        cta: "Add-ons",
        href: "https://addons.mozilla.org/en-US/firefox/addon/cuecard-extension/",
      },
      {
        name: "Safari",
        icon: "safari",
        meta: "Installed by the macOS app",
        cta: "Download",
        href: "/desktop/#download",
      },
    ],
  },

  // ── The demo film ───────────────────────────────────────────────────────
  // The one moving picture on the site that is CueCard's own. It is not
  // embedded: a still links out to YouTube, so no third-party player script
  // loads on any page. (The reel behind the page is atmosphere; this is the
  // thing to actually watch.)
  demo: {
    id: "VQ85qXoMfis",
    url: "https://www.youtube.com/watch?v=VQ85qXoMfis",
    thumb: "https://img.youtube.com/vi/VQ85qXoMfis/maxresdefault.jpg",
    title: "CueCard - speaker notes only you can see",
    alt: "CueCard's speaker notes sitting on screen while a deck is shared - watch the demo on YouTube",
  },

  // The download total, written by hand. It is a claim about the product, not
  // a live figure: the GitHub API only knows about desktop release assets, so
  // anything computed from it undercounts the App Store badly. Edit the
  // string and every page follows. The star count beside it *is* live.
  downloadTotal: "1,100+",

  // ── The apps CueCard is read over, on a phone ───────────────────────────
  // Each has a page of its own; `icon` names a symbol in partials/icons.njk.
  socialApps: [
    { name: "Instagram", slug: "instagram", icon: "instagram", use: "Reels" },
    { name: "TikTok", slug: "tiktok", icon: "tiktok", use: "TikToks" },
    { name: "YouTube", slug: "youtube", icon: "youtube", use: "Shorts and long form" },
    { name: "LinkedIn", slug: "linkedin", icon: "linkedin", use: "Video posts" },
    { name: "Facebook", slug: "facebook", icon: "facebook", use: "Reels and Live" },
    { name: "Snapchat", slug: "snapchat", icon: "snapchat", use: "Spotlight" },
    { name: "Twitter / X", slug: "twitter", icon: "twitter", use: "Video posts" },
  ],

  // ── The apps CueCard hides from, on a computer ──────────────────────────
  meetingApps: [
    { name: "Zoom", slug: "zoom", icon: "zoom", use: "Screen sharing" },
    { name: "Google Meet", slug: "google-meet", icon: "meet", use: "Presenting a tab" },
    { name: "Microsoft Teams", slug: "microsoft-teams", icon: "teams", use: "Sharing a window" },
    { name: "Google Slides", slug: "google-slides", icon: "slides", use: "Live note sync" },
  ],

  // Roles with a page on each side of the product. Kept in the order the
  // footer prints them, which is alphabetical so nothing looks ranked.
  mobileRoles: [
    { name: "Content Creators", slug: "content-creators" },
    { name: "Coaches", slug: "coaches" },
    { name: "Course Creators", slug: "course-creators" },
    { name: "Fitness Instructors", slug: "fitness-instructors" },
    { name: "Podcasters", slug: "podcasters" },
    { name: "Realtors", slug: "realtors" },
    { name: "Sales", slug: "sales" },
    { name: "Streamers", slug: "streamers" },
    { name: "Teachers", slug: "teachers" },
    { name: "TikTokers", slug: "tiktokers" },
    { name: "Vloggers", slug: "vloggers" },
    { name: "YouTubers", slug: "youtubers" },
  ],

  desktopRoles: [
    { name: "Coaches", slug: "coaches" },
    { name: "Consultants", slug: "consultants" },
    { name: "Course Creators", slug: "course-creators" },
    { name: "Executives", slug: "executives" },
    { name: "Fitness Instructors", slug: "fitness-instructors" },
    { name: "Lawyers", slug: "lawyers" },
    { name: "Realtors", slug: "realtors" },
    { name: "Sales", slug: "sales" },
    { name: "Students", slug: "students" },
    { name: "Teachers", slug: "teachers" },
    { name: "Trainers", slug: "trainers" },
    { name: "Webinar Hosts", slug: "webinar-hosts" },
  ],
};

// Every download as one flat list, in the order the groups print them. The
// grouped shape is what the page reads; this is what schema and any counting
// wants, and deriving it means the two can never disagree.
site.downloads = site.downloadGroups.reduce(
  (all, g) => all.concat(g.items.map((d) => ({ ...d, group: g.label }))),
  []
);

module.exports = site;
