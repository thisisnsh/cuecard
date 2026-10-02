// The FAQ bank.
//
// One file, grouped into sections. /faq/ renders every group; the home page
// and product pages carry selected questions. App and role pages add only
// price and account essentials where their own questions do not cover them, so
// every page earns a complete FAQPage block of its own instead of pointing at
// a shared one.
//
// Answers are plain sentences with a little inline HTML. Nothing here promises
// a capability the apps do not have.

const site = require("./site");
const store = site.ios;
const gh = "https://github.com/thisisnsh/cuecard";

/** Questions about the phone app — the product cuecard.dev now leads with. */
const mobile = [
  {
    question: "What is CueCard Teleprompter?",
    answer:
      'CueCard Teleprompter is a free teleprompter and cue cards app for iPhone, iPad and Apple Watch. The <a href="/teleprompter/">teleprompter</a> scrolls your script while you speak, full screen or in a small window above the camera, Instagram, TikTok or a video call. <a href="/cards/">Cards</a> shows a talk one card at a time, in the app, on the Lock Screen or on your <a href="/watch/">Apple Watch</a>. It is on <a href="' +
      store +
      '">the App Store</a> today, and the Android app is still being built.'
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
    question: "Can I use CueCard while recording an Instagram Reel or a TikTok?",
    answer:
      "Yes. The prompter floats above Instagram, TikTok, YouTube, Snapchat, LinkedIn, Facebook, X and your phone's own camera app. Record where you normally record; the script comes with you."
  },
  {
    question: "Is CueCard a free teleprompter app?",
    answer:
      'Yes. CueCard is free on iPhone and iPad, with no subscription, no trial and no paid tier, and the project is open source on <a href="' +
      gh +
      '" target="_blank" rel="noopener">GitHub</a>.'
  },
  {
    question: "Is CueCard available on Android?",
    answer:
      "Not yet. The Android app is still being built. The iPhone and iPad app is free and out now, and so is the app for Mac and Windows."
  },
  {
    question: "Is there a teleprompter for iPad?",
    answer:
      'Yes, and the iPad is the best screen CueCard runs on. Read the script full width at arm\'s length like a studio prompter, or shrink it into a floating window over the app you are filming in. <a href="/mobile/ipad/">See CueCard Teleprompter on iPad</a>.'
  },
  {
    question: "Which iPhones and iPads does CueCard support?",
    answer:
      "An iPhone or iPad running " + site.requiresMobile + ". The Apple Watch app needs " + site.requiresWatch + "."
  },
  {
    question: "Can I use it while live streaming or on a video call?",
    answer:
      "Yes. The prompter behaves the same whether you are recording, going live or on a call, and it stays above whatever is in front of it — the camera, social apps, streaming tools, meeting apps, a browser — for as long as you want it there."
  },
  {
    question: "What are cue tags?",
    answer:
      "A cue is a note to yourself in the middle of the script — <code>[cue smile]</code>, <code>[cue slow down]</code>, <code>[cue hold for two]</code>. CueCard draws it in its own colour so you take it in as a direction rather than reading it aloud. Tap Add Cue, or just type <code>[</code>, and the tag is written for you. Pick the colour every cue is drawn in from Settings."
  },
  {
    question: "How fast should the teleprompter scroll?",
    answer:
      "Most people speak somewhere between 120 and 160 words a minute, and read comfortably a little under that. CueCard sets the pace in lines per minute so you can nudge it up or down between takes until it matches how you actually talk, rather than making you speed up to catch it."
  },
  {
    question: "Can I pause the script or change its speed part-way through?",
    answer:
      "Yes. Pause it, start it again, or move the speed up and down while it is running. If a sentence needs more room than you gave it, you do not have to start the take over."
  },
  {
    question: "Is there a countdown before the script starts moving?",
    answer:
      "Yes. Tap the timer beside the play button and set a Countdown in seconds. CueCard counts you in before the script begins to scroll, so the first line is not the one you fumble while reaching for the record button."
  },
  {
    question: "Is there a timer?",
    answer:
      "Yes, in both modes. Tap the timer beside the play button, set a Duration, and choose when to be warned with Warn in Last. The timer changes color at the warning and again once you run over, in colors you pick. With no timer set, it counts up from when you started."
  },
  {
    question: "Can I change the size of the floating window?",
    answer:
      "Yes. You can make it rectangular or square, set its own text size, and drag it anywhere on screen. Make it big enough to read at arm's length and small enough to leave your face and the rest of your shot clear."
  },
  {
    question: "Can I change the text size on mobile?",
    answer:
      "Yes. The teleprompter, the floating window, cards and the editor each have their own text size, from presets in Settings. Tap Show Advanced Settings to type an exact size."
  },
  {
    question: "How do I keep my eyes on the camera while reading?",
    answer:
      "Move the floating window as close to the front camera as you can and make it small. The smaller the window and the nearer it sits to the lens, the shorter the glance away — on camera it reads as someone thinking, not someone reading."
  },
  {
    question: "Can I save scripts and come back to them?",
    answer:
      "Yes. Tap Unsaved below the top bar or choose ••• › Save to name and save a script or deck. Choose ••• › Open to see Saved Notes, search by title or text, and swipe a note to rename or delete it."
  },
  {
    question: "Can I restore an older version of a script or deck?",
    answer:
      "Yes, on iPhone and iPad. Saving changed text adds a version. Once a note has more than one version, tap the clock at the top of the editor to compare changes and restore an earlier version. Restoring adds a new version, so the history stays available."
  },
  {
    question: "How do I keep my notes if I delete the iPhone or iPad app?",
    answer:
      "Open Saved Notes with ••• › Open, then choose ••• › Choose Notes Folder. CueCard keeps the latest copy of each saved note as a text file in that folder, outside the app. Choose the same folder after reinstalling to bring the notes back. Without a notes folder, removing the app deletes its notes. Version history stays inside the app and is not included in the folder."
  },
  {
    question: "Can I edit saved notes outside CueCard?",
    answer:
      "Yes. On iPhone and iPad, choose a Notes Folder in Saved Notes. Changes to its text files come back into CueCard when it next syncs the folder, and new .txt or .md files become saved notes. The latest change wins if both copies have been edited."
  },
  {
    question: "Which files can I import on iPhone and iPad?",
    answer:
      "Choose ••• › Import to open plain text files, including .txt and .md, or an RTF file. Imported content becomes a saved note; RTF formatting is removed. Files larger than 10 MB are not imported. Use ••• › Share to send a script or deck as text, with its cues included."
  },
  {
    question: "Does the phone app have a dark mode?",
    answer:
      "Yes. You can set the app to light, set it to dark, or let it follow whatever your phone is already set to."
  },
  {
    question: "What is Cards mode?",
    answer:
      'Cue cards on your phone. Tap the mode name at the top left of the editor and choose Cards, write one short point per card, and tap Read Cards to swipe through them one at a time. It suits a speech, a toast or a class presentation, where you want reminders rather than a script. <a href="/cards/">See Cards</a>.'
  },
  {
    question: "Can I read cue cards on the Lock Screen?",
    answer:
      "Yes. In Cards Settings, turn on Show on Lock Screen. When a deck is open, the card you are on, the timer and Back and Next sit on the Lock Screen, so you can lock the phone and keep going. The Lock Screen shows up to 120 characters of a card."
  },
  {
    question: "Is there an Apple Watch app?",
    answer:
      'Yes, and it comes with the iPhone app. It plays, pauses and skips back ten seconds in the teleprompter, and shows your cards on your wrist in step with the iPhone. Keep a deck on the watch to read it without your iPhone. <a href="/watch/">See CueCard on Apple Watch</a>.'
  },
  {
    question: "Can I start the teleprompter with the Action Button?",
    answer:
      "Yes, on an iPhone with an Action Button and iOS 18. In the Settings app, go to Action Button › Controls and pick Play or Pause under CueCard."
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
      "With Invisible to Screen Sharing turned on in Settings, the CueCard window is excluded from screen shares and screen recordings on Mac and Windows. The Invisible button in the toolbar controls the same setting. Try one practice share before your call to check your setup."
  },
  {
    question: "Which meeting apps does CueCard work with?",
    answer:
      "Zoom, Google Meet, Microsoft Teams, Webex, Slack huddles, Discord — anything that shares a screen or a window. The notes are hidden at the operating-system level, not per app, so it is not a list you have to be on."
  },
  {
    question: "Which operating systems does the desktop app run on?",
    answer:
      "macOS and Windows. Both builds are on the downloads section and on the GitHub releases page."
  },
  {
    question: "Do I need Google Slides to use CueCard?",
    answer:
      "No. Type or paste your notes straight into CueCard and present from anything you like — PowerPoint, Keynote, a PDF, a browser, or nothing at all. Google Slides sync is one extra way to use CueCard, not something it needs to work."
  },
  {
    question: "Does CueCard work with PowerPoint, Keynote or a PDF?",
    answer:
      "Yes. CueCard runs alongside whatever you present from — it does not need to know what your deck is. Paste your notes in and present as usual."
  },
  {
    question: "How do I sync speaker notes from Google Slides?",
    answer:
      "Install the CueCard desktop app and browser extension. In CueCard, choose Google Slides and click Connect Google Slides, then authorize read-only access to your presentations with Google. Open your deck in the browser and present; the notes in CueCard follow the current slide. You can read them in the editor or press play to scroll them in the prompter."
  },
  {
    question: "Which browsers support the Google Slides extension?",
    answer: "Chrome, Firefox and Safari."
  },
  {
    question: "How do cue tags work?",
    answer:
      "A cue is a reminder to yourself about how to say the next part, rather than another line to read. Write <code>[cue slow down]</code> or <code>[cue pause here]</code> in the middle of your notes and CueCard draws it in colour, so you take it in as a direction instead of reading it out. Cues are optional."
  },
  {
    question: "Is there a timer for my slot?",
    answer:
      "Yes. Click Set Timer and choose a duration. The prompter counts down, warns you in the last fifth of the time and shows when you run over. With no duration set, it counts up. Changing slides does not reset the timer. Set the duration in the app; timing tags in the script are no longer used."
  },
  {
    question: "Does the desktop app scroll my script automatically?",
    answer:
      "Yes. Press play to open the prompter. In Settings, choose Scroll Speed in lines per minute, a Start Delay before scrolling begins, and Small, Medium or Large text. You can pause, go back ten seconds, restart or scroll by hand. Google Slides notes can scroll too."
  },
  {
    question: "Can I save, import and export scripts on desktop?",
    answer:
      "Yes. Choose Save as New from the ••• menu to name a script, then open it again from Scripts in the sidebar. Save updates the current script. Import from File and Export to File let you move scripts as text files, with cues included."
  },
  {
    question: "Which desktop keyboard shortcuts work from another app?",
    answer:
      "Hold Control and Option on Mac, or Ctrl and Alt on Windows: C shows or hides CueCard, Space plays or pauses, 0 restarts, minus and equals change opacity, and the arrow keys move the window. See Settings › Keyboard Shortcuts for the full list, including saving scripts and moving a line in the prompter."
  },
  {
    question: "Can I show CueCard during a meeting on purpose?",
    answer:
      "Yes. Turn Invisible to Screen Sharing off in Settings, or click the Invisible button in the toolbar. CueCard then appears in screen capture like any other window."
  },
  {
    question: "Can I change the window transparency?",
    answer:
      "Yes. There is a slider in Settings that fades the CueCard window back over your deck, so it can be as faint or as solid as you want it, and there are keyboard shortcuts for it too. Settings is also where you switch between light and dark."
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
      'Yes. Your notes, scripts and any Google token (used for Google Slides sync) stay on your device and are not uploaded. See the <a href="/privacy/">privacy policy</a> for the full details.'
  },
  {
    question: "Is there a mobile version?",
    answer:
      'Yes. CueCard for <a href="' +
      store +
      '">iPhone, iPad and Apple Watch</a> is a teleprompter that sits on top of the camera, Instagram, TikTok or any other app while you record, and cue cards you can turn from the Lock Screen or your wrist. Android is still being built. <a href="/mobile/">See the phone app</a>.'
  }
];

