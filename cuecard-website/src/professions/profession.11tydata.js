module.exports = {
  eleventyComputed: {
    crumbs: (data) => [
      { name: "CueCard", url: "/" },
      { name: "Desktop", url: "/desktop/" },
      {
        name: "For " + data.profession.name,
        url: "/" + data.profession.slug + "/",
      },
    ],
  },
};
