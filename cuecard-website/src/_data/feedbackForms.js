// Google Forms embedded at /feedback-<id>/, one page each. The apps link to
// these from a notification, and cuecard.dev is already on every client's link
// allowlist, so a new form needs no app release.
//
// The id is random rather than descriptive so a URL can't be guessed or reused:
// a new survey gets a new entry and a new id, and an old link keeps pointing at
// the form it was sent with.
//
//   formId   The long id in docs.google.com/forms/d/e/<formId>/viewform.
//   height      The iframe's height in pixels on phones. Google Forms can't
//               report its own, so measure the form's longest page and match it;
//               any extra shows up as blank space under the form.
//   heightWide  The same from 600px wide up, where the form wraps less.

module.exports = [
  {
    id: "95efa0d9",
    title: "Help make CueCard better",
    formId: "1FAIpQLSc_XWKXhezJHwRCdUl2u322KYtsc8xnRC1KpoyrKSjlFXIpHA",
    height: 1080,
    heightWide: 960,
  },
];
