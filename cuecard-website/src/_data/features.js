// What the apps actually do, read out of the app source rather than guessed:
// the iOS app's TeleprompterPiPManager, SettingsService, TeleprompterParser and
// HomeView, and the desktop app's screen-capture and Google Slides sync.
//
// One sentence each, on purpose. Nobody reads a paragraph about a feature they
// have not installed yet; the FAQ is where the long answers live.
//
// The home page carries the mobile set, /desktop/ carries the desktop set, and
// the role and app pages reword the same capabilities around their subject so
// no two feature sections on the site read alike.

const mobile = [
  {
    h: "Floats over every other app",
    p: "Your script sits on top of the camera, Instagram, TikTok or a live stream — and never lands in the recording.",
  },
  {
    h: "Auto-scroll in lines per minute",
    p: "Pick a speed and it moves at it, word by word, with the word you are on lit up.",
  },
  {
    h: "Cues you see but never say",
    p: "Write [cue smile] mid-sentence and it renders in its own colour — a stage direction to yourself.",
  },
  {
    h: "Sized for the shot",
    p: "16:9, 4:3 or 1:1, with its own text size, parked where it does not cover the frame.",
  },
  {
    h: "A countdown and a timer",
    p: "A start delay counts you in; a timer runs down while you talk, so the take fits.",
  },
  {
    h: "Scripts you keep",
    p: "Save it, name it, come back to it. Light or dark, or whatever your phone is set to.",
  },
];

const desktop = [
  {
    h: "Invisible in the screen share",
    p: "CueCard is excluded from screen capture, so Zoom, Google Meet and Teams send your deck and nothing else.",
  },
  {
    h: "Notes synced live from Google Slides",
    p: "With the extension installed, the notes for the slide you are on appear as you advance.",
  },
  {
    h: "Timing tags and cues in the script",
    p: "[time 05:00] counts down on screen; [cue slow down] is highlighted and never read out.",
  },
  {
    h: "Any deck, not only Slides",
    p: "Paste your notes in and present from PowerPoint, Keynote, a PDF or nothing at all.",
  },
  {
    h: "Transparency, light and dark",
    p: "Fade the window back over your deck or bring it forward. It follows your system theme.",
  },
  {
    h: "Free and open source",
    p: "MIT licensed and on GitHub, so you can read exactly what an app that sees your notes does.",
  },
];

/** Four rows reworded around one social or meeting app. */
function forApp(name, kind) {
  if (kind === "meeting") {
    return [
      {
        h: `Invisible while you share on ${name}`,
        p: `CueCard is excluded from screen capture, so ${name} sends your deck and not your notes.`,
      },
      {
        h: "Notes that keep pace with the deck",
        p: "Sync them from Google Slides and they change as you advance, or paste a script in and read straight through.",
      },
      {
        h: "A countdown you can actually see",
        p: "Write [time 05:00] into the script and CueCard counts it down, so a thirty minute slot stays one.",
      },
      {
        h: "On your phone too",
        p: `Filming after the ${name} call? The mobile teleprompter floats over every app on iOS.`,
      },
    ];
  }
  return [
    {
      h: `Read your script while ${name} records`,
      p: `The prompter floats above ${name}, so the footage still comes out of the app it always did.`,
    },
    {
      h: "Eyes near the lens, not down at your hand",
      p: "Park the window under the front camera and let it scroll. On camera it reads as talking, not reading.",
    },
    {
      h: "Cues for the delivery, not just the words",
      p: "[cue smile], [cue hold for two] — written into the script, shown in colour, never spoken.",
    },
    {
      h: `Shaped for the ${name} frame`,
      p: "Set the overlay to 16:9, 4:3 or 1:1 so it never covers the part of the shot that matters.",
    },
  ];
}

module.exports = { mobile, desktop, forApp };
