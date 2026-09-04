// Breadcrumbs for the mobile app pages. They have to be real data rather than
// a {% set %} in the body, because base.njk emits the BreadcrumbList in <head>,
// which is rendered before any block in the page.
module.exports = {
  eleventyComputed: {
    crumbs: (data) => {
      const trail = [
        { name: "CueCard", url: "/" },
        { name: "Mobile", url: "/mobile/" },
      ];
      // /mobile/ is the second crumb already; deeper pages add themselves.
      if (data.app && data.app.slug !== "mobile") {
        trail.push({ name: data.app.name, url: "/" + data.app.slug + "/" });
      }
      return trail;
    },
  },
};
