// The copy inside the two cross-sell cards: partials/crosspanel.njk, which
// points at the other half of the product, and partials/bigscreen.njk, which
// points at the other size of screen.
//
// Both used to carry one paragraph each, printed word for word on every page
// that included them — twenty-five pages of the first, twenty-three of the
// second. They are the second and third largest blocks of prose on a landing
// page after the feature rows, so they are the second and third largest reason
// two of those pages read alike.
//
// Each function returns { h, p }: the card's own heading and its paragraph,
// written around whatever the page it is on is about.

/** Pointing a phone page at the desktop app. */
function toDesktop(subject) {
  const when = subject
    ? `for the meeting after the ${subject} take`
    : "when you are presenting rather than filming";
  return {
    h: "Speaker notes your screen share cannot see",
    p: `The other half of CueCard runs on a Mac or PC, and it hides rather than floats: the window is left out of screen capture, so a call sees your deck and never your notes. Open it ${when}. Any deck, or none at all — and <a href="/google-slides/">Google Slides</a> notes can follow your slides.`,
  };
}

/** Pointing a phone page at the desktop app, for a role page. */
function toDesktopForRole(role) {
  const who = (role || "").toLowerCase();
  return {
    h: "Speaker notes your screen share cannot see",
    p: `Most ${who} present from a laptop as well as film on a phone. On a Mac or PC the CueCard window is left out of screen capture, so a call sees your deck and never your notes — same scripts, same cues, nothing on the shared screen.`,
  };
}

/** Pointing a desktop page at the phone app. */
function toMobile(subject) {
  const when = subject
    ? `to open once the ${subject} call is over`
    : "for filming rather than presenting";
  return {
    h: "A script that floats over the app you film in",
    p: `The other half runs on an iPhone or iPad, and it is the one ${when}. Your script floats over the camera, <a href="/mobile/instagram/">Instagram</a> or <a href="/mobile/tiktok/">TikTok</a> and scrolls while you talk.`,
  };
}

/** Pointing a desktop page at the phone app, for a role page. */
function toMobileForRole(role) {
  const who = (role || "").toLowerCase();
  return {
    h: "A script that floats over the app you film in",
    p: `Plenty of ${who} end up on the other side of a camera too. On an iPhone or iPad the script floats over <a href="/mobile/instagram/">Instagram</a>, <a href="/mobile/tiktok/">TikTok</a> or the camera itself, scrolling while you talk.`,
  };
}

/**
 * The "also on iPad" card.
 *
 * The whole paragraph is written around the page, not just its last clause:
 * appending one sentence to a shared one still leaves twenty-three pages
 * carrying the same two sentences as each other.
 */
function bigscreen(subject, role) {
  if (role) {
    const who = role.toLowerCase();
    return {
      h: "A screen big enough to read from a few feet away",
      p: `An iPad is the screen a good many ${who} end up propping under the lens. The script runs the full width of it, big enough to read from where you are standing with both hands free. Shrink it back into the floating window whenever you would rather film in an app.`,
    };
  }
  if (subject) {
    return {
      h: "A screen big enough to read from a few feet away",
      p: `Filming ${subject} from an iPad gives you more room: the script can take the whole display, so you read it from a few feet back rather than holding a phone at arm's length. Or shrink it into the floating window and film as you would anyway.`,
    };
  }
  return {
    h: "A screen big enough to read from a few feet away",
    p: "On an iPad the script can fill the whole display, so you can prop the iPad under a camera and read it from where you are standing, the way a studio teleprompter works. Or shrink it into the same floating window and film in whatever app you like.",
  };
}

/** The same card on the iPad page, pointed back at the phone. */
function pocket(subject) {
  const about = subject ? ` — including wherever you happen to be filming ${subject}` : "";
  return {
    h: "Small enough to film with, wherever you are standing",
    p: `The same scripts, the same cues and the same floating window, on the phone already in your hand${about}. Shrink the prompter into a corner, open the camera, <a href="/mobile/instagram/">Instagram</a> or <a href="/mobile/tiktok/">TikTok</a>, and film wherever you are rather than wherever the iPad is propped.`,
  };
}

module.exports = { toDesktop, toDesktopForRole, toMobile, toMobileForRole, bigscreen, pocket };
