"""Validate generated search metadata and crawl paths using Python's standard library."""

import json
from collections import defaultdict
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1] / '_site'
ORIGIN = 'https://' + (ROOT / 'CNAME').read_text().strip()
errors = []


def require(condition, message):
    if not condition:
        errors.append(message)


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.meta = defaultdict(list)
        self.canonicals = []
        self.links = []
        self.ids = set()
        self.schemas = []
        self.title = ''
        self.h1s = 0
        self.in_title = False
        self.json_text = None
        self.path = path
        self.feed(path.read_text())

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.add(attrs['id'])
        if tag == 'meta':
            self.meta[attrs.get('name', attrs.get('property'))].append(attrs.get('content', ''))
        if tag == 'link' and attrs.get('rel') == 'canonical':
            self.canonicals.append(attrs.get('href'))
        if tag == 'a' and attrs.get('href'):
            self.links.append(attrs['href'])
        if tag == 'h1':
            self.h1s += 1
        if tag == 'title':
            self.in_title = True
        if tag == 'script' and attrs.get('type') == 'application/ld+json':
            self.json_text = ''

    def handle_data(self, text):
        if self.in_title:
            self.title += text
        if self.json_text is not None:
            self.json_text += text

    def handle_endtag(self, tag):
        if tag == 'title':
            self.in_title = False
        if tag == 'script' and self.json_text is not None:
            try:
                schema = json.loads(self.json_text)
                self.schemas.extend(schema.get('@graph', [schema]))
            except (ValueError, AttributeError) as error:
                errors.append(f'{self.path}: invalid JSON-LD: {error}')
            self.json_text = None

    def value(self, name):
        return self.meta.get(name, [''])[0]

    @property
    def indexable(self):
        return 'noindex' not in self.value('robots').lower()


pages = {}
for path in sorted(ROOT.rglob('*.html')):
    route = '/' + path.relative_to(ROOT).as_posix()
    if route.endswith('/index.html'):
        route = route[:-len('index.html')]
    pages[route] = Page(path)

indexable = {route for route, page in pages.items() if page.indexable}
require('/' in indexable, 'Homepage must be indexable')
titles, descriptions = defaultdict(list), defaultdict(list)
edges = defaultdict(set)
article_dates = {}

for route, page in pages.items():
    canonical = ORIGIN + route
    if page.indexable:
        require(bool(page.title.strip()), f'{route}: missing title')
        require(page.h1s == 1, f'{route}: expected one h1, found {page.h1s}')
        require(page.canonicals == [canonical], f'{route}: canonical must be {canonical}')
        require(bool(page.schemas), f'{route}: missing structured data')
        for name in ('description', 'robots', 'og:type', 'og:url', 'og:title',
                     'og:description', 'og:image', 'twitter:card', 'twitter:title',
                     'twitter:description', 'twitter:image'):
            require(len(page.meta[name]) == 1 and bool(page.value(name)),
                    f'{route}: missing, empty or duplicate {name}')
        require(page.value('og:url') == canonical, f'{route}: social URL differs from canonical')
        titles[page.title].append(route)
        descriptions[page.value('description')].append(route)
        for schema in page.schemas:
            if schema.get('@type') == 'BreadcrumbList':
                crumbs = schema.get('itemListElement', [])
                require(bool(crumbs) and crumbs[-1].get('item') == canonical,
                        f'{route}: breadcrumb must end at the current page')
            if schema.get('@type') == 'BlogPosting':
                require(page.value('og:type') == 'article', f'{route}: missing article social type')
                for field, name in (('datePublished', 'article:published_time'),
                                    ('dateModified', 'article:modified_time')):
                    require(schema.get(field) == page.value(name), f'{route}: inconsistent {field}')
                article_dates[canonical] = schema.get('dateModified')

    for href in page.links:
        target = urlsplit(urljoin(canonical, href))
        if target.netloc != urlsplit(ORIGIN).netloc:
            continue
        if target.path in pages:
            edges[route].add(target.path)
            require(not target.fragment or unquote(target.fragment) in pages[target.path].ids,
                    f'{route}: broken fragment {href}')
        else:
            require((ROOT / unquote(target.path).lstrip('/')).is_file(),
                    f'{route}: broken internal link {href}')

for label, values in (('title', titles), ('description', descriptions)):
    for value, routes in values.items():
        require(len(routes) == 1, f'Duplicate {label}: {routes}')

ns = {'s': 'http://www.sitemaps.org/schemas/sitemap/0.9'}
sitemap = ET.parse(ROOT / 'sitemap.xml')
urls = [node.findtext('s:loc', namespaces=ns) for node in sitemap.findall('s:url', ns)]
require(len(urls) == len(set(urls)), 'Sitemap contains duplicate URLs')
require(set(urls) == {ORIGIN + route for route in indexable},
        'Sitemap must contain exactly the indexable canonical URLs')
for node in sitemap.findall('s:url', ns):
    url = node.findtext('s:loc', namespaces=ns)
    if url in article_dates:
        require(node.findtext('s:lastmod', namespaces=ns) == article_dates[url],
                f'{url}: sitemap lastmod differs from article dateModified')
require(f'Sitemap: {ORIGIN}/sitemap.xml' in (ROOT / 'robots.txt').read_text(),
        'robots.txt must advertise the canonical sitemap')
for route in ('/404.html', '/ios/', '/android/'):
    require(route in pages and not pages[route].indexable, f'{route}: must exist and be noindex')

visited, pending = set(), ['/']
while pending:
    route = pending.pop()
    if route not in visited:
        visited.add(route)
        pending.extend(edges[route] - visited)
require(indexable <= visited, f'Pages unreachable through links from home: {sorted(indexable - visited)}')

if errors:
    raise SystemExit('SEO check failed:\n' + '\n'.join(f'- {error}' for error in errors))
print(f'SEO check passed: {len(pages)} pages, {len(indexable)} indexable URLs, '
      f'{len(article_dates)} articles; metadata, JSON-LD, sitemap and internal links validated.')
