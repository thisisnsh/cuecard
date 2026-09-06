// What the apps actually do, read out of the app source rather than guessed:
// the iOS app's TeleprompterPiPManager, SettingsService, TeleprompterParser and
// HomeView, and the desktop app's screen-capture, shortcuts and Google Slides
// sync.
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
// The home page carries the mobile set, /desktop/ and the meeting pages carry
// the desktop set, and the role and app pages reword the same capabilities
// around their subject so no two feature sections on the site read alike.

const mobile = [
  {
    h: "Floats on top of every other app",
    p: "Your script stays on screen while you record in the camera app, Instagram, TikTok or anything else, so you never have to switch apps in the middle of a take to check your next line.",
  },
  {
    h: "Scrolls on its own, at your pace",
    p: "Set how fast the script moves and it scrolls by itself while you talk. Speed it up or slow it down at any time, and pause it whenever you need a moment.",
  },
  {
    h: "Cues you read but never say out loud",
    p: "Type something like [cue smile] or [cue slow down] in the middle of your script and it appears in colour — pink, yellow, green, blue, purple or red, whichever you pick. It is a reminder about how to say the next line, not a line to read.",
  },
  {
    h: "A countdown to start, and a timer while you talk",
    p: "CueCard counts you in before the script starts moving, so you have a few seconds to get ready. A timer then runs while you speak, so you know whether the take is running long.",
  },
  {
    h: "A floating window you can shape and move",
    p: "Drag the window anywhere on screen, make it wide, square or tall, and set the text size inside it. Put it just under the camera lens and your eyes stay close to the lens instead of drifting down.",
  },
  {
    h: "Scripts you save and come back to",
    p: "Give a script a name, save it, and open it again next time. You can also import one from a file. The app follows your phone's light or dark appearance, or you can set it to stay light or stay dark.",
  },
];

const desktop = [
  {
    h: "Hidden from your screen share",
    p: "The CueCard window is left out of screen capture by the operating system itself. On Zoom, Google Meet and Microsoft Teams, everyone sees your slides and never your notes — even though the window is right there on your screen.",
  },
  {
    h: "Cues you read but never say out loud",
    p: "Type something like [cue slow down] in your notes and it appears in colour. It reminds you how to say the next part instead of giving you another line to read.",
  },
  {
    h: "Timing tags that count themselves down",
    p: "Write [time 05:00] at the start of a section and CueCard counts those five minutes down on screen. It is the easiest way to keep a thirty-minute slot to thirty minutes.",
  },
  {
    h: "Google Slides notes that follow your slides",
    p: "Add the CueCard browser extension and the speaker notes for the slide you are on show up in CueCard as you move through the deck. You do not have to scroll to keep up.",
  },
  {
    h: "Works with any deck, or no deck at all",
    p: "Google Slides is optional. Paste your notes straight into CueCard and present from PowerPoint, Keynote, a PDF, or nothing at all — it is a teleprompter on its own.",
  },
  {
    h: "Keyboard shortcuts for the whole thing",
    p: "Show and hide the window, move it, resize it, fade it back over your slides and start or reset the timer from the keyboard, without ever clicking away from what you are presenting.",
  },
];

/** Four rows reworded around one social or meeting app. */
function forApp(name, kind) {
  if (kind === "meeting") {
    return [
      {
        h: `Hidden while you share your screen on ${name}`,
        p: `The CueCard window is left out of screen capture by the operating system, so ${name} shows everyone your slides and never your notes.`,
      },
      {
        h: "Notes that keep up with your slides",
        p: "Presenting from Google Slides? Add the browser extension and your notes change as you move through the deck. Presenting from anything else? Paste your notes in and read straight through them.",
      },
      {
        h: "A countdown you can actually see",
        p: `Write [time 05:00] into your notes and CueCard counts it down on screen, so a thirty-minute ${name} call stays thirty minutes.`,
      },
      {
        h: "On your phone as well",
        p: `Filming a video after the ${name} call? The CueCard app for iPhone and iPad floats your script on top of whatever you record in.`,
      },
    ];
  }
  return [
    {
      h: `Read your script while ${name} records`,
      p: `CueCard floats on top of ${name}, so you keep recording in the app you always use and your video comes out of it exactly as it always has.`,
    },
    {
      h: "Eyes near the lens, not down at your hand",
      p: "Put the floating window just under the front camera and let it scroll. On camera it reads as talking to someone, not reading off a page.",
    },
    {
      h: "Cues for how to say it, not just what to say",
      p: "Type [cue smile] or [cue hold for two] into your script and it shows up in colour. You take it in as you pass it; you never read it out.",
    },
    {
      h: `Shaped to fit the ${name} frame`,
      p: "Make the floating window wide, square or tall, then drag it to a corner where it does not cover your face or anything else you want in shot.",
    },
  ];
}

module.exports = { mobile, desktop, forApp };
