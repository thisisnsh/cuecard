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
    h: "Two ways to read: Teleprompter and Cards",
    p: "Teleprompter scrolls your whole script. Cards shows it one card at a time, for talks you give from notes rather than read word for word. Switch between them from the mode name at the top of the editor; each keeps its own script and settings.",
  },
  {
    h: "A teleprompter that scrolls at your pace",
    p: "Set the speed in lines per minute and the script moves on its own. Pause when you need a moment, or drag it back or ahead and it carries on from wherever you leave it.",
  },
  {
    h: "Floats on top of the app you film in",
    p: "Leave CueCard while the teleprompter is open and the script keeps going in a floating window over the camera, Instagram, TikTok or a video call. Pick a 16:9, 4:3 or square layout, give it its own text size and drag it up under the lens.",
  },
  {
    h: "Cards you swipe through, in the app or on the Lock Screen",
    p: "Swipe, or tap Back and Next, and dots show where you are in the deck. Turn on Show on Lock Screen and the card, the timer and the Back and Next buttons sit on your Lock Screen too.",
    appleOnly: true,
  },
  {
    h: "An Apple Watch app",
    p: "The watch plays, pauses and skips back ten seconds in the teleprompter, and shows your cards on your wrist in step with the iPhone. Keep a deck on the watch and you can speak from it with the iPhone left behind.",
    appleOnly: true,
  },
  {
    h: "A timer that warns you before time runs out",
    p: "Set how long you have and when to be warned, and the timer changes color at the warning and again once you run over. Pick colors that are easy for you to tell apart, and give the teleprompter a countdown before it starts to move.",
  },
  {
    h: "Cues you read but never say out loud",
    p: "Type [ or tap Add Cue to write a reminder like [cue smile] or [cue slow down]. It shows in the color you pick, in the teleprompter, on cards, on the Lock Screen and on the watch.",
  },
  {
    h: "Scripts and decks you save, and nothing to sign up for",
    p: "Save what you write, rename it or open it again from Saved Content, and import or export plain text files. There is no account, no ads and no subscription, and your scripts stay on your phone.",
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
    h: "A timer that counts your slot down",
    p: "Set how long you have on the Set Timer pill and CueCard counts it down on screen while you talk. It is the easiest way to keep a thirty-minute slot to thirty minutes.",
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
        p: `Set how long you have in CueCard and it counts down on screen, so a thirty-minute ${name} call stays thirty minutes.`,
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
        p: `Whatever ${who} record in — the camera app, Instagram, TikTok, a live stream — CueCard floats above it, so the next line is on screen without you ever leaving the app you are shooting in.`,
      },
      {
        h: "Scrolling you set once and then forget",
        p: "Pick a speed that matches how you talk and the script moves on its own. Nudge it faster or slower part-way through, or pause it while you reset the shot.",
      },
      {
        h: "Cues about how to say it, not what to say",
        p: "Drop [cue smile] or [cue slow down] in wherever you keep tripping up, and it shows in the colour you picked as you pass it. It is a reminder, not another line to read.",
      },
      {
        h: "A countdown in, and a clock while you talk",
        p: `CueCard counts you in before the script starts moving, so you have a moment to settle. The timer then runs while you speak, which is how ${who} keep a take to the length it has to be.`,
      },
      {
        h: "A window shaped to fit your shot",
        p: "Make the prompter wide, square or tall, then drag it up under the lens. Your eyes stay next to the camera instead of dropping to the bottom of the screen.",
      },
      {
        h: "Scripts saved, named and opened again",
        p: `Save the ones ${who} use more than once — an intro, a sign-off, the explanation you give every week — and open them next time instead of typing them out again. You can import one from a file as well.`,
      },
    ];
  }

  return [
    {
      h: "Hidden from the screen you are sharing",
      p: `The CueCard window is left out of screen capture by the operating system itself. On Zoom, Google Meet and Microsoft Teams the room sees your deck and never your notes — which is the whole reason ${who} keep it open.`,
    },
    {
      h: "Notes for the deck you already present from",
      p: "Paste them straight in and present from PowerPoint, Keynote, a PDF, or from nothing at all. If the deck is in Google Slides, the browser extension makes the notes change along with the slide.",
    },
    {
      h: "Cues you read but never say out loud",
      p: "Write [cue slow down] or [cue take a breath] into your notes and it appears in colour. It reminds you how to say the next part instead of handing you another line to get through.",
    },
    {
      h: "A timer that counts your slot down",
      p: `Set how long you have on the Set Timer pill and CueCard counts it down on screen while you talk. It is the plainest way ${who} keep a thirty-minute slot to thirty minutes.`,
    },
    {
      h: "A window that sits where you want it",
      p: "Move it, resize it, and fade it back over the slide behind it, so your notes are near the camera you are looking into rather than somewhere you have to go hunting for.",
    },
    {
      h: "Keyboard shortcuts for the whole thing",
      p: "Show and hide the window, move it, resize it, and start or reset the timer from the keyboard, without ever clicking away from what you are presenting.",
    },
  ];
}

/** The phone rows that could apply to an app that is not out yet. */
const mobilePlanned = mobile.filter((row) => !row.appleOnly);

module.exports = { mobile, mobilePlanned, desktop, forApp, forRole };
