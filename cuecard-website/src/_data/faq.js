// The FAQ bank.
//
// One file, grouped into sections. /faq/ renders every group; the home page
// carries the mobile bank, /desktop/ the desktop one, and each app and role
// page carries its own questions followed by the small `everywhere` set, so
// every page earns a complete FAQPage block of its own instead of pointing at
// a shared one.
//
// Answers are plain sentences with a little inline HTML. Nothing here promises
// a capability the apps do not have.

const store = "https://apps.apple.com/app/cuecard-teleprompter/id6757321325";
const gh = "https://github.com/thisisnsh/cuecard";

/** Questions about the phone app — the product cuecard.dev now leads with. */
const mobile = [
  {
    question: "What is CueCard Teleprompter?",
    answer:
      'CueCard Teleprompter is a free teleprompter app for iPhone and iPad that floats on top of every other app. Your script sits in a small window above the camera, Instagram, TikTok, a video call or anything else, auto-scrolling while you speak, so you never have to switch away from what you are recording in. It is on <a href="' +
      store +
      '">iPhone and iPad</a> today, and the Android app is still being built.'
  },
  {
    question: "How does the floating teleprompter work?",
    answer:
      "CueCard opens a small window that stays above your other apps. You start the script scrolling, switch to your camera or whichever app you are recording in, and the window stays on top where you can read it. Because it sits on your screen and not in front of the lens, your camera never records it."
  },
  {
    question: "Does the teleprompter show up in my recorded video?",
    answer:
      "Not when you are filming with the camera. The prompter is a window on your screen rather than something in front of the lens, so the camera records you and your background and nothing else. Screen recording is the one exception: a screen recording captures your whole screen, prompter included, so close the prompter first if that is how you are recording. On a Mac or PC it works differently — <a href=\"/desktop/\">the desktop app</a> really is left out of screen capture."
  },
  {
    question: "Is CueCard a free teleprompter app?",
    answer:
      'Yes. CueCard is free on iPhone and iPad, with no subscription, no trial and no paid tier, and the project is open source under the MIT licence on <a href="' +
      gh +
      '" target="_blank" rel="noopener">GitHub</a>.'
  },
  {
    question: "Is CueCard available on Android?",
    answer:
      "Not yet. The Android app is still being built. The iPhone and iPad app is free and out now, and so is the app for Mac and Windows."
  },
  {
    question: "Which iPhones and iPads does CueCard support?",
    answer:
      "Any iPhone or iPad running iOS 17 or later."
  },
  {
    question: "Is there a teleprompter for iPad?",
    answer:
      'Yes, and the iPad is the best screen CueCard runs on. Read the script full width at arm\'s length like a studio prompter, or shrink it into a floating window over the app you are filming in. <a href="/mobile/ipad/">See CueCard Teleprompter on iPad</a>.'
  },
  {
    question: "Can I use CueCard while recording an Instagram Reel or a TikTok?",
    answer:
      "Yes. The prompter floats above Instagram, TikTok, YouTube, Snapchat, LinkedIn, Facebook, X and your phone's own camera app. Record where you normally record; the script comes with you."
  },
  {
    question: "Can I use it while live streaming?",
    answer:
      "Yes. The prompter behaves the same whether you are recording, going live or on a video call — it stays above the app you are in for as long as you want it there."
  },
  {
    question: "How fast should the teleprompter scroll?",
    answer:
      "Most people speak somewhere between 120 and 160 words a minute, and read comfortably a little under that. CueCard sets the pace in lines per minute so you can nudge it up or down between takes until it matches how you actually talk, rather than making you speed up to catch it."
  },
  {
    question: "How do I keep my eyes on the camera while reading?",
    answer:
      "Move the floating window as close to the front camera as you can and make it small. The smaller the window and the nearer it sits to the lens, the shorter the glance away — on camera it reads as someone thinking, not someone reading."
  },
  {
    question: "Can I change the size of the floating window?",
    answer:
      "Yes. You can make it wide, square or tall, set its own text size, and drag it anywhere on screen. Make it big enough to read at arm's length and small enough to leave your face and the rest of your shot clear."
  },
  {
    question: "Can I change the text size on mobile?",
    answer:
      "Yes. Small, medium and large presets are available for both the in-app prompter and the floating one, so you can read comfortably at whatever distance you have set your phone up at."
  },
  {
    question: "What are cue tags?",
    answer:
      "A cue is a note to yourself in the middle of the script — <code>[cue smile]</code>, <code>[cue slow down]</code>, <code>[cue hold for two]</code>. CueCard draws it in its own colour so you take it in as a direction rather than reading it aloud. Tap Add Cue, or just type <code>[</code>, and the tag is written for you."
  },
  {
    question: "Can I change the cue colour?",
    answer:
      "Yes. Pick the colour every cue is drawn in from Settings, so cues stand as far away from the script as you want them to."
  },
  {
    question: "Is there a countdown before the script starts moving?",
    answer:
      "Yes. Set a start delay and CueCard counts you in before the script begins to scroll, so the first line is not the one you fumble while reaching for the record button."
  },
  {
    question: "Is there a timer?",
    answer:
      "Yes. Set a length in minutes and seconds and the timer runs while you speak, so you find out a take is running long while you can still do something about it, rather than in the edit."
  },
  {
    question: "Can I pause the script or change its speed part-way through?",
    answer:
      "Yes. Pause it, start it again, or move the speed up and down while it is running. If a sentence needs more room than you gave it, you do not have to start the take over."
  },
  {
    question: "Can I save scripts and come back to them?",
    answer:
      "Yes. Save a script with a name and it stays in your library, ready to open, rename or run again."
  },
  {
    question: "Does the phone app have a dark mode?",
    answer:
      "Yes. You can set the app to light, set it to dark, or let it follow whatever your phone is already set to."
  },
  {
    question: "Do I need an account to use the phone app?",
    answer:
      'You sign in with Google to use the app. Your scripts and settings live on your device, and you can delete your account from Settings whenever you like. See the <a href="/privacy/">privacy policy</a> for the details.'
  },
  {
    question: "Can I use the phone app with any other app?",
    answer:
      "Yes. The camera, social apps, streaming tools, meeting apps, a browser — the prompter stays on top of whatever is in front of it."
  },
  {
    question: "How is this different from a hardware teleprompter?",
    answer:
      "A hardware rig puts a mirror in front of your lens and costs real money to buy and carry. CueCard puts the script on the screen you are already holding. It is not identical — a beam-splitter rig puts your eyes dead centre on the lens — but for a phone shot filmed anywhere, at no cost, it gets you most of the way there."
  },
  {
    question: "Is there a desktop version of CueCard?",
    answer:
      'Yes. CueCard for Mac and Windows keeps your speaker notes on your screen and out of your screen share on Zoom, Google Meet and Microsoft Teams. Paste your notes in to use it with any deck, or add the browser extension so notes from Google Slides follow your slides. <a href="/desktop/">See the desktop app</a>.'
  }
];