/** The handful worth repeating on every page, whichever product it is about. */
const everywhere = [
  {
    topic: "account",
    question: "Do I need an account to use CueCard?",
    answer:
      'No. There is nothing to sign up for on either app, and your scripts and settings live on your device. The one exception is Google Slides sync on the desktop app, which asks you to sign in with Google so it can read the notes out of your deck. See the <a href="/privacy/">privacy policy</a> for the details.'
  },
  {
    topic: "price",
    question: "Is CueCard free?",
    answer:
      'Yes. CueCard is completely free on mobile and on desktop, and open source. Read the code on <a href="' +
      gh +
      '" target="_blank" rel="noopener">GitHub</a> — and a star is always welcome.'
  },
  {
    question: "Is CueCard open source?",
    answer:
      'Yes, the code is on <a href="' +
      gh +
      '" target="_blank" rel="noopener">GitHub</a>. An app that can see your script is one worth being able to read the source of.'
  },
  {
    question: "Where are my scripts stored?",
    answer:
      'Your notes are stored on your device and are not uploaded to CueCard. On iPhone and iPad, you can also keep note files in a folder you choose in Files. If you choose a cloud-backed folder, that provider handles its storage and sync. Version history stays inside the iPhone or iPad app. See the <a href="/privacy/">privacy policy</a> for details.'
  },
  {
    question: "How do I report a bug or ask for a feature?",
    answer:
      'Open an issue on <a href="https://github.com/ThisIsNSH/CueCard/issues" target="_blank" rel="noopener">GitHub</a>, or email <a href="mailto:support@cuecard.dev">support@cuecard.dev</a>. Both are read.'
  }
];

