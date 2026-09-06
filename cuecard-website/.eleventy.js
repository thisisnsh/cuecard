const markdownIt = require("markdown-it");

module.exports = function(eleventyConfig) {
  // Configure dev server to serve 404.html for missing routes
  eleventyConfig.setServerOptions({
    showAllHosts: true,
  });

  const markdown = markdownIt({
    html: false,
    breaks: true,
    linkify: true
  });

  // Posts are written with their sections at "###", but they render under the
  // page's h1, so the document jumped h1 -> h3. Shift every heading so the
  // shallowest one in the post lands at h2 and the rest keep their relative
  // depth. A post already written at "##" is left exactly as it is.
  const normalizeHeadings = (html) => {
    const levels = [...html.matchAll(/<h([1-6])\b/g)].map((m) => Number(m[1]));
    if (!levels.length) {
      return html;
    }
    const shift = 2 - Math.min(...levels);
    if (shift === 0) {
      return html;
    }
    return html.replace(
      /<(\/?)h([1-6])\b/g,
      (_, slash, level) => `<${slash}h${Math.min(6, Math.max(2, Number(level) + shift))}`
    );
  };

  eleventyConfig.addFilter("markdownify", (value) => {
    if (!value) {
      return "";
    }
    return normalizeHeadings(markdown.render(value));
  });

  // The first block of real prose. Posts open on a heading, and a heading is a
  // label rather than a summary: as an excerpt it reads as a stub, and as a
  // meta description it gave Google four words to rank. Skip to the first
  // paragraph instead.
  const firstParagraph = (value) => {
    const trimmed = String(value || "").trim();
    if (!trimmed) {
      return "";
    }
    const blocks = trimmed.split(/\n\s*\n/);
    return blocks.find((block) => block.trim() && !block.trim().startsWith("#")) || "";
  };

  eleventyConfig.addFilter("markdownExcerpt", (value) => {
    const block = firstParagraph(value);
    return block ? markdown.render(block) : "";
  });

  // The same paragraph as plain text, cut to a word boundary inside the length
  // Google will actually print. Used for description and og:description, so a
  // post never has to carry a hand-written copy that can drift from the body.
  eleventyConfig.addFilter("metaExcerpt", (value, limit = 155) => {
    const block = firstParagraph(value);
    if (!block) {
      return "";
    }
    const text = markdown
      .render(block)
      .replace(/<[^>]+>/g, "")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/\s+/g, " ")
      .trim();
    if (text.length <= limit) {
      return text;
    }
    const cut = text.slice(0, limit + 1);
    const lastSpace = cut.lastIndexOf(" ");
    return cut.slice(0, lastSpace > 0 ? lastSpace : limit).replace(/[,;:.—-]+$/, "") + "…";
  });

  // Copy static assets
  eleventyConfig.addPassthroughCopy("src/assets");
  eleventyConfig.addPassthroughCopy("src/styles.css");
  eleventyConfig.addPassthroughCopy("src/script.js");
  eleventyConfig.addPassthroughCopy("src/robots.txt");
  // GitHub Pages reads CNAME from the published root to serve the custom domain
  eleventyConfig.addPassthroughCopy("src/CNAME");

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
