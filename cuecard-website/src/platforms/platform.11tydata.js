module.exports = {
  eleventyComputed: {
    crumbs: (data) => [
      { name: "CueCard", url: "/" },
      { name: "Desktop", url: "/desktop/" },
      { name: data.platform.name, url: "/" + data.platform.slug + "/" },
    ],
  },
};
