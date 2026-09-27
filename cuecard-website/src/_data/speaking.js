// The pages about one part of the phone app: /teleprompter/, /cards/ and
// /watch/, and the speaking pages under /cards/ for the talks people give from
// cue cards. Rendered by src/speaking/page.njk.
//
// Every label here was checked against the iOS app source (HomeView,
// SettingsView, TimerSheet, HelpView, CueCards and the watch app) on
// 2026-09-26. Change a label in the app and change it here.
//
// A card in `cards` is a string; [cue ...] in it is drawn in the cue color. A
// line in `deck` is { t } or { cue }, as in _data/deck.js.

const site = require("./site");
const store = site.ios;

const cardLimit = 280;
const lockScreenLimit = 120;

// ── The three parts of the app ─────────────────────────────────────────────

const teleprompter = {
  slug: "teleprompter",
  kind: "mode",
  icon: "scroll",
  name: "Teleprompter",
  title: "Free Teleprompter App That Floats Over Other Apps | CueCard",
  description:
    "A free teleprompter for iPhone and iPad. Your script scrolls at the speed you set, floats over the camera, TikTok or a call, and shows cues and a timer.",
  keywords:
    "teleprompter app, free teleprompter, teleprompter app iphone, floating teleprompter, auto scroll teleprompter, teleprompter for video, teleprompter with timer, teleprompter over camera app",
  h1: "A teleprompter that <em>floats over every app.</em>",
  lede:
    "Your script scrolls at the speed you set, full screen or in a small window on top of the camera, Instagram, TikTok or a video call. Cues show you how to say it, and a timer tells you when to wrap up.",
  demo: "prompter",
  deck: [
    { t: "Hi, I'm Sam, and this is the one thing I wish I'd known sooner." },
    { cue: "smile" },
    { t: "You don't need to memorise a script to sound natural on camera." },
    { cue: "slow down" },
    { t: "Put it right under the lens and let it scroll at the pace you talk." },
    { cue: "pause" },
    { t: "Your eyes stay on the camera, and your words stay yours." },
    { cue: "lean in" },
    { t: "Try it on your next take." },
  ],
  rowsHeading: "Everything the teleprompter does",
  rows: [
    {
      h: "Scrolls at the speed you set",
      p: "Set Scroll Speed in lines per minute and the script moves on its own. It keeps the pace you set rather than listening to your voice, so a pause never makes it jump. Drag it back or ahead and it carries on from where you leave it.",
    },
    {
      h: "Floats over the app you film in",
      p: "Leave CueCard while the teleprompter is open and your script keeps going in a floating window above the camera, Instagram, TikTok, YouTube or a video call. The camera records you, not the window. A screen recording does include it.",
    },
    {
      h: "A window shaped to fit your shot",
      p: "Choose a 16:9, 4:3 or square layout and give the floating window its own text size, apart from the full-screen one. Drag it up under the front camera so your eyes barely move.",
    },
    {
      h: "A countdown, a timer and a warning",
      p: "A countdown gives you a few seconds before the script starts to move. The timer runs while you talk, changes color when you are near the end and again when you run over, in colors you pick.",
    },
    {
      h: "Play and pause from your watch or the Action Button",
      p: "The Apple Watch app plays, pauses and skips back ten seconds, and shows the timer. On an iPhone with an Action Button and iOS 18, set it to Play or Pause and start the script without touching the screen.",
    },
    {
      h: "Cues you read but never say",
      p: "Write [cue smile] or [cue pause] into the script and it shows in color as it passes, a reminder of how to say the next line rather than another line to read.",
    },
  ],
  shotIds: ["teleprompter"],
  shotsNote: "In a floating window over the home screen, and full screen with the timer running.",
  guide: {
    heading: "How to use the teleprompter on iPhone",
    intro: "Six steps from an empty page to your first take.",
    steps: [
      {
        title: "Choose Teleprompter",
        body: "Tap the mode name at the top left of the editor and pick Teleprompter. Cards keeps its own script, so switching never mixes the two.",
      },
      {
        title: "Write, paste or import the script",
        body: "Type or paste into the editor, or use Import from File in the ••• menu. Type [ or tap Add Cue for a reminder, and choose Save as New to keep a named copy in Saved Content.",
      },
      {
        title: "Set the speed and text size",
        body: "Tap the gear for Teleprompter Settings. Set Scroll Speed and Text Size, and under Floating Window pick a Text Size and a Layout that leaves your camera controls clear.",
      },
      {
        title: "Set the timer and countdown",
        body: "Tap the timer beside the play button. Set a Duration, choose when to be warned with Warn in Last, and add a Countdown so you have time to get ready before the script moves.",
      },
      {
        title: "Press play",
        body: "Tap the green play button to open the teleprompter full screen. The buttons fade while it scrolls; tap the screen to bring them back.",
      },
      {
        title: "Float it over your camera",
        body: "Tap the picture-in-picture button, or simply leave CueCard, and the script keeps going in a floating window. Open your camera or recording app and drag the window up under the lens.",
      },
    ],
    sample:
      "Hi, I'm Sam, and this is the one thing I wish I'd known sooner. [cue smile]\nYou don't need to memorise a script to sound natural on camera. [cue slow down]\nPut it right under the lens and let it scroll at the pace you talk. [cue pause]\nYour eyes stay on the camera, and your words stay yours.\nTry it on your next take.",
  },
  faq: [
    {
      question: "What is a teleprompter app?",
      answer:
        "A teleprompter app shows your script on the screen and scrolls it while you speak, so you can read it without memorising it or looking down at paper. CueCard's teleprompter scrolls at the speed you set and can float over other apps, so you can read while you record in the app you already use.",
    },
    {
      question: "Does the teleprompter follow my voice?",
      answer:
        "No. It scrolls at the speed you set in lines per minute and keeps that pace. If you need a moment, pause it, or drag the script back and it carries on from there.",
    },
    {
      question: "Will the floating teleprompter show up in my video?",
      answer:
        "Not in a camera recording: the camera films you, not your screen. A screen recording or a screen broadcast captures the whole screen, so it would include the window.",
    },
    {
      question: "Can I control the teleprompter without touching my phone?",
      answer:
        'Yes. The <a href="/watch/">Apple Watch app</a> plays, pauses and skips back ten seconds. On an iPhone with an Action Button and iOS 18, go to Settings › Action Button › Controls and choose Play or Pause under CueCard.',
    },
    {
      question: "Is there a countdown before the script starts?",
      answer:
        "Yes. Tap the timer beside the play button and set a Countdown in seconds. The script waits that long before it starts to scroll.",
    },
  ],
  links: [
    { href: "/mobile/ios/#how-to", label: "Set up on iPhone" },
    { href: "/mobile/ipad/#how-to", label: "Read from an iPad" },
    { href: "/mobile/tiktok/#how-to", label: "Record a TikTok" },
    { href: "/mobile/instagram/#how-to", label: "Record an Instagram Reel" },
    { href: "/cards/", label: "Speak from cue cards instead" },
    { href: "/watch/", label: "Control it from Apple Watch" },
  ],
};

