// The script the live prompter in the hero reads.
//
// There is one of these on every landing page, and for a long time there was
// one script — the same eleven lines, word for word, on forty-two pages. It is
// the largest block of prose on the site and it was the largest block of
// duplicated prose on the site, which is a bad trade for a page whose whole job
// is to rank for one phrase.
//
// So each page gets a script about the thing that page is about. They are all
// the same shape, because the shape is the argument — a line, a cue, a line, a
// cue — but the words are the page's own, and a reader who lands on the
// realtor page watches a realtor's script scroll past rather than a generic
// one.
//
// A line is { t: "spoken line" } or { cue: "an instruction you never say" }.

/** The stock script: the home page's, and the fallback for anything unlisted. */
const standard = [
  { t: "Welcome everyone." },
  { t: "I'm excited to be here today to talk about CueCard." },
  { cue: "smile and pause" },
  { t: "It keeps your speaker notes visible above all apps, so you can use your existing camera apps and still read your notes." },
  { cue: "pause" },
  { t: "It has a timer so you know if you're being brief… or too passionate." },
  { cue: "light chuckle" },
  { t: "And the colored highlights?" },
  { cue: "emphasize" },
  { t: "Those are your secret cues — reminders to smile, pause, or not panic." },
  { cue: "pause" },
  { t: "Try it out. I think you'll love it." },
];

/**
 * A script for a page about filming in one named app.
 *
 * `subject` is the app — "Instagram", "TikTok" — or null for the pages about
 * the phone app itself.
 */
function forApp(subject, device) {
  const where = subject || "the camera";
  const on = device || "my phone";
  return [
    { t: `Hey — quick one before I start recording.` },
    { cue: "look at the lens" },
    { t: `This script is floating over ${where} right now, on ${on}.` },
    { cue: "small nod" },
    { t: `It scrolls on its own, so my hands stay where they are and my eyes stay up here.` },
    { cue: "slow down" },
    { t: `The pink lines are cues. They tell me how to say the next bit.` },
    { cue: "smile" },
    { t: `They are never lines to read out — which is why you have not heard me say one.` },
    { cue: "pause, then land it" },
    { t: `That is the whole app. It is free.` },
  ];
}

/** A script for a page about presenting on one named meeting app. */
function forMeeting(name) {
  return [
    { t: `Thanks for joining — I'll share my screen in a second.` },
    { cue: "wait for the green dot" },
    { t: `You can see my deck now. You cannot see this window.` },
    { cue: "let that land" },
    { t: `These are my speaker notes, sitting on my screen and left out of what ${name} is sending you.` },
    { cue: "slow down" },
    { t: `The clock at the top is counting this section down, so I finish when I said I would.` },
    { cue: "check the time" },
    { t: `And the pink lines are reminders about how to say the next part.` },
    { cue: "smile, then move on" },
    { t: `Right — on to the numbers.` },
  ];
}

/** A script for a role page about filming on a phone. */
function forMobileRole(name, audience, firstUse) {
  const who = (audience || name || "").toLowerCase();
  const topic = firstUse || "This one";
  return [
    { t: `Okay — recording. ${topic}, take one.` },
    { cue: "settle, then start" },
    { t: `Everything I am saying is on a script floating above the camera app.` },
    { cue: "eyes up" },
    { t: `It scrolls by itself, at the speed I talk, so I am not scrubbing back to find my place.` },
    { cue: "slow down here" },
    { t: `The coloured lines are notes to me — where to pause, where to smile, what not to rush.` },
    { cue: "smile" },
    { t: `They are for ${who} who would rather sound like themselves than read off a card.` },
    { cue: "pause" },
    { t: `One take. That is the point.` },
  ];
}

/** A script for a role page about presenting from a computer. */
function forDesktopRole(name, audience, firstUse) {
  const who = (audience || name || "").toLowerCase();
  const topic = firstUse ? firstUse.toLowerCase() : "the usual";
  return [
    { t: `Right — let's start. Today: ${topic}.` },
    { cue: "look at the camera, not the deck" },
    { t: `You are seeing my slides. You are not seeing this.` },
    { cue: "let that land" },
    { t: `This window sits on my screen and is left out of the screen share entirely.` },
    { cue: "slow down" },
    { t: `Which means the notes ${who} actually need are right here, at eye level.` },
    { cue: "check the clock" },
    { t: `The timer keeps me honest, and the pink lines tell me how to say the next part.` },
    { cue: "smile, then continue" },
    { t: `Nobody on the call knows either of them exist.` },
  ];
}

module.exports = { standard, forApp, forMeeting, forMobileRole, forDesktopRole };