/** Everything, grouped, for /faq/. */
const groups = [
  { id: "mobile", title: "The app for iPhone, iPad and Apple Watch", intro: "Filming, speaking from cue cards and going live.", items: mobile },
  { id: "desktop", title: "Speaker notes on Mac and Windows", intro: "Hidden from a screen share.", items: desktop },
  { id: "general", title: "Price, privacy and the project", intro: "The questions that apply wherever you run it.", items: everywhere }
];

/** Flat list, in group order — what /faq/ searches and what its schema carries. */
const items = groups.reduce((all, g) => all.concat(g.items), []);

/**
 * Add download essentials without repeating a topic covered by a page's own
 * wording. Project and support questions remain in /faq/ and the FAQ footer.
 */
function withGeneral(own) {
  return merge(own, everywhere.filter((q) => q.topic === "price" || q.topic === "account"));
}

/** Keep the first answer for a question or explicitly identified topic. */
function merge(first, second) {
  const asked = new Set();
  const topics = new Set();
  return (first || []).concat(second || []).filter((q) => {
    if (asked.has(q.question) || (q.topic && topics.has(q.topic))) return false;
    asked.add(q.question);
    if (q.topic) topics.add(q.topic);
    return true;
  });
}

/** Platform FAQs cover their own setup; avoid repeating the desktop bank. */
function forPlatform(platform) {
  const own = platform.faqJsonLd || [];
  if (platform.slug === "google-slides") {
    return withGeneral(merge(own, pick(
      "How do I sync speaker notes from Google Slides?",
      "Is CueCard invisible on Zoom, Google Meet and Microsoft Teams?",
      "Does the desktop app scroll my script automatically?",
      "Is there a timer for my slot?"
    )));
  }
  // The hero links here for the screen-sharing explanation.
  const questions = own.map((q, i) => i === 0 ? { ...q, id: "faq-undetectable" } : q);
  return withGeneral(merge(questions, pick(
    "Does the desktop app scroll my script automatically?",
    "Can I save, import and export scripts on desktop?",
    "Which operating systems does the desktop app run on?"
  )));
}