const cards = {
  slug: "cards",
  kind: "mode",
  icon: "cards",
  name: "Cards",
  title: "Free Cue Cards App for iPhone & Apple Watch | CueCard",
  description:
    "Digital cue cards for speeches and presentations. Swipe through one card at a time, turn them from the Lock Screen or your Apple Watch, with a timer.",
  keywords:
    "cue cards app, digital cue cards, cue card app iphone, speech cards app, note cards for speech, speech notes app, presentation cue cards, cue cards on lock screen, apple watch cue cards",
  h1: "Cue cards that <em>never fall out of order.</em>",
  lede:
    "Write your talk as a deck of short cards and swipe through them one at a time, in the app, on your Lock Screen or on your Apple Watch. A timer keeps you on time, and cues remind you how to say each point.",
  demo: "cards",
  cards: [
    "Good evening, everyone. Thank you for coming. [cue smile]",
    "Three years ago this was an idea on a napkin. [cue pause]",
    "Tonight it has 40 people and its first customers.",
    "Thank you to the team, who made the napkin real. [cue look at them]",
    "Now, the part you came for: the food. [cue raise glass]",
  ],
  rowsHeading: "Everything Cards does",
  rows: [
    {
      h: "One card, one thought",
      p: `Each box in the editor is one card; tap Create New Card to add the next. A card holds up to ${cardLimit} characters, and as you near the limit a count appears and anything over it is marked, so every card stays short enough to take in at a glance.`,
    },
    {
      h: "Swipe, or tap Back and Next",
      p: "Read Cards opens the deck one card at a time. Swipe to turn, or tap Back and Next, and the dots at the top show where you are. At the end, swipe back for the last card or start over.",
    },
    {
      h: "On your Lock Screen",
      p: `Turn on Show on Lock Screen and the card you are on, the timer and Back and Next sit on your Lock Screen as a Live Activity, so you can put the phone down, lock it and keep going. Cards longer than ${lockScreenLimit} characters are cut short there.`,
    },
    {
      h: "On your Apple Watch",
      p: "Open a deck on your iPhone and it shows on the watch too; turning a card on either moves both. Keep a saved deck on the watch and you can speak from your wrist with the iPhone in your pocket, or not with you at all.",
    },
    {
      h: "A timer that warns you",
      p: "Set how long you have and when to be warned. The time at the top counts down and changes color at the warning and when you run over, on the phone, the Lock Screen and the watch. With no timer set, it counts up from when you started.",
    },
    {
      h: "Cues on every card",
      p: "Add [cue pause] or [cue smile] and it shows in color on the card, wherever you are reading it. Cards has its own cue color and text size, apart from the teleprompter's.",
    },
    {
      h: "Decks you save and share as text",
      p: "Save a deck and open it again from Saved Content. Export it as a text file, or import one: a [separator] line between cards splits it into a deck.",
    },
  ],
  shotIds: ["cards"],
  shotsNote: "Swiping to the next card in the app, and the same deck on the Lock Screen with Back and Next.",
  guide: {
    heading: "How to make cue cards on iPhone",
    intro: "From an empty deck to speaking from your Lock Screen or watch, in six steps.",
    steps: [
      {
        title: "Switch to Cards",
        body: "Tap the mode name at the top left of the editor and pick Cards. Cards has its own deck and settings, apart from the teleprompter's script.",
      },
      {
        title: "Write one thought per card",
        body: `Type the first card in the first box, then tap Create New Card for the next. Keep each under ${cardLimit} characters, or ${lockScreenLimit} if you will read from the Lock Screen.`,
      },
      {
        title: "Add cues and save the deck",
        body: "Type [ or tap Add Cue for reminders like [cue pause]. Choose Save as New in the ••• menu to keep the deck in Saved Content.",
      },
      {
        title: "Set a timer",
        body: "Tap the timer beside Read Cards, set the Duration and choose when to be warned with Warn in Last. Leave it at 0:00 and the timer counts up instead.",
      },
      {
        title: "Tap Read Cards",
        body: "The deck opens one card at a time. Swipe or tap Back and Next to move through it.",
      },
      {
        title: "Read from the Lock Screen or your watch",
        body: "Tap the gear for Cards Settings and turn on Show on Lock Screen, then lock your iPhone and turn cards from there. With the watch app installed, the deck is on your wrist as well.",
      },
    ],
    sampleIntro: "One card per paragraph: type each into its own box in CueCard. The [cue ...] tags are reminders to yourself, not words to say.",
    sample:
      "Good evening, everyone. Thank you for coming. [cue smile]\n\nThree years ago this was an idea on a napkin. [cue pause]\n\nTonight it has 40 people and its first customers.\n\nThank you to the team, who made the napkin real. [cue look at them]\n\nNow, the part you came for: the food. [cue raise glass]",
  },
  faq: [
    {
      question: "What are digital cue cards?",
      answer:
        "Cue cards are short notes, one point per card, that you glance at while you speak instead of reading a full script. CueCard's Cards mode puts them on your iPhone, iPad or Apple Watch: one card on screen at a time, turned with a swipe, with a timer and colored cues.",
    },
    {
      question: "How much should I write on each cue card?",
      answer: `One thought, in as few words as will remind you of it. CueCard allows ${cardLimit} characters a card and marks anything over. If you read from the Lock Screen, keep it under ${lockScreenLimit}, which is what the Lock Screen shows. <a href="/blog/how-much-to-write-on-a-cue-card/">More on writing cue cards</a>.`,
    },
    {
      question: "Can I read my cue cards from the Lock Screen?",
      answer:
        "Yes. In Cards Settings, turn on Show on Lock Screen. When you open a deck, the card you are on, the timer and Back and Next buttons appear on the Lock Screen, so you can lock your iPhone and keep going.",
    },
    {
      question: "Can I use cue cards on Apple Watch?",
      answer:
        'Yes. Open a deck on your iPhone and it shows on the watch too, and turning a card on either moves both. Choose Keep on Apple Watch from the ••• menu on a saved deck to read it on the watch without your iPhone. <a href="/watch/">See CueCard on Apple Watch</a>.',
    },
    {
      question: "Should I use cue cards or a teleprompter?",
      answer:
        'Use the <a href="/teleprompter/">teleprompter</a> when you need every word, like a video you film to camera. Use cards when you know what you want to say and only need the next point, like a speech, a toast or a class presentation. CueCard has both, and you switch between them from the mode name. <a href="/blog/cue-cards-vs-teleprompter/">Cue cards vs a teleprompter</a>.',
    },
    {
      question: "Can I import cue cards from a text file?",
      answer:
        "Yes. Use Import from File in the ••• menu. Put a [separator] line between cards and each part becomes its own card. Export to File writes a deck out the same way.",
    },
  ],
  links: [
    { href: "/cards/wedding-speech/", label: "Cue cards for a wedding speech" },
    { href: "/cards/class-presentations/", label: "Cue cards for a class presentation" },
    { href: "/cards/public-speaking/", label: "Cue cards for public speaking" },
    { href: "/cards/sermons/", label: "Sermon notes on iPhone and Apple Watch" },
    { href: "/watch/", label: "Cue cards on Apple Watch" },
    { href: "/blog/cue-cards-vs-teleprompter/", label: "Cue cards vs a teleprompter" },
  ],
};

