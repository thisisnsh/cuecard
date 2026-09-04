// Site-wide constants. Anything that appears on more than one page and would
// be a bug to get out of step lives here, so a change lands everywhere at once.
//
// CueCard leads with the mobile teleprompter: cuecard.dev is the mobile app
// site, and the Mac/Windows app keeps its own home at /desktop/ with every URL
// it already ranked for left exactly where it was.

const year = new Date().getFullYear();

module.exports = {
  name: "CueCard",
  shortName: "CueCard",
  tagline: "The teleprompter that floats over everything",
  url: "https://cuecard.dev",
  email: "support@cuecard.dev",
  github: "https://github.com/thisisnsh/cuecard",
  issues: "https://github.com/ThisIsNSH/CueCard/issues",
  releases: "https://github.com/thisisnsh/cuecard/releases",
  year,

  // Stores. Android is in closed testing, so it is announced as coming soon
  // everywhere rather than linked as if it were shipping.
  ios: "https://apps.apple.com/app/cuecard-teleprompter/id6757321325",
  android: "https://play.google.com/apps/testing/com.thisisnsh.cuecard.android",
  androidComingSoon: true,

  requiresMobile: "iOS 17.0 or later",
  requiresMobileShort: "iOS 17+",
  requiresDesktop: "macOS 13 or later, Windows 10 or later",
  requiresDesktopShort: "macOS · Windows",

  // ── The background reel ─────────────────────────────────────────────────
  // A fixed layer the whole page scrolls over, exactly like the poster frame
  // it fades up from. `enabled` stays false until the real files are dropped
  // in src/assets/ — with it off the poster simply stays, which is a complete,
  // unbroken background rather than a 404 in the console.
  video: {
    enabled: false,
    mp4: "/assets/promo.mp4",
    webm: "/assets/promo.webm",
    poster: "/assets/cuecard-poster.png",
    posterWidth: 1104,
    posterHeight: 720,
  },

  // ── The canonical demos ─────────────────────────────────────────────────
  // What the VideoObject blocks describe. `mobile` is a placeholder pointing
  // at the existing reel until the mobile film is up: swap `id`, `title`,
  // `uploadDate` and `duration` and every page follows.
  youtube: {
    mobile: {
      placeholder: true,
      id: "VQ85qXoMfis",
      watch: "https://www.youtube.com/watch?v=VQ85qXoMfis",
      embed: "https://www.youtube.com/embed/VQ85qXoMfis",
      thumb: "https://i.ytimg.com/vi/VQ85qXoMfis/maxresdefault.jpg",
      title: "CueCard Mobile - a teleprompter that floats over every app",
      description:
        "A walkthrough of CueCard on iPhone: a floating teleprompter window that stays on top of the camera, Instagram, TikTok or any other app, auto-scrolling your script while you record.",
      uploadDate: "2025-12-28",
      duration: "PT1M14S",
    },
    desktop: {
      id: "VQ85qXoMfis",
      watch: "https://www.youtube.com/watch?v=VQ85qXoMfis",
      embed: "https://www.youtube.com/embed/VQ85qXoMfis",
      thumb: "https://i.ytimg.com/vi/VQ85qXoMfis/maxresdefault.jpg",
      title: "CueCard - invisible speaker notes for Zoom, Google Meet and Teams",
      description:
        "A walkthrough of CueCard on macOS and Windows: speaker notes that stay invisible while you share your screen on Zoom, Google Meet or Microsoft Teams, synced live from Google Slides.",
      uploadDate: "2025-12-28",
      duration: "PT1M14S",
    },
  },

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
