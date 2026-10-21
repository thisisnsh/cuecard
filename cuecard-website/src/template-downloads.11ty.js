const resources = require('./_data/resources');

module.exports = class {
  data() {
    return {
      pagination: { data: 'templateDownloads', size: 1, alias: 'templateDownload' },
      templateDownloads: resources.flatMap(resource => resource.samples),
      permalink: data => `templates/${data.templateDownload.id}.txt`,
      eleventyExcludeFromCollections: true
    };
  }

  render({ templateDownload: sample }) {
    return (sample.cards ? sample.cards.join('\n[separator]\n') : sample.text) + '\n';
  }
};
