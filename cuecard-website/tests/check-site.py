"""Crawl generated HTML, without executing JavaScript or making network requests."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urljoin,urlparse,unquote
import json, re, xml.etree.ElementTree as ET

class Page(HTMLParser):
    def __init__(self, file):
        super().__init__(convert_charrefs=True)
        self.file=file;self.ids=[];self.links=[];self.meta={};self.h1=0;self.title='';self.canonical='';self.jsonld=[];self.text=[];self.capture=None;self.buffer='';self.feed(file.read_text())
    def handle_starttag(self, tag, attrs):
        a=dict(attrs)
        if 'id' in a:self.ids.append(a['id'])
        if tag=='a' and 'href' in a:self.links.append(a)
        if tag=='h1':self.h1+=1
        if tag=='title':self.capture='title';self.buffer=''
        if tag=='script' and a.get('type')=='application/ld+json':self.capture='json';self.buffer=''
        if tag=='meta':self.meta[a.get('name',a.get('property',''))]=a.get('content','')
        if tag=='link' and a.get('rel')=='canonical':self.canonical=a['href']
    def handle_data(self,data):
        if self.capture:self.buffer+=data
        elif data.strip():self.text.append(data)
    def handle_endtag(self,tag):
        if tag=='title' and self.capture=='title':self.title=self.buffer;self.capture=None
        if tag=='script' and self.capture=='json':self.jsonld.append(json.loads(self.buffer));self.capture=None

root=Path('_site');pages={f:Page(f) for f in root.rglob('*.html')}
errors=[]
def check(ok,message):
    if not ok:errors.append(message)
urls=[e.text for e in ET.parse(root/'sitemap.xml').iter('{http://www.sitemaps.org/schemas/sitemap/0.9}loc')]
check(len(urls)==59,f'sitemap URLs: expected 59, got {len(urls)}')
check(len(set(urls))==len(urls),'duplicate sitemap URLs')
titles=set();descriptions=set();links=0;schemas=0
for url in urls:
    file=root/urlparse(url).path.lstrip('/')/'index.html'
    check(file in pages,f'{url}: missing page')
    if file not in pages:continue
    p=pages[file]
    check(p.h1==1,f'{url}: {p.h1} H1 elements')
    check(bool(p.title.strip()) and p.title not in titles,f'{url}: duplicate/empty title')
    check(bool(p.meta.get('description')) and p.meta['description'] not in descriptions,f'{url}: duplicate/empty description')
    titles.add(p.title);descriptions.add(p.meta.get('description'))
    check(p.canonical==url,f'{url}: wrong canonical {p.canonical}')
    check(len(set(p.ids))==len(p.ids),f'{url}: duplicate IDs')
    check(bool(p.jsonld),f'{url}: no JSON-LD')
    check(not re.search(r'i(?:OS|PadOS) 17',file.read_text()),f'{url}: stale requirement')
    for s in p.jsonld:
        schemas+=1
        if s.get('@type')=='MobileApplication':
            check(s['@id']=='https://cuecard.dev/#mobileapp',f'{url}: unstable mobile entity')
            if '/android/' in url:
                check(not any(k in s for k in ['offers','installUrl','downloadUrl']),f'{url}: Android offered for installation')
            else:check('Android' not in s.get('operatingSystem',''),f'{url}: Android shown as shipping')
        if s.get('@type')=='FAQPage':
            visible=' '.join(' '.join(p.text).split())
            for q in s['mainEntity']:
                check(' '.join(q['name'].split()) in visible,f'{url}: hidden FAQ question')
                check(''.join(q['acceptedAnswer']['text'].split()) in ''.join(visible.split()),f'{url}: FAQ answer drift')
    for a in p.links:
        href=a['href'];dest=urlparse(urljoin(url,href))
        if dest.netloc!='cuecard.dev':continue
        links+=1
        target=root/unquote(dest.path).lstrip('/')
        if not target.suffix:target=target/'index.html'
        check(target.exists(),f'{url}: broken route {href}')
        if dest.fragment and target in pages:check(unquote(dest.fragment) in pages[target].ids,f'{url}: broken anchor {href}')
        check('data-product-platform' not in a,f'{url}: internal navigation measured {href}')
for name in ['index.html','404.html','CNAME','ios/index.html','android/index.html']:
    check((root/name).stat().st_size>0,f'empty deployment file {name}')
check(not list(root.rglob('*.php')),'PHP in static output')
check(not any('tutorial-action' in p.file.read_text() for p in pages.values()),'Production tutorial URL must remain empty')
if errors:
    print('\n'.join(errors));raise SystemExit(1)
print(f'PASS: {len(urls)} sitemap pages, {len(pages)} HTML files, {links} internal links, {schemas} JSON-LD blocks; unique metadata, FAQ parity, availability, anchors and deployment output verified.')
