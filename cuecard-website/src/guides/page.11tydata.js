module.exports = {
  eleventyComputed: {
    crumbs: ({ guidePage }) => [{ name: 'CueCard', url: '/' }, { name: guidePage.title, url: `/${guidePage.slug}/` }]
  }
};