const watch = {
  slug: "watch",
  kind: "mode",
  icon: "watch",
  name: "Apple Watch",
  title: "Apple Watch Teleprompter Remote & Cue Cards | CueCard",
  description:
    "Play and pause the CueCard teleprompter from your Apple Watch, and read cue cards on your wrist, in step with your iPhone or on their own. Free.",
  keywords:
    "apple watch teleprompter, teleprompter remote apple watch, apple watch cue cards, speech notes apple watch, apple watch speaker notes, notes on apple watch for speech, apple watch presentation remote",
  h1: "Your notes, <em>on your wrist.</em>",
  lede:
    "The CueCard app for Apple Watch is a remote for the teleprompter and a place to read your cue cards. Glance down, turn a card, and keep talking with your phone out of sight.",
  demo: "watch",
  cards: [
    "Open with the story about the lost keys. [cue smile]",
    "Why it matters: we spend 12 minutes a day looking for things.",
    "The fix fits on a key ring. [cue hold it up]",
    "Ask: who's lost their keys this week? [cue pause]",
  ],
  rowsHeading: "What the watch app does",
  rows: [
    {
      h: "A remote for the teleprompter",
      p: "Open a script on your iPhone and the watch shows its timer, with buttons to play, pause and go back ten seconds. Start the script from across the room without walking back to the phone.",
    },
    {
      h: "Cue cards on your wrist, in step with the iPhone",
      p: "Open a deck on the iPhone and it shows on the watch too. Turn a card on either one and both move, so the phone on the lectern and the watch on your wrist never disagree.",
    },
    {
      h: "Decks kept on the watch",
      p: "Choose Keep on Apple Watch from the ••• menu on a saved deck, and it stays on the watch to read with no iPhone nearby. Remove it the same way when you are done.",
    },
    {
      h: "Easy to read at a glance",
      p: "Cues show in color and the timer runs at the top. Set the watch's Card Text Size from the iPhone's Cards Settings, and turn the Digital Crown to scroll a longer card.",
    },
    {
      h: "Stays up while you talk",
      p: "Your watch goes back to the clock after a while. In the Watch app, set General › Return to Clock › CueCard to 1 hour and your notes stay on screen.",
    },
    {
      h: "Free, with the iPhone app",
      p: `There is nothing extra to buy. The watch app comes with CueCard for iPhone and needs ${site.requiresWatch}.`,
    },
  ],
  shotIds: [],
  guide: {
    heading: "How to set up CueCard on Apple Watch",
    intro: "Install it once, then open a script or a deck on your iPhone.",
    steps: [
      {
        title: "Install the watch app",
        body: "Open the Watch app on your iPhone. Under Available Apps, tap Install next to CueCard. If your watch is paired and the app is missing, CueCard's Settings also shows Install on Apple Watch.",
      },
      {
        title: "Use it as a teleprompter remote",
        body: "Open a script in Teleprompter mode on your iPhone and press play. The watch shows the timer, with play, pause and back 10 seconds.",
      },
      {
        title: "Read cards on the watch",
        body: "Switch to Cards on your iPhone and tap Read Cards. The deck shows on the watch too; turning a card on either one moves both.",
      },
      {
        title: "Keep a deck on the watch",
        body: "Open a saved deck on the iPhone and choose Keep on Apple Watch from the ••• menu. It is then on the watch under On Watch, and works without your iPhone.",
      },
      {
        title: "Set the text size",
        body: "On the iPhone, tap the gear in Cards mode and choose Card Text Size under Apple Watch.",
      },
      {
        title: "Keep it on screen",
        body: "In the Watch app on your iPhone, go to General › Return to Clock › CueCard and set it to 1 hour.",
      },
    ],
  },
  faq: [
    {
      question: "Is there a teleprompter app for Apple Watch?",
      answer:
        "CueCard's watch app controls the teleprompter on your iPhone: it shows the timer and plays, pauses and goes back ten seconds. The script itself is read on the iPhone or iPad; the watch is for cue cards, which are short enough to read on your wrist.",
    },
    {
      question: "Can I read speech notes on my Apple Watch?",
      answer:
        "Yes. Write your notes as a deck in Cards mode, and they show on the watch one card at a time. Turn cards on the watch or the iPhone, and the two stay in step.",
    },
    {
      question: "Does the watch app work without my iPhone?",
      answer:
        "For decks you keep on the watch, yes. Choose Keep on Apple Watch from the ••• menu on a saved deck, and you can read it on the watch with no iPhone nearby. The teleprompter remote needs the iPhone, because that is where the script is scrolling.",
    },
    {
      question: "Which Apple Watch do I need?",
      answer: `One running ${site.requiresWatch}, paired with an iPhone running ${site.products.mobile.platforms[0].os.split(",")[0]}.`,
    },
    {
      question: "Why does my watch go back to the clock?",
      answer:
        "The watch returns to the clock after a while by default. In the Watch app on your iPhone, go to General › Return to Clock › CueCard and set it to 1 hour.",
    },
  ],
  links: [
    { href: "/cards/", label: "Cue cards on iPhone" },
    { href: "/teleprompter/", label: "The teleprompter" },
    { href: "/cards/sermons/", label: "Sermon notes on Apple Watch" },
    { href: "/cards/public-speaking/", label: "Cue cards for public speaking" },
    { href: "/blog/speech-notes-on-apple-watch/", label: "Speech notes on Apple Watch" },
  ],
};

