module.exports = {
  eleventyComputed: {
    crumbs: ({ blog }) => [
      { name: 'CueCard', url: '/' },
      { name: 'Blog', url: '/blog/' },
      { name: blog.seoTitle || blog.title, url: `/blog/${blog.slug}/` },
    ],
    relatedPosts: ({ blog, blogs }) => (blog.related || []).map(slug => {
      const related = blogs.find(post => post.slug === slug);
      if (!related || slug === blog.slug) {
        throw new Error(`Invalid related article "${slug}" on "${blog.slug}"`);
      }
      return related;
    }),
  },
};