/** Product pages explain the app; recording pages answer recording questions. */
function forApp(app) {
  const selections = {
    mobile: [
      "What can the CueCard app do?",
      "Is CueCard available for iPhone and Android?",
      "Will the script appear in my video?",
      "Can I read cue cards on my Lock Screen?",
      "Is there an Apple Watch app?"
    ],
    "mobile/ios": [
      "How does the floating teleprompter work on iOS?",
      "Which iPhones does CueCard support?",
      "Does it work on iPad too?",
      "Can I use the Action Button to start the teleprompter?",
      "Does CueCard have cue cards as well as a teleprompter?"
    ],
    "mobile/ipad": [
      "Is there a teleprompter app for iPad?",
      "Can the iPad prompter float over other apps?",
      "Can I use an iPad as a teleprompter for a camera?",
      "Will the script appear in my video?"
    ]
  };
  if (selections[app.slug]) {
    const own = selections[app.slug].map((question) => app.faq.find((q) => q.question === question));
    return withGeneral(merge(own, pick(
      "Can I save scripts and come back to them?",
      "Can I restore an older version of a script or deck?"
    )));
  }
  // Android has its own release-status questions, without shipping-app claims.
  if (app.slug === "mobile/android") return app.faq;
  return withGeneral((app.faq || []).filter((q) => ![
    "What if the script moves too fast?",
    "What if CueCard covers a camera control?"
  ].includes(q.question)));
}

/** Pull named questions out of the bank, in the order asked for. */
function pick(...questions) {
  return questions
    .map((q) => items.find((i) => i.question === q))
    .filter(Boolean);
}

/**
 * The home page's bank - nine questions, not forty.
 *
 * The landing page used to print the phone bank, the desktop bank and the
 * general one end to end, which ran to a screen and a half of accordion
 * nobody opened. These are the nine questions people actually ask before
 * installing, in the order they ask them, and /faq/ still carries every one of
 * the rest.
 */
const home = pick(
  "What is CueCard Teleprompter?",
  "What is Cards mode?",
  "Is there an Apple Watch app?",
  "Does the teleprompter show up in my recorded video?",
  "Is CueCard a free teleprompter app?",
  "Do I need an account to use CueCard?",
  "Is there a teleprompter for iPad?",
  "Is CueCard available on Android?",
  "Is CueCard invisible on Zoom, Google Meet and Microsoft Teams?"
);

/** The trim for the desktop pages: what gets asked before downloading. */
const desktopShort = pick(
  "Is CueCard invisible on Zoom, Google Meet and Microsoft Teams?",
  "Do I need Google Slides to use CueCard?",
  "How do I sync speaker notes from Google Slides?",
  "How do cue tags work?",
  "Does the desktop app scroll my script automatically?",
  "Can I save, import and export scripts on desktop?",
  "Which operating systems does the desktop app run on?",
  "Do I need an account to use CueCard?",
  "Is CueCard free?"
);

module.exports = {
  items, groups, mobile, desktop, everywhere,
  home, desktopShort,
  pick, withGeneral, merge, forApp, forPlatform
};
