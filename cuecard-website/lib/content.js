// Serialize for a script element, including strings containing HTML delimiters.
const jsonLd = value => JSON.stringify(value ?? null).replace(/</g, '\\u003c').replace(/>/g, '\\u003e').replace(/&/g, '\\u0026');

function softwareSchema(product, platformKey) {
  const shipping = product.platforms.filter(p => p.shipping && (!platformKey || p.key === platformKey));
  return {
    '@context': 'https://schema.org',
    '@type': product.id.endsWith('#mobileapp') ? 'MobileApplication' : 'SoftwareApplication',
    '@id': product.id, name: product.name, url: product.url,
    alternateName: product.alternateName,
    applicationCategory: product.id.endsWith('#mobileapp') ? 'UtilitiesApplication' : 'BusinessApplication',
    description: product.description, isAccessibleForFree: product.price === '0',
    image: product.image, screenshot: product.screenshots, featureList: product.features,
    license: 'https://www.gnu.org/licenses/gpl-3.0.html',
    publisher: { '@id': 'https://cuecard.dev/#org' },
    ...(shipping.length ? {
      operatingSystem: shipping.map(p => p.os).join(', '),
      downloadUrl: shipping[0].storeUrl, installUrl: shipping[0].storeUrl,
      offers: { '@type': 'Offer', price: product.price, priceCurrency: product.currency, availability: 'https://schema.org/InStock' }
    } : {})
  };
}

// A card as the app draws it: its text, with each [...] cue in the cue color
// and without the brackets. Escaped first, so a card is never HTML.
function cueHtml(value) {
  const escaped = String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  return escaped.replace(/\[([^\]\n]+)\]/g, (_, cue) => `<span class="cue">${cue.trim()}</span>`);
}

module.exports = { jsonLd, softwareSchema, cueHtml };
