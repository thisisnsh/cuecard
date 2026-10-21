module.exports = {
  eleventyComputed: {
    crumbs: data => [
      { name: "CueCard", url: "/" },
      { name: data.resource.name, url: `/${data.resource.slug}/` }
    ]
  }
};
