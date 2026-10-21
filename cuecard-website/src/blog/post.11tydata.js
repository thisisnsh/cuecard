module.exports = {
  eleventyComputed: {
    templateResource: ({ blog }) => {
      if (['cue-cards-vs-teleprompter', 'how-much-to-write-on-a-cue-card', 'speech-notes-on-apple-watch', 'how-to-time-a-speech'].includes(blog.slug)) {
        return { href: '/cue-card-templates/', label: 'Try a free cue-card template for your next talk' };
      }
      if (['snapchat-story-teleprompter-natural-script-one-take', 'teleprompter-for-snapchat-read-your-script-on-camera', 'instagram-reels-teleprompter-stop-looking-like-reading', 'tiktok-teleprompter-one-script-every-app', 'make-perfect-reels-tiktok-videos-cuecard-auto-scroll-teleprompter'].includes(blog.slug)) {
        return { href: '/teleprompter-scripts/', label: 'Start with a free teleprompter script for your next video' };
      }
      return null;
    },
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
