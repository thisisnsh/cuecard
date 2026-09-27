// Breadcrumbs for /teleprompter/, /cards/, /watch/ and the speaking pages. As
// in apps/app.11tydata.js, they have to be data: base.njk writes the
// BreadcrumbList in <head>, before any block in the page is rendered.
module.exports = {
  eleventyComputed: {
    crumbs: (data) => {
      const p = data.speakingPage;
      if (!p) return [];
      const trail = [{ name: "CueCard", url: "/" }];
      if (p.kind === "speech") trail.push({ name: "Cards", url: "/cards/" });
      trail.push({ name: p.name, url: "/" + p.slug + "/" });
      return trail;
    },
  },
};
