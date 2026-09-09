// Site-wide constants. Anything that appears on more than one page and would
// be a bug to get out of step lives here, so a change lands everywhere at once.
//
// The homepage introduces both products; /mobile/ and /desktop/ own their workflows.

const year = new Date().getFullYear();

const products = {
  mobile: {
    id: "https://cuecard.dev/#mobileapp", name: "CueCard Teleprompter",
    url: "https://cuecard.dev/mobile/", price: "0", currency: "USD",
    description: "A free mobile teleprompter with a floating script, adjustable scrolling, saved scripts, colored cues and timing controls.",
    image: "https://cuecard.dev/assets/promo-mobile.jpg",
    screenshots: ["https://cuecard.dev/assets/promo-mobile.jpg", "https://cuecard.dev/assets/promo-ipad.jpg"],
    features: ["Movable floating window", "Adjustable scroll speed in lines per minute", "Saved scripts", "Colored [cue ...] reminders", "Start delay and timer", "Separate full-screen and floating text sizes"],
    platforms: [
      { key: "ios", shipping: true, os: "iOS 16.6 or later, iPadOS 16.6 or later", short: "iOS / iPadOS 16.6+", storeUrl: "https://apps.apple.com/app/cuecard-teleprompter/id6757321325" },
      { key: "android", shipping: false, os: "Android", storeUrl: null }
    ]
  },
  desktop: {
    id: "https://cuecard.dev/#desktopapp", name: "CueCard for Mac and Windows",
    url: "https://cuecard.dev/desktop/", price: "0", currency: "USD",
    description: "Free speaker notes that stay out of your screen share, with optional Google Slides note sync.",
    image: "https://cuecard.dev/assets/og-image.png",
    features: ["Speaker notes excluded from screen capture", "Paste notes for any deck", "Google Slides note sync with the browser extension", "Colored cues and timing tags", "Keyboard shortcuts"],
    platforms: [
      { key: "macos", shipping: true, os: "macOS 13 or later", storeUrl: "https://github.com/thisisnsh/cuecard/releases" },
      { key: "windows", shipping: true, os: "Windows 10 or later", storeUrl: "https://github.com/thisisnsh/cuecard/releases" }
    ]
  }
};
const mobilePlatform = products.mobile.platforms[0];
const site = {
  products,
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
  ios: mobilePlatform.storeUrl,
  android: "https://play.google.com/apps/testing/com.thisisnsh.cuecard.android",
  androidComingSoon: !products.mobile.platforms[1].shipping,

  // Who writes the posts. A name on its own is a string; this is an entity
  // Google can resolve and tie to the same person elsewhere, which is what
  // carries authorship across to the blog.
  author: {
    id: "https://cuecard.dev/#nishant",
    name: "Nishant Hada",
    url: "https://thisisnsh.com",
    sameAs: ["https://github.com/thisisnsh", "https://www.linkedin.com/in/thisisnsh"],
  },

  requiresMobile: mobilePlatform.os,
  requiresMobileShort: mobilePlatform.short,
  requiresDesktop: products.desktop.platforms.map(p => p.os).join(", "),
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
      alt: "CueCard Teleprompter on iPhone: the script scrolling with cues in pink and a timer running, the floating prompter window sitting on top of the home screen, and the settings for start delay, scroll speed, cue colour and text size.",
      caption:
        "The script scrolling, the floating window sitting on top of another app, and the settings behind both.",
    },
    {
      id: "ipad",
      src: "/assets/promo-ipad.jpg",
      small: "/assets/promo-ipad-1100.jpg",
      width: 2200,
      height: 978,
      label: "On iPad",
      alt: "CueCard Teleprompter on iPad: the script filling the screen with play and restart controls, and the floating prompter window sitting on top of the home screen.",
      caption:
        "The same app on a bigger screen, easy to read from a few feet away.",
    },
  ],

  // ── The demos ───────────────────────────────────────────────────────────
  // Nothing is embedded anywhere on this site. Every demo is a link out to
  // YouTube, so no third-party player script loads on any page.
  //
  // A card carries a title and nothing else. It used to carry a second line
  // under the title as well, which only ever said the title again.
  demos: [
    {
      id: "phone",
      device: "iPhone",
      icon: "phone",
      url: "https://youtube.com/shorts/zSSABBm7K1Q",
      title: "The floating teleprompter on iPhone",
      shape: "portrait",
      primary: true,
    },
    {
      id: "ipad",
      device: "iPad",
      icon: "tablet",
      url: "https://youtube.com/shorts/cHfZ-XLuz1E",
      title: "CueCard Teleprompter on iPad",
      shape: "portrait",
    },
    {
      id: "desktop",
      device: "Mac and Windows",
      icon: "monitor",
      url: "https://youtu.be/lNKghjFrdTE",
      title: "Speaker notes only you can see",
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
      note: "Your script floats on top of whatever app you record in.",
      items: [
        {
          name: "iPhone and iPad",
          icon: "apple",
          meta: mobilePlatform.os,
          cta: "App Store",
          href: mobilePlatform.storeUrl,
          productPlatform: "ios", destinationType: "app_store",
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
      note: "Speaker notes that your screen share cannot see.",
      items: [
        {
          name: "macOS",
          icon: "apple",
          meta: products.desktop.platforms[0].os,
          cta: "Download",
          href: "/desktop/#download",
          more: "/desktop/",
        },
        {
          name: "Windows",
          icon: "windows",
          meta: products.desktop.platforms[1].os,
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
    note: "Sends your Google Slides speaker notes to the desktop app as you change slides.",
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

  // What the desktop app gets opened for. The role pages carry their own
  // lists; this is the general one, for /desktop/.
  desktopUses: [
    "Client presentations",
    "Sales demos",
    "All-hands and town halls",
    "Webinars",
    "Investor pitches",
    "Interviews and panels",
    "Online classes",
    "Product walkthroughs",
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