// ── Speaking pages, under /cards/ ──────────────────────────────────────────

/** The steps every speaking page ends on, around the page's own opening. */
const speechSteps = (first, second) => [
  first,
  second,
  {
    title: "Add cues where you rush",
    body: "Type [ or tap Add Cue for reminders like [cue pause] or [cue look up]. They show in color and are never read out.",
  },
  {
    title: "Set a timer with a warning",
    body: "Tap the timer beside Read Cards, set how long you have, and use Warn in Last so the time changes color before you run over.",
  },
  {
    title: "Rehearse with Read Cards",
    body: "Tap Read Cards and run the whole deck out loud, swiping or tapping Next. Cut any card you have to squint at.",
  },
  {
    title: "Speak from your Lock Screen or watch",
    body: "Turn on Show on Lock Screen in Cards Settings to turn cards with the phone locked, or keep the deck on your Apple Watch and leave the phone in your pocket.",
  },
];

const speeches = [
  {
    slug: "cards/wedding-speech",
    kind: "speech",
    icon: "cards",
    name: "Wedding speech",
    title: "Cue Cards for a Wedding Speech or Toast | CueCard",
    description:
      "Give a best man, maid of honor or parent's wedding speech from cue cards on your iPhone or Apple Watch. A timer, colored cues and no paper to drop.",
    keywords:
      "wedding speech cue cards, best man speech cue cards, maid of honor speech notes, wedding toast notes app, wedding speech app, speech notes on phone",
    h1: "Wedding speech cue cards, <em>on your phone.</em>",
    lede:
      "A best man, maid of honor or parent's speech is three to five minutes of stories you know by heart and lines you don't. Put each on its own card, swipe through them with a glass in the other hand, and let a timer tell you when to raise it.",
    cards: [
      "For those who don't know me, I'm Jess, Emma's sister. [cue smile]",
      "Story: Emma, age nine, and the hamster in the post box.",
      "Then she met Tom. First thing she told me: he fixed my bike.",
      "What I love about them together: they still laugh at the same things. [cue look at them]",
      "Please raise your glasses: to Emma and Tom. [cue raise glass]",
    ],
    rowsHeading: "Why cards beat paper at a wedding",
    rows: [
      {
        h: "One story per card",
        p: "A card holds the one line that gets you into each story: the hamster, the bike, the first dance. You tell the rest from memory, looking at the room rather than a sheet of A4.",
      },
      {
        h: "Nothing to drop, fold or lose",
        p: "The deck is on the phone already in your jacket. Turn cards from the Lock Screen, or keep them on your Apple Watch and keep both hands for the microphone and the glass.",
      },
      {
        h: "A timer for a speech that stays short",
        p: "Set four minutes with a warning at one minute left. The time changes color when it is time to move to the toast, which is the part everyone is waiting for.",
      },
      {
        h: "Cues for the moments that matter",
        p: "Mark where to pause for the laugh, where to look at the couple and when to raise your glass. They show in color, so you catch them without reading them out.",
      },
    ],
    guide: {
      heading: "How to put a wedding speech on cue cards",
      intro: "Write the speech first. Then turn it into cards in CueCard.",
      steps: speechSteps(
        {
          title: "Switch to Cards",
          body: "Tap the mode name at the top left of CueCard's editor and choose Cards.",
        },
        {
          title: "One story per card",
          body: "Put who you are on the first card, one line per story after it, and the toast on the last. Keep each short enough to take in at a glance.",
        }
      ),
      sampleIntro: "One card per paragraph: type each into its own box in CueCard.",
      sample:
        "For those who don't know me, I'm Jess, Emma's sister. [cue smile]\n\nStory: Emma, age nine, and the hamster in the post box.\n\nThen she met Tom. First thing she told me: he fixed my bike.\n\nWhat I love about them together: they still laugh at the same things. [cue look at them]\n\nPlease raise your glasses: to Emma and Tom. [cue raise glass]",
    },
    faq: [
      {
        question: "Is it OK to read a wedding speech from a phone?",
        answer:
          "Yes, if you are glancing rather than reading. Cue cards help: one short line per card reminds you of the story, and you tell it while looking at the guests. With Show on Lock Screen on, you can lock the phone between glances and still turn cards.",
      },
      {
        question: "How long should a wedding speech be?",
        answer:
          "Three to five minutes is typical for a best man, maid of honor or parent. Set the CueCard timer to your time, with Warn in Last set to a minute, and the time changes color when it is time to head for the toast.",
      },
      {
        question: "Can I give my speech from my Apple Watch?",
        answer:
          'Yes. Save the deck, choose Keep on Apple Watch from the ••• menu, and read it on your wrist with the phone in your pocket. <a href="/watch/">See CueCard on Apple Watch</a>.',
      },
    ],
  },
  {
    slug: "cards/class-presentations",
    kind: "speech",
    icon: "cards",
    name: "Class presentations",
    title: "Cue Cards for Class Presentations on iPhone | CueCard",
    description:
      "Present in class from cue cards on your iPhone: one point per card, a timer that warns you before your slot ends, and cues so you don't rush. Free.",
    keywords:
      "cue cards for presentation, presentation notes app, class presentation cue cards, student presentation notes, speech cards for school, presentation cue cards app",
    h1: "Cue cards for your <em>class presentation.</em>",
    lede:
      "A class presentation is usually a set time, a set of slides and a teacher who marks you on eye contact. Put one point per card, swipe with your slides, and let the timer tell you when to wrap up.",
    cards: [
      "Slide 1: The water cycle in three steps. [cue look up]",
      "Evaporation: the sun heats water, it rises as vapour.",
      "Condensation: vapour cools into clouds. [cue point to diagram]",
      "Precipitation: rain, snow, hail. Back to the start.",
      "Question for the class: where did today's rain start? [cue pause]",
    ],
    rowsHeading: "Why cards work for a presentation",
    rows: [
      {
        h: "One card for each slide",
        p: "Write a card per slide with the point you need to make, and turn the card when you change the slide. You glance down for the point and look up to explain it.",
      },
      {
        h: "A timer for a set slot",
        p: "Set five minutes, or whatever you have, with a warning a minute before the end. The time turns color so you know to skip to your conclusion.",
      },
      {
        h: "Cues for eye contact and pace",
        p: "Add [cue look up] or [cue slow down] where you tend to rush. They show in color on the card, so you notice them without saying them.",
      },
      {
        h: "Free, with nothing to sign up for",
        p: "No account, no ads and no subscription. Your cards stay on your phone, and you can export them as a text file to hand in or keep.",
      },
    ],
    guide: {
      heading: "How to present from cue cards on your phone",
      intro: "Build the slides first. Then make one card for each.",
      steps: speechSteps(
        {
          title: "Switch to Cards",
          body: "Tap the mode name at the top left of CueCard's editor and choose Cards.",
        },
        {
          title: "One card per slide",
          body: "Start each card with the slide it goes with, then the point you need to make. Keep facts and numbers on the card, not the explanation.",
        }
      ),
      sampleIntro: "One card per paragraph: type each into its own box in CueCard.",
      sample:
        "Slide 1: The water cycle in three steps. [cue look up]\n\nEvaporation: the sun heats water, it rises as vapour.\n\nCondensation: vapour cools into clouds. [cue point to diagram]\n\nPrecipitation: rain, snow, hail. Back to the start.\n\nQuestion for the class: where did today's rain start? [cue pause]",
    },
    faq: [
      {
        question: "Can I use my phone for presentation notes?",
        answer:
          "If your teacher allows it, yes. Cards mode shows one point at a time in large text, which is quicker to glance at than a page of notes. Turn on Show on Lock Screen and you can read and turn cards with the phone locked.",
      },
      {
        question: "How many cue cards should a five-minute presentation have?",
        answer:
          "About one per slide, or one per minute if you have no slides. Five to eight short cards is plenty; if a card needs reading, it is too long.",
      },
      {
        question: "Presenting online instead?",
        answer:
          'For a presentation over Zoom, Google Meet or Teams, <a href="/desktop/">CueCard for Mac and Windows</a> keeps your notes on your screen and out of the screen share.',
      },
    ],
  },
  {
    slug: "cards/public-speaking",
    kind: "speech",
    icon: "cards",
    name: "Public speaking",
    title: "Cue Cards App for Public Speaking and Talks | CueCard",
    description:
      "Speak from cue cards on your iPhone or Apple Watch at meetups, conferences and events. One point per card, a timer with a warning, and colored cues.",
    keywords:
      "public speaking cue cards, speech notes app, speaker notes phone, talk notes app, conference talk notes, toastmasters cue cards, speech cue cards app",
    h1: "Cue cards for <em>public speaking.</em>",
    lede:
      "A talk at a meetup, a conference slot or a toast at work goes better when you know the next point without having to remember it. Put each on a card, and keep the deck on your phone, your Lock Screen or your wrist.",
    cards: [
      "Open: the 3 a.m. pager alert. [cue pause]",
      "Point 1: most outages start with a change we made.",
      "Point 2: small changes, shipped often, break less.",
      "Point 3: make rollback the easiest button. [cue slow down]",
      "Close: sleep through the night. Questions? [cue smile]",
    ],
    rowsHeading: "Speaking notes that help, not distract",
    rows: [
      {
        h: "The next point, not the whole talk",
        p: "A card holds the one line that starts each section. You speak the rest, which is what makes it sound like a talk rather than a reading.",
      },
      {
        h: "A timer that keeps you in your slot",
        p: "Set your slot with a warning a few minutes before the end. The time changes color at the warning and again if you run over, so the next speaker never has to wave at you.",
      },
      {
        h: "On the lectern, on the Lock Screen, or on your wrist",
        p: "Put the phone on the lectern and swipe, lock it and turn cards from the Lock Screen, or keep the deck on your Apple Watch and walk the stage.",
      },
      {
        h: "Cues for delivery",
        p: "Mark where to pause, slow down or look at the audience. Cues show in color, so they guide how you speak without being spoken.",
      },
    ],
    guide: {
      heading: "How to give a talk from cue cards",
      intro: "Outline the talk first. Then give each point its own card.",
      steps: speechSteps(
        {
          title: "Switch to Cards",
          body: "Tap the mode name at the top left of CueCard's editor and choose Cards.",
        },
        {
          title: "One section per card",
          body: "Write your opening line on the first card, one card for each point, and your close on the last. A few words each is enough.",
        }
      ),
      sampleIntro: "One card per paragraph: type each into its own box in CueCard.",
      sample:
        "Open: the 3 a.m. pager alert. [cue pause]\n\nPoint 1: most outages start with a change we made.\n\nPoint 2: small changes, shipped often, break less.\n\nPoint 3: make rollback the easiest button. [cue slow down]\n\nClose: sleep through the night. Questions? [cue smile]",
    },
    faq: [
      {
        question: "Should I use cue cards for a speech?",
        answer:
          'Cue cards are a good fit when you know your material and want reminders, not a script. If you need every word, as for a video, use the <a href="/teleprompter/">teleprompter</a> instead. CueCard has both.',
      },
      {
        question: "Can I use cue cards while presenting slides?",
        answer:
          'Yes. Write a card per slide and turn it when you change slides. If you present from a laptop over a video call, <a href="/desktop/">CueCard for Mac and Windows</a> keeps notes out of your screen share, and can follow Google Slides.',
      },
      {
        question: "Can I turn cards without looking at my phone?",
        answer:
          'With the <a href="/watch/">Apple Watch app</a>, tap or swipe on the watch and the phone moves with it. On the Lock Screen, tap Back or Next.',
      },
    ],
  },
  {
    slug: "cards/sermons",
    kind: "speech",
    icon: "cards",
    name: "Sermons",
    title: "Sermon Notes on iPhone and Apple Watch | CueCard",
    description:
      "Preach from sermon notes on your iPhone, iPad or Apple Watch. One point per card, a timer for your service, colored cues, and no pages to turn. Free.",
    keywords:
      "sermon notes app, sermon notes iphone, preaching notes app, sermon notes apple watch, pastor notes app, homily notes, sermon cue cards",
    h1: "Sermon notes, <em>one point at a time.</em>",
    lede:
      "Preach from a deck of short cards on your iPhone, iPad or Apple Watch: the passage, each point and its illustration, with a timer so the service runs on time and cues for where to pause.",
    cards: [
      "Read: Luke 15:11–24. [cue pause]",
      "1. The son leaves: we all wander.",
      "Illustration: the lost dog in the snow.",
      "2. The father runs: grace moves first. [cue slow down]",
      "3. The feast: joy is the point. Pray. [cue look up]",
    ],
    rowsHeading: "Sermon notes that stay out of the way",
    rows: [
      {
        h: "A card for each point",
        p: "The passage, each point, each illustration and the close, one to a card. You see only what comes next, in large text you can read from the pulpit.",
      },
      {
        h: "On the iPad, the phone or your wrist",
        p: "Put your iPhone or an iPad on the pulpit and swipe, or keep the deck on your Apple Watch and step away from it. The watch and iPhone stay in step, so turning a card on one moves the other.",
      },
      {
        h: "A timer for the service",
        p: "Set the length of the sermon with a warning before the end. It changes color when it is time to close, and again if you run over.",
      },
      {
        h: "Cues for the pauses",
        p: "Mark where to pause, slow down or look up. Cues show in color, so they guide the delivery without being read out.",
      },
    ],
    guide: {
      heading: "How to preach from sermon notes on iPhone or iPad",
      intro: "Prepare the sermon as you always do. Then give each point its own card.",
      steps: speechSteps(
        {
          title: "Switch to Cards",
          body: "Tap the mode name at the top left of CueCard's editor and choose Cards.",
        },
        {
          title: "The passage, then each point",
          body: "Put the reading on the first card, one card for each point and illustration, and the close last. Keep the words you want exact, like a quotation, on their own card.",
        }
      ),
      sampleIntro: "One card per paragraph: type each into its own box in CueCard.",
      sample:
        "Read: Luke 15:11–24. [cue pause]\n\n1. The son leaves: we all wander.\n\nIllustration: the lost dog in the snow.\n\n2. The father runs: grace moves first. [cue slow down]\n\n3. The feast: joy is the point. Pray. [cue look up]",
    },
    faq: [
      {
        question: "Can I preach from my Apple Watch?",
        answer:
          'Yes. Keep a saved deck on the watch with Keep on Apple Watch in the ••• menu, and read each point on your wrist without the phone. Set the watch to stay on CueCard for an hour in General › Return to Clock. <a href="/watch/">See CueCard on Apple Watch</a>.',
      },
      {
        question: "Can I read a full sermon manuscript instead?",
        answer:
          'Yes. Switch to the <a href="/teleprompter/">teleprompter</a>, which scrolls the whole manuscript at the speed you set. It works on iPad, and can be read from a few feet away.',
      },
      {
        question: "Is CueCard free for churches?",
        answer:
          "Yes. It is free for everyone, with no account, no ads and no subscription, and your notes stay on your device.",
      },
    ],
  },
];

const pages = [teleprompter, cards, watch, ...speeches];

// The related guides print at the foot of the setup guide.
for (const p of pages) {
  if (p.links) p.guide.links = p.links;
}

// The three parts, in the order the site presents them, for the tiles on the
// home page, /mobile/ and each part's own page.
const modes = [teleprompter, cards, watch].map((p) => ({
  slug: p.slug,
  name: p.name,
  icon: p.icon,
  href: `/${p.slug}/`,
}));
modes[0].blurb = "Your whole script, scrolling at your pace, full screen or floating over the app you film in.";
modes[1].blurb = "One point at a time. Swipe through in the app, on the Lock Screen or on your watch.";
modes[2].blurb = "A remote for the teleprompter, and your cue cards on your wrist.";

module.exports = { pages, speeches, modes };
