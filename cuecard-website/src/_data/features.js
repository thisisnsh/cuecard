// What the apps actually do, read out of the app source rather than guessed:
// the iOS app's HelpView, SettingsView, TimerSheet, CueCards, the watch app
// and TeleprompterPiPManager, and the desktop app's screen-capture, shortcuts
// and Google Slides sync. Every row is something the app does today; nothing
// is here to fill a row.
//
// Written for someone who has never used a teleprompter. Plain words, whole
// sentences, no clipped phrases the reader has to unpack. One or two sentences
// each: nobody reads a paragraph about a feature they have not installed yet,
// and the FAQ is where the long answers live.
//
// Two claims that must not drift, because they are different on each side:
//
//   * On the phone, CueCard is NOT invisible. It floats above other apps, so
//     the camera never sees it — but an iPhone screen recording does. Only the
//     desktop app is genuinely hidden from screen capture.
//   * Google Slides sync is one way of using the desktop app, not the whole of
//     it. The desktop app also works on its own with notes you paste in.
//
// The home page and /mobile/ carry the mobile set, /desktop/ and the meeting
// pages carry the desktop set, and the role and app pages reword the same
// capabilities around their subject so no two feature sections on the site
// read alike. The /teleprompter/, /cards/ and /watch/ pages carry their own
// rows in _data/speaking.js. site.products.mobile.features is this list in a
// line each.

// `appleOnly` rows are left off the Android page, which lists what is planned.
const mobile = [
  {
    h: "A teleprompter and cue cards in one app",
    p: "Read a whole script as it scrolls, or speak from short cards one at a time.",
  },
  {
    h: "Scrolls at your pace",
    p: "Set the speed once and the script moves on its own. Pause or drag it whenever you need.",
  },
  {
    h: "Floats over the app you film in",
    p: "Your script stays on screen over the camera, Instagram, TikTok or a call, in a rectangular or square window.",
  },
  {
    h: "Cards on your Lock Screen",
    p: "Turn cards and watch the timer with your phone locked.",
    appleOnly: true,
  },
  {
    h: "An Apple Watch app",
    p: "Control the teleprompter from your wrist, and read your cards there, with or without your iPhone.",
    appleOnly: true,
  },
  {
    h: "A timer that warns you",
    p: "It changes color near the end and when you run over, in colors you can tell apart.",
  },
  {
    h: "Cues you read but never say",
    p: "Reminders like [cue smile] show in color, telling you how to say the next line.",
  },
  {
    h: "Find a script or bring back an earlier draft",
    p: "Search saved notes by title or text. Compare versions and restore an earlier save.",
    appleOnly: true,
  },
  {
    h: "Keep notes as files",
    p: "Choose a notes folder to keep the latest copy of every saved script and deck outside the app, even if you remove CueCard.",
    appleOnly: true,
  },
  {
    h: "Free, private, no sign-up",
    p: "No account, no ads and no subscription. Your scripts are not uploaded to CueCard.",
  },
];

const desktop = [
  {
    h: "A script that scrolls while you speak",
    p: "Press play, with a speed, text size and start delay you choose. Pause, go back or restart whenever you need.",
  },
  {
    h: "Saved scripts for the next presentation",
    p: "Name a script and open it again from the sidebar. Import and export text files with your cues included.",
  },
  {
    h: "Hidden from your screen share",
    p: "Your notes stay on your screen while Zoom, Google Meet and Teams show only your slides.",
  },
  {
    h: "Cues you read but never say",
    p: "Reminders like [cue slow down] show in color, telling you how to say the next part.",
  },
  {
    h: "A timer for your slot",
    p: "Set a duration for a countdown with warning and overtime colors, or leave it unset to count up. The timer keeps going across slides.",
  },
  {
    h: "Google Slides notes that follow your slides",
    p: "With the browser extension, the notes for the slide you are on show up as you present.",
  },
  {
    h: "Works with any deck, or none",
    p: "PowerPoint, Keynote, a PDF or no slides at all. Just paste your notes in.",
  },
  {
    h: "Keyboard shortcuts",
    p: "Show, hide, move and time it without clicking away from your presentation.",
  },
];

/** Four rows reworded around one social or meeting app. */
function forApp(name, kind) {
  if (kind === "meeting") {
    return [
      {
        h: `Hidden while you share your screen on ${name}`,
        p: `${name} shows everyone your slides and never your notes.`,
      },
      {
        h: "Notes that keep up with your slides",
        p: "Google Slides notes follow the slide you are on. Any other deck, paste your notes in.",
      },
      {
        h: "A countdown you can see",
        p: `Keep a thirty-minute ${name} call to thirty minutes.`,
      },
      {
        h: "On your phone as well",
        p: `Filming after the ${name} call? CueCard for iPhone and iPad floats your script over whatever you record in.`,
      },
    ];
  }
  return [
    {
      h: `Read your script while ${name} records`,
      p: `CueCard floats on top of ${name}, so you record where you always do.`,
    },
    {
      h: "Eyes near the lens",
      p: "Keep the script just under the front camera, so you look like you are talking, not reading.",
    },
    {
      h: "Cues for how to say it",
      p: "Reminders like [cue smile] show in color as they pass.",
    },
    {
      h: `Shaped to fit the ${name} frame`,
      p: "Rectangular or square, and it goes wherever you drag it.",
    },
  ];
}

/**
 * Six rows reworded around one role.
 *
 * The role pages used to print the `mobile` or `desktop` list verbatim, which
 * meant twenty-four pages carrying the same six paragraphs as each other and
 * as the page they were trying not to compete with. Same capabilities, said in
 * the terms of the job the page is about.
 */
function forRole(name, audience, kind) {
  const who = (audience || name || "").toLowerCase();

  if (kind === "mobile") {
    return [
      {
        h: "A script that stays up while you film",
        p: `Whatever ${who} record in, CueCard floats above it.`,
      },
      {
        h: "Scrolls at your pace",
        p: "Set the speed once, then pause or drag it whenever you need.",
      },
      {
        h: "Cues for how to say it",
        p: "Reminders like [cue slow down] show in color as they pass.",
      },
      {
        h: "A countdown and a timer",
        p: `A moment to settle before it moves, and a timer that keeps ${who} to the length a take has to be.`,
      },
      {
        h: "Cue cards when you are speaking live",
        p: "Short cards to swipe through, on your phone, Lock Screen or Apple Watch.",
      },
      {
        h: "Scripts saved for next time",
        p: `Find the scripts ${who} reuse by title or text, and restore an earlier version when a rewrite needs undoing.`,
      },
    ];
  }

  return [
    {
      h: "Hidden from the screen you share",
      p: `On Zoom, Google Meet and Teams the room sees your deck, and only ${who} see the notes.`,
    },
    {
      h: "Notes for any deck",
      p: "PowerPoint, Keynote, a PDF or nothing at all. Google Slides notes can follow your slides.",
    },
    {
      h: "Cues you read but never say",
      p: "Reminders like [cue take a breath] show in color.",
    },
    {
      h: "A timer for your slot",
      p: `A countdown on screen keeps ${who} on time.`,
    },
    {
      h: "A window where you want it",
      p: "Move it, resize it and fade it over your slides, close to the camera.",
    },
    {
      h: "Keyboard shortcuts",
      p: "Show, hide, move and time it without clicking away.",
    },
  ];
}

/** The phone rows that could apply to an app that is not out yet. */
const mobilePlanned = mobile.filter((row) => !row.appleOnly);

module.exports = { mobile, mobilePlanned, desktop, forApp, forRole };
