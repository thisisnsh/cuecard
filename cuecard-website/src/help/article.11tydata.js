module.exports = {
  eleventyComputed: {
    crumbs: ({ article }) => [
      { name: 'CueCard', url: '/' }, { name: 'Help', url: '/help/' },
      { name: article.title, url: `/${article.slug}/` }
    ]
  }
};
