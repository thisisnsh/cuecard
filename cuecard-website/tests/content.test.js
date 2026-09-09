const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const nunjucks = require('nunjucks');
const { jsonLd, tutorialUrl, softwareSchema } = require('../lib/content');
const site = require('../src/_data/site');
const env = new nunjucks.Environment(new nunjucks.FileSystemLoader('src/_includes'), { autoescape: true });
env.addFilter('tutorialUrl', tutorialUrl);

test('offers follow shipping status, independently of display flags', () => {
  const mobile = softwareSchema(site.products.mobile);
  assert.equal(mobile['@id'], 'https://cuecard.dev/#mobileapp');
  assert.equal(mobile.offers.price, '0');
  assert.match(mobile.operatingSystem, /16\.6/);
  assert.doesNotMatch(mobile.operatingSystem, /Android/);
  const android = softwareSchema(site.products.mobile, 'android');
  for (const key of ['offers', 'operatingSystem', 'installUrl', 'downloadUrl']) assert.equal(android[key], undefined);
  const future = structuredClone(site.products.mobile);
  future.platforms[0].shipping = false;
  assert.equal(softwareSchema(future).offers, undefined);
  future.platforms[1].shipping = true;
  future.platforms[1].storeUrl = 'https://play.google.com/store/apps/details?id=fixture';
  assert.equal(softwareSchema(future).operatingSystem, 'Android');
});

test('JSON-LD round trips quotes, newlines and script delimiters', () => {
  const value = { featureList: ['A "quote"\n</script><script>alert(1)</script> & cues'] };
  const result = jsonLd(value);
  assert.equal(result.includes('</script>'), false);
  assert.deepEqual(JSON.parse(result), value);
});

test('missing and invalid tutorials render no markup or whitespace', () => {
  for (const youtubeUrl of [undefined, '', '#', 'javascript:alert(1)', 'http://youtu.be/zSSABBm7K1Q', 'https://youtube.com.evil.test/watch?v=zSSABBm7K1Q', 'https://youtube.com/', 'https://youtube.com/watch?v=bad', 'https://user:pass@youtube.com/watch?v=zSSABBm7K1Q']) {
    assert.equal(env.render('partials/tutorial-link.njk', { tutorial: { youtubeUrl } }), '');
  }
});

test('valid tutorial appears beside a complete written guide, safely escaped', () => {
  for (const youtubeUrl of ['https://www.youtube.com/watch?v=zSSABBm7K1Q', 'https://youtu.be/zSSABBm7K1Q', 'https://youtube.com/shorts/zSSABBm7K1Q']) {
    const html = env.render('partials/setup-guide.njk', {
      guide: { heading: 'Fixture setup', steps: [{ title: 'Start Overlay', body: 'Keep the written guide.' }] },
      tutorial: { youtubeUrl, label: 'Watch the TikTok tutorial on YouTube <test>' }
    });
    assert.match(html, /class="btn btn-ghost tutorial-action"/);
    assert.match(html, /Keep the written guide/);
    assert.match(html, /&lt;test&gt;/);
    assert.match(html, /rel="noopener"/);
  }
});

function runtime() {
  const listeners = {};
  const events = [];
  const document = {
    querySelectorAll: () => [],
    addEventListener: (name, callback) => (listeners[name] ||= []).push(callback),
    createElement: () => ({ className: '', innerHTML: '', querySelectorAll: () => [] })
  };
  const window = { location: new URL('https://cuecard.dev/mobile/tiktok/?private=query#how-to'), gtag: (...args) => events.push(args) };
  const context = vm.createContext({ document, window, URL, console, navigator: { userAgent: '' } });
  vm.runInContext(fs.readFileSync('src/script.js', 'utf8'), context);
  function click(dataset, href = site.ios, nested = false) {
    const link = { dataset, href };
    const event = { target: { closest: () => Object.keys(dataset).length ? link : null }, preventDefault: () => assert.fail('navigation intercepted') };
    if (nested) event.target.tagName = 'path';
    for (const listener of listeners.click || []) listener(event);
  }
  return { context, events, window, click };
}

test('delegation emits exactly one bounded event per download, including nested icons', () => {
  const r = runtime();
  for (const ctaLocation of ['hero', 'navigation', 'download_section', 'article']) {
    const before = r.events.length;
    r.click({ productPlatform: 'ios', ctaLocation, destinationType: 'app_store' }, site.ios, true);
    assert.equal(r.events.length, before + 1);
    const [type, name, fields] = r.events.at(-1);
    assert.equal(type, 'event'); assert.equal(name, 'product_download_click');
    assert.deepEqual(JSON.parse(JSON.stringify(fields)), { product_platform: 'ios', cta_location: ctaLocation, page_path: '/mobile/tiktok/', destination_type: 'app_store' });
  }
});

test('actual dynamically generated installer cards carry the measured platform', () => {
  const r = runtime();
  for (const [key, name, expected] of [['macos', 'cuecard-universal.dmg', 'macos'], ['windows_x64', 'cuecard-x64.exe', 'windows'], ['windows_arm', 'cuecard-arm64.msi', 'windows']]) {
    const card = r.context.createPlatformCard(key, { name: key, instructions: [], assets: [{ name, size: 1024, browser_download_url: 'https://github.com/thisisnsh/cuecard/releases/download/v1/' + name }] });
    const tag = card.innerHTML.match(/<a[^>]+data-product-platform[^>]+>/)[0];
    const data = Object.fromEntries([...tag.matchAll(/data-([a-z-]+)="([^"]+)"/g)].map(([, key, value]) => [key.replace(/-([a-z])/g, (_, c) => c.toUpperCase()), value]));
    r.click(data, tag.match(/href="([^"]+)"/)[1], true);
    assert.equal(r.events.at(-1)[2].product_platform, expected);
    assert.equal(r.events.at(-1)[2].destination_type, 'installer');
  }
  assert.equal(r.events.length, 3);
});

test('navigation, Android and extensions are excluded; blocked analytics cannot break links', () => {
  const r = runtime();
  r.click({}, 'https://cuecard.dev/desktop/#download');
  r.click({}, 'https://cuecard.dev/mobile/android/');
  r.click({ productPlatform: 'android', ctaLocation: 'hero', destinationType: 'app_store' });
  r.click({ productPlatform: 'ios', ctaLocation: 'user entered text', destinationType: 'app_store' });
  r.click({ productPlatform: 'macos', ctaLocation: 'hero', destinationType: 'installer' }, 'https://cuecard.dev/desktop/#download');
  assert.equal(r.events.length, 0);
  r.window.gtag = undefined;
  assert.doesNotThrow(() => r.click({ productPlatform: 'ios', ctaLocation: 'hero', destinationType: 'app_store' }));
  r.window.gtag = () => { throw new Error('blocked'); };
  assert.doesNotThrow(() => r.click({ productPlatform: 'ios', ctaLocation: 'hero', destinationType: 'app_store' }));
});