/** Questions about the Mac and Windows app. */
const desktop = [
  {
    // The anchor the desktop hero's "and more..." link has always pointed at.
    id: "faq-undetectable",
    question: "Is CueCard invisible on Zoom, Google Meet and Microsoft Teams?",
    answer:
      "Yes. CueCard is designed to be undetectable on Zoom, Microsoft Teams, Google Meet and similar apps: it is excluded from screen capture, so your speaker notes stay off the shared screen while your deck goes out normally. Run one practice call to confirm it behaves as you expect with your setup."
  },
  {
    question: "Can other people see my notes during screen sharing or a recording?",
    answer:
      "No. On Mac and Windows the CueCard window is left out of screen shares and screen recordings by the operating system itself. If you want to be sure before a call, check that Ghost Mode is turned on in Settings and try one practice share."
  },
  {
    question: "Which meeting apps does CueCard work with?",
    answer:
      "Zoom, Google Meet, Microsoft Teams, Webex, Slack huddles, Discord — anything that shares a screen or a window. The notes are hidden at the operating-system level, not per app, so it is not a list you have to be on."
  },
  {
    question: "Can I show CueCard during a meeting on purpose?",
    answer:
      "Yes. Turn Ghost Mode off in Settings and CueCard appears in the share like any other window, for when you want to walk people through the notes themselves."
  },
  {
    question: "Do I need Google Slides to use CueCard?",
    answer:
      "No. Type or paste your notes straight into CueCard and present from anything you like — PowerPoint, Keynote, a PDF, a browser, or nothing at all. Google Slides sync is one extra way to use CueCard, not something it needs to work."
  },
  {
    question: "How do I sync speaker notes from Google Slides?",
    answer:
      "Two things have to be installed: the CueCard app for Mac or Windows, which is the window your notes appear in, and the CueCard browser extension, which reads the notes out of your deck. With both in place, open your presentation and the notes for the slide you are on show up in CueCard and change as you move through the deck."
  },
  {
    question: "Which browsers support the Google Slides extension?",
    answer: "Chrome, Firefox and Safari."
  },
  {
    question: "Does CueCard work with PowerPoint, Keynote or a PDF?",
    answer:
      "Yes. CueCard runs alongside whatever you present from. Paste your notes in and present as usual."
  },
  {
    question: "How do the timer and note tags work?",
    answer:
      "Write <code>[time mm:ss]</code> where you want a section timed, and <code>[cue something]</code> where you want to remind yourself how to say the next part. The older <code>[note something]</code> spelling still works. Time tags count down on screen and cues are shown in colour, so you catch both without reading either of them out. Both are optional."
  },
  {
    question: "Can I change the window transparency?",
    answer:
      "Yes. There is a slider in Settings that fades the CueCard window back over your deck, so it can be as faint or as solid as you want it. There are keyboard shortcuts for it too."
  },
  {
    question: "Does CueCard have a light mode?",
    answer: "Yes. Switch between light and dark in Settings."
  },
  {
    question: "Which operating systems does the desktop app run on?",
    answer:
      "macOS and Windows. Both builds are on the downloads section and on the GitHub releases page."
  },
  {
    question: "Does it work with two monitors?",
    answer:
      "Yes. Put CueCard on whichever display you like — it stays out of the shared screen either way, so it does not matter which one you are sharing."
  },
  {
    question: "Can I use CueCard for a webinar or a recorded demo?",
    answer:
      "Yes. Anything that captures the screen — a webinar platform, a Loom, a QuickTime recording, OBS — gets your deck without the notes."
  },
  {
    question: "Is my data safe?",
    answer:
      'Your notes and Google tokens stay on your device and are not uploaded. See the <a href="/privacy/">privacy policy</a> for the full details.'
  },
  {
    question: "Is there a mobile version?",
    answer:
      'Yes. CueCard for <a href="' +
      store +
      '">iPhone and iPad</a> is a teleprompter that sits on top of the camera, Instagram, TikTok or any other app while you record, so you never have to switch apps in the middle of a take. Android is still being built. <a href="/">See the phone app</a>.'
  }
];

