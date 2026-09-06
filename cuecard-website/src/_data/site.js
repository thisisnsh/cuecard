// Site-wide constants. Anything that appears on more than one page and would
// be a bug to get out of step lives here, so a change lands everywhere at once.
//
// The phone is the product. /  is CueCard Teleprompter on iPhone and iPad;
// /desktop/ is the Mac and Windows app, kept whole because it ranks, but it
// is the second half of the story on every page rather than the first.

const year = new Date().getFullYear();

const site = {
  name: "CueCard",
  // The name to rank for. Used wherever a title, a heading or a schema block
  // wants the full product name rather than the short one.
  productName: "CueCard Teleprompter",
  shortName: "CueCard",
  tagline: "The teleprompter that floats over every app you film in",
  url: "https://cuecard.dev",
  email: "hello@thisisnsh.com",
  github: "https://github.com/thisisnsh/cuecard",
  youtube: "https://www.youtube.com/@thisisnsh",
  issues: "https://github.com/ThisIsNSH/CueCard/issues",
  releases: "https://github.com/thisisnsh/cuecard/releases",
  year,

  // Stores. Android is not out: it is announced as coming soon everywhere
  // rather than linked as if it were shipping, and never as a beta.
  ios: "https://apps.apple.com/app/cuecard-teleprompter/id6757321325",
  android: "https://play.google.com/apps/testing/com.thisisnsh.cuecard.android",
  androidComingSoon: true,

  // Who writes the posts. A name on its own is a string; this is an entity
  // Google can resolve and tie to the same person elsewhere, which is what
  // carries authorship across to the blog.
  author: {
    id: "https://cuecard.dev/#nishant",
    name: "Nishant Hada",
    url: "https://thisisnsh.com",
    sameAs: ["https://github.com/thisisnsh", "https://www.linkedin.com/in/thisisnsh"],
  },

  requiresMobile: "iOS 17.0 or later",
  requiresMobileShort: "iOS 17+",
  requiresDesktop: "macOS 13 or later, Windows 10 or later",
  requiresDesktopShort: "macOS · Windows",

  // ── The App Store artwork ───────────────────────────────────────────────
  // The one place on the site that shows the app itself. Two strips, one per
  // device, shown at full width under the hero.
  shots: [
    {
      id: "phone",
      src: "/assets/promo-mobile.jpg",
      small: "/assets/promo-mobile-1100.jpg",
      width: 2200,
      height: 1192,
      label: "On iPhone",
      alt: "CueCard Teleprompter on iPhone: the script scrolling with a countdown timer, the floating prompter reading over the home screen, and the settings for scroll speed and cue colour.",
      caption:
        "The prompter, the floating window over every other app, and the settings behind them.",
    },
    {
      id: "ipad",
      src: "/assets/promo-ipad.jpg",
      small: "/assets/promo-ipad-1100.jpg",
      width: 2200,
      height: 978,
      label: "On iPad",
      alt: "CueCard Teleprompter on iPad: a full-width script with play and restart controls, and the floating prompter window sitting over the home screen.",
      caption:
        "Same app, bigger glass. The iPad reads as a proper studio prompter at arm's length.",
    },
  ],

  // ── The demos ───────────────────────────────────────────────────────────
  // Nothing is embedded anywhere on this site. Every demo is a link out to
  // YouTube, so no third-party player script loads on any page.
  demos: [
    {
      id: "phone",
      device: "iPhone",
      icon: "phone",
      url: "https://youtube.com/shorts/zSSABBm7K1Q",
      title: "The floating teleprompter on iPhone",
      note: "Recording a Reel with the script on the glass.",
      shape: "portrait",
      primary: true,
    },
    {
      id: "ipad",
      device: "iPad",
      icon: "tablet",
      url: "https://youtube.com/shorts/cHfZ-XLuz1E",
      title: "CueCard Teleprompter on iPad",
      note: "A big-screen prompter that still floats over everything.",
      shape: "portrait",
    },
    {
      id: "desktop",
      device: "Mac and Windows",
      icon: "monitor",
      url: "https://youtu.be/lNKghjFrdTE",
      title: "Speaker notes only you can see",
      note: "Notes staying out of a shared screen on Zoom, Meet and Teams.",
      shape: "landscape",
    },
  ],

  // ── Where CueCard can actually be had ───────────────────────────────────
  // One list, used in two places: the header's download menu and the download
  // section that closes every page. They cannot drift apart because there is
  // only one of them.
  //
  // An `href` starting with "/" is a page on this site; anything else is a
  // store and opens in a new tab.
  downloadGroups: [
    {
      id: "phone",
      label: "On your phone and iPad",
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
    { name: "Snapchat", slug: "snapchat", icon: "snapchat", use: "Spotlight" },
    { name: "LinkedIn", slug: "linkedin", icon: "linkedin", use: "Video posts" },
    { name: "Facebook", slug: "facebook", icon: "facebook", use: "Reels and Live" },
    { name: "Twitter / X", slug: "twitter", icon: "twitter", use: "Video posts" },
    { name: "Twitch", slug: "twitch", icon: "twitch", use: "Going live" },
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

// The demos, addressable by id, for the pages that only want one of them.
site.demo = site.demos.reduce((map, d) => Object.assign(map, { [d.id]: d }), {});

// The shots, addressable by id. An id and its file name are not the same thing
// — the phone shot lives in promo-mobile.jpg — so anything that wants one looks
// it up here rather than rebuilding the path out of the id and missing.
site.shot = site.shots.reduce((map, s) => Object.assign(map, { [s.id]: s }), {});

module.exports = site;
