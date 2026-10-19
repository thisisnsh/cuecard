// Google Forms embedded at /feedback-<id>/, one page each. The apps link to
// these from a notification, and cuecard.dev is already on every client's link
// allowlist, so a new form needs no app release.
//
// The id is random rather than descriptive so a URL can't be guessed or reused:
// a new survey gets a new entry and a new id, and an old link keeps pointing at
// the form it was sent with.
//
//   formId   The long id in docs.google.com/forms/d/e/<formId>/viewform.
//   heights  Screen width -> the iframe's height from that width up, in pixels.
//            The page can't read the form's height (it is on Google's domain),
//            so measure it inside the frame on this page: the bottom of Google's
//            footer plus about 45px for the help button under it, at the
//            narrowest width of each step. Too little and the form scrolls inside
//            its frame; too much leaves blank space under it.

module.exports = [
  {
    id: "95efa0d9",
    title: "Help make CueCard better",
    formId: "1FAIpQLSc_XWKXhezJHwRCdUl2u322KYtsc8xnRC1KpoyrKSjlFXIpHA",
    heights: { 0: 1410, 380: 1335, 600: 1185 },
  },
];
