// Serialize for a script element, including strings containing HTML delimiters.
const jsonLd = value => JSON.stringify(value ?? null).replace(/</g, '\\u003c').replace(/>/g, '\\u003e').replace(/&/g, '\\u0026');

function tutorialUrl(value) {
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.username || url.password || url.port) return '';
    const id = '[A-Za-z0-9_-]{11}';
    if (url.hostname === 'youtu.be' && new RegExp(`^/${id}/?$`).test(url.pathname)) return url.href;
    if (!['youtube.com', 'www.youtube.com', 'm.youtube.com'].includes(url.hostname)) return '';
    if (url.pathname === '/watch' && new RegExp(`^${id}$`).test(url.searchParams.get('v') || '')) return url.href;
    if (new RegExp(`^/shorts/${id}/?$`).test(url.pathname)) return url.href;
  } catch {}
  return '';
}

function softwareSchema(product, platformKey) {
  const shipping = product.platforms.filter(p => p.shipping && (!platformKey || p.key === platformKey));
  return {
    '@context': 'https://schema.org',
    '@type': product.id.endsWith('#mobileapp') ? 'MobileApplication' : 'SoftwareApplication',
    '@id': product.id, name: product.name, url: product.url,
    applicationCategory: product.id.endsWith('#mobileapp') ? 'UtilitiesApplication' : 'BusinessApplication',
    description: product.description, isAccessibleForFree: product.price === '0',
    image: product.image, screenshot: product.screenshots, featureList: product.features,
    license: 'https://opensource.org/licenses/MIT',
    publisher: { '@id': 'https://cuecard.dev/#org' },
    ...(shipping.length ? {
      operatingSystem: shipping.map(p => p.os).join(', '),
      downloadUrl: shipping[0].storeUrl, installUrl: shipping[0].storeUrl,
      offers: { '@type': 'Offer', price: product.price, priceCurrency: product.currency, availability: 'https://schema.org/InStock' }
    } : {})
  };
}

module.exports = { jsonLd, tutorialUrl, softwareSchema };