/** The handful worth repeating on every page, whichever product it is about. */
const everywhere = [
  {
    question: "Is CueCard free?",
    answer:
      'Yes. CueCard is completely free on mobile and on desktop, and open source under the MIT licence. Read the code on <a href="' +
      gh +
      '" target="_blank" rel="noopener">GitHub</a> — and a star is always welcome.'
  },
  {
    question: "Is CueCard open source?",
    answer:
      'Yes, MIT licensed, on <a href="' +
      gh +
      '" target="_blank" rel="noopener">GitHub</a>. An app that can see your script is one worth being able to read the source of.'
  },
  {
    question: "Where are my scripts stored?",
    answer:
      'On your device. Your notes are not uploaded to us. The <a href="/privacy/">privacy policy</a> sets out exactly what is and is not kept.'
  },
  {
    question: "How do I report a bug or ask for a feature?",
    answer:
      'Open an issue on <a href="https://github.com/ThisIsNSH/CueCard/issues" target="_blank" rel="noopener">GitHub</a>, or email <a href="mailto:hello@thisisnsh.com">hello@thisisnsh.com</a>. Both are read.'
  }
];

/** Everything, grouped, for /faq/. */
const groups = [
  { id: "mobile", title: "The teleprompter on iPhone and iPad", intro: "Filming, recording and going live.", items: mobile },
  { id: "desktop", title: "Speaker notes on Mac and Windows", intro: "Hidden from a screen share.", items: desktop },
  { id: "general", title: "Price, privacy and the project", intro: "The questions that apply wherever you run it.", items: everywhere }
];

/** Flat list, in group order — what /faq/ searches and what its schema carries. */
const items = groups.reduce((all, g) => all.concat(g.items), []);

/**
 * A page-sized bank: the page's own questions, then the general ones it has
 * not already asked. Keeps every FAQPage block complete without repeating a
 * question twice on one page.
 */
function withGeneral(own) {
  const asked = new Set((own || []).map((q) => q.question));
  return (own || []).concat(everywhere.filter((q) => !asked.has(q.question)));
}

/** Concatenate two banks, dropping any question the first one already asks. */
function merge(first, second) {
  const asked = new Set((first || []).map((q) => q.question));
  return (first || []).concat((second || []).filter((q) => !asked.has(q.question)));
}

/** Pull named questions out of the bank, in the order asked for. */
function pick(...questions) {
  return questions
    .map((q) => items.find((i) => i.question === q))
    .filter(Boolean);
}

/**
 * The home page's bank - eight questions, not forty.
 *
 * The landing page used to print the phone bank, the desktop bank and the
 * general one end to end, which ran to a screen and a half of accordion
 * nobody opened. These are the eight people actually ask before installing,
 * in the order they ask them, and /faq/ still carries every one of the rest.
 */
const home = pick(
  "What is CueCard Teleprompter?",
  "Does the teleprompter show up in my recorded video?",
  "Can I use CueCard while recording an Instagram Reel or a TikTok?",
  "Is CueCard a free teleprompter app?",
  "Is there a teleprompter for iPad?",
  "Is CueCard available on Android?",
  "Is CueCard invisible on Zoom, Google Meet and Microsoft Teams?",
  "How is this different from a hardware teleprompter?"
);

/** The trim for the desktop pages: what gets asked before downloading. */
const desktopShort = pick(
  "Is CueCard invisible on Zoom, Google Meet and Microsoft Teams?",
  "Can other people see my notes during screen sharing or a recording?",
  "How do I sync speaker notes from Google Slides?",
  "Does CueCard work with PowerPoint, Keynote or a PDF?",
  "Which operating systems does the desktop app run on?",
  "Is CueCard free?"
);

module.exports = {
  items, groups, mobile, desktop, everywhere,
  home, desktopShort,
  pick, withGeneral, merge
};
