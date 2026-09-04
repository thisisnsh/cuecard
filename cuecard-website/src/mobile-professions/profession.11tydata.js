module.exports = {
  eleventyComputed: {
    crumbs: (data) => [
      { name: "CueCard", url: "/" },
      { name: "Mobile", url: "/mobile/" },
      {
        name: "For " + data.mobileProfession.name,
        url: "/mobile/" + data.mobileProfession.slug + "/",
      },
    ],
  },
};
