const markdownIt = require("markdown-it");

module.exports = function(eleventyConfig) {
  const markdown = markdownIt({
    html: false,
    breaks: true,
    linkify: true
  });

  eleventyConfig.addFilter("markdownify", (value) => {
    if (!value) {
      return "";
    }
    return markdown.render(value);
  });

  eleventyConfig.addFilter("markdownExcerpt", (value) => {
    if (!value) {
      return "";
    }
    const trimmed = String(value).trim();
    if (!trimmed) {
      return "";
    }
    const blocks = trimmed.split(/\n\s*\n/);
    const firstBlock = blocks.find((block) => block.trim());
    if (!firstBlock) {
      return "";
    }
    return markdown.render(firstBlock);
  });

  // Copy static assets
  eleventyConfig.addPassthroughCopy("src/assets");
  eleventyConfig.addPassthroughCopy("src/styles.css");
  eleventyConfig.addPassthroughCopy("src/script.js");
  eleventyConfig.addPassthroughCopy("src/robots.txt");
  eleventyConfig.addPassthroughCopy("src/_redirects");
  eleventyConfig.addPassthroughCopy("src/.htaccess");

  // Watch for changes
  eleventyConfig.addWatchTarget("src/styles.css");
  eleventyConfig.addWatchTarget("src/script.js");

  return {
    dir: {
      input: "src",
      output: "_site",
      includes: "_includes",
      data: "_data"
    },
    templateFormats: ["njk", "html", "md"],
    htmlTemplateEngine: "njk",
    markdownTemplateEngine: "njk"
  };
};
