// Google Forms embedded at /feedback-<id>/, one page each. The apps link to
// these from a notification, and cuecard.dev is already on every client's link
// allowlist, so a new form needs no app release.
//
// The id is random rather than descriptive so a URL can't be guessed or reused:
// a new survey gets a new entry and a new id, and an old link keeps pointing at
// the form it was sent with.
//
//   formId   The long id in docs.google.com/forms/d/e/<formId>/viewform.
//   fields   Query parameter -> the form's prefill field, e.g. { p: "entry.123" }.
//            Find a field's id under ⋮ -> Get pre-filled link. A parameter with
//            no field is dropped, so links can carry it before the form does.
//   height   The iframe's height in pixels. Google Forms can't report its own,
//            so set it to fit the longest page of the form.

module.exports = [
  {
    id: "95efa0d9",
    title: "Help make CueCard better",
    formId: "1FAIpQLSc_XWKXhezJHwRCdUl2u322KYtsc8xnRC1KpoyrKSjlFXIpHA",
    fields: { p: "", v: "" },
    height: 1300,
  },
];
