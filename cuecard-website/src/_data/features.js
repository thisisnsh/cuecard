// What the apps actually do, read out of the app source rather than guessed:
// the iOS app's TeleprompterPiPManager, SettingsService, TeleprompterParser and
// HomeView, and the desktop app's screen-capture and Google Slides sync.
//
// The home page carries the mobile set, /desktop/ carries the desktop set, and
// the role and app pages reword the same capabilities around their subject so
// no two feature sections on the site read alike.

const mobile = [
  {
    h: "A prompter that floats over every other app",
    p: "Your script sits in a window on top of whatever you are doing — the camera, Instagram, TikTok, Zoom, a slide deck. Nothing to switch to, nothing to switch back from, and it never lands in the recording.",
  },
  {
    h: "Auto-scroll set in lines per minute, not guesswork",
    p: "Pick a speed and the script moves at it, word by word, with the word you are on lit up so your eye never has to search for its place. A start delay counts you in so the first line is not the one you fumble.",
  },
  {
    h: "Delivery cues you can see but never read out",
    p: "Write [cue smile] or [cue slow down here] in the middle of a sentence and it renders in its own colour, distinct from the script. They are stage directions to yourself — you take them in without saying them.",
  },
  {
    h: "Sized and shaped for the shot you are actually filming",
    p: "Set the floating window to 16:9, 4:3 or 1:1, pick a text size for it separately from the in-app one, and put it where it does not cover the frame you are recording.",
  },
  {
    h: "A timer that tells you the truth about your length",
    p: "Set a duration and watch it run down while you speak. It is the difference between a take that fits the platform's limit and one you find out is too long in the edit.",
  },
  {
    h: "Scripts you write once and keep",
    p: "Save a script, name it, come back to it next week. Light, dark or whatever your phone is set to, so reading it at midnight is not a flashbang.",
  },
];

const desktop = [
  {
    h: "Speaker notes that stay out of the screen share",
    p: "CueCard sits above your deck on macOS and Windows and is excluded from screen capture, so Zoom, Google Meet and Microsoft Teams send the presentation and nothing else. What your audience sees is your slide.",
  },
  {
    h: "Notes synced live from Google Slides",
    p: "Install the browser extension for Chrome, Firefox or Safari and the speaker notes for the slide you are on appear in CueCard as you advance. No copy-paste, no second monitor, no printed script.",
  },
  {
    h: "Timing tags and delivery cues in the script itself",
    p: "Write [time 05:00] to pin a checkpoint and [cue slow down] to leave yourself a reminder. Timestamps count down on screen; cues are highlighted so you catch them without reading them out.",
  },
  {
    h: "Works with any deck, not only Google Slides",
    p: "Paste your notes in and present from PowerPoint, Keynote, a PDF or nothing at all. The Slides sync is a convenience, never a requirement.",
  },
  {
    h: "Adjustable transparency, light and dark",
    p: "Fade the window back until it is barely there over your deck, or bring it forward when you need it. Matches your system theme either way.",
  },
  {
    h: "Free, open source, and yours to check",
    p: "MIT licensed and on GitHub. If you want to know exactly what an app that sees your notes is doing, you can read it.",
  },
];

/** Four rows reworded around one social or meeting app. */
function forApp(name, kind) {
  if (kind === "meeting") {
    return [
      {
        h: `Invisible while you share your screen on ${name}`,
        p: `CueCard is excluded from screen capture, so ${name} sends your deck and not your notes. Nobody on the call sees the window you are reading from.`,
      },
      {
        h: `Notes that keep pace with the deck`,
        p: "Sync speaker notes from Google Slides and they change as you advance, or paste a script in and read it straight through.",
      },
      {
        h: "A countdown you can actually see",
        p: "Write [time 05:00] into the script and CueCard counts it down on screen, so a thirty minute slot stays a thirty minute slot.",
      },
      {
        h: `On your phone too`,
        p: `Taking the ${name} call from a phone, or filming something afterwards? CueCard's mobile teleprompter floats over every app on iOS.`,
      },
    ];
  }
  return [
    {
      h: `Read your script while ${name} is recording`,
      p: `The prompter floats above ${name}, so you record inside the app you always record in and your script is simply there on top of it.`,
    },
    {
      h: "Eyes near the lens, not down at your hand",
      p: "Put the window right under the front camera and auto-scroll it. The result on camera is someone talking to a person, not reading off a desk.",
    },
    {
      h: "Cues for the delivery, not just the words",
      p: "[cue smile], [cue hold for two] — written into the script, shown in their own colour, never spoken.",
    },
    {
      h: `Shaped for the ${name} frame`,
      p: "Set the overlay to 16:9, 4:3 or 1:1 and size the text for it, so the prompter never covers the part of the shot that matters.",
    },
  ];
}

module.exports = { mobile, desktop, forApp };
