// CueCard Website - Interactions & Animations

document.addEventListener('DOMContentLoaded', () => {
    // The live prompter in the hero: the app, running, in the page
    initDeck();

    // The menu on narrow screens, and the header's download menu
    initNavToggle();
    initDownloadMenu();

    // Reveal on scroll, smooth anchors, the sticky header's scrolled state
    initScrollReveal();
    initSmoothScroll();
    initNavbarScroll();

    // The FAQ accordion and the search box on /faq/
    initFAQAccordion();
    initFaqSearch();

    // The counting [time] tag in the script-syntax panels
    initTimestampCountdowns();

    // The Mac / Windows choice in a hero that offers both
    initOsButtons();

    // GitHub stars, and the desktop release downloads
    initGitHubData();
});


/* A hero that offers a Mac download and a Windows download shows both, and
   this drops the one the reader cannot use. It has to work that way round:
   the page is built once and served to everyone, so both buttons are in the
   HTML and a browser removes one, rather than a browser having to add one.

   If we cannot tell which machine this is - and on iOS and Android we can, it
   is neither - both buttons stay. Two working buttons is a worse hero than
   one, but it is never a wrong one. */
function initOsButtons() {
    const buttons = document.querySelectorAll('[data-os-btn]');
    if (!buttons.length) return;

    const ua = navigator.userAgent || '';
    const platform = navigator.userAgentData?.platform || navigator.platform || '';
    const both = platform + ' ' + ua;

    // An iPad reports itself as a Mac, so rule the touch devices out first:
    // neither download on this page runs on one.
    if (/iPhone|iPad|iPod|Android/i.test(ua) || (/Mac/i.test(both) && navigator.maxTouchPoints > 2)) return;

    let os = null;
    if (/Mac|Darwin/i.test(both)) os = 'mac';
    else if (/Win/i.test(both)) os = 'windows';
    if (!os) return;

    buttons.forEach((button) => {
        if (button.dataset.osBtn !== os) button.remove();
    });
}


/* The live prompter in the hero.

   Not a video and not a GIF: the same script the App Store film uses,
   scrolling at real lines per minute, with the cues in the cue colour and the
   clock counting up. You can pause it, restart it and change its speed, which
   is three of the app's controls demonstrated without a word of copy. */
function initDeck() {
    const deck = document.querySelector('[data-deck]');
    if (!deck) return;

    const script = deck.querySelector('[data-deck-script]');
    const clock = deck.querySelector('[data-deck-clock]');
    const toggle = deck.querySelector('[data-deck-toggle]');
    const restart = deck.querySelector('[data-deck-restart]');
    const speed = deck.querySelector('[data-deck-speed]');
    const screen = deck.querySelector('.deck-screen');
    if (!script || !screen) return;

    const lines = Array.from(script.querySelectorAll('.deck-line'));
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    let offset = 0;          // pixels the script has travelled
    let elapsed = 0;         // seconds on the clock
    let running = !reduced;
    let last = null;
    let lit = null;

    const linesPerMinute = () => Number(speed && speed.value) || 26;
    // One "line" is one rendered line of type; the app sets its speed the same
    // way, which is why the number on the slider means something.
    const lineHeight = () => {
        const h = parseFloat(getComputedStyle(lines[0] || script).lineHeight);
        return Number.isFinite(h) && h > 0 ? h : 28;
    };

    const setRunning = (on) => {
        running = on;
        if (toggle) {
            toggle.textContent = on ? 'Pause' : 'Play';
            toggle.setAttribute('aria-label', on ? 'Pause the prompter' : 'Play the prompter');
        }
    };

    const paintClock = () => {
        if (!clock) return;
        const total = Math.floor(elapsed);
        const m = String(Math.floor(total / 60)).padStart(2, '0');
        const s = String(total % 60).padStart(2, '0');
        clock.textContent = `${m}:${s}`;
        clock.classList.toggle('is-warn', total >= 45);
    };

    const highlight = () => {
        const mid = screen.getBoundingClientRect().top + screen.offsetHeight * 0.42;
        let best = null;
        let bestGap = Infinity;
        for (const el of lines) {
            const box = el.getBoundingClientRect();
            const gap = Math.abs(box.top + box.height / 2 - mid);
            if (gap < bestGap) { bestGap = gap; best = el; }
        }
        if (best !== lit) {
            if (lit) lit.classList.remove('is-on');
            if (best) best.classList.add('is-on');
            lit = best;
        }
    };

    const reset = () => {
        offset = 0;
        elapsed = 0;
        script.style.transform = 'translateY(0)';
        paintClock();
        highlight();
    };

    const frame = (now) => {
        if (last === null) last = now;
        const dt = Math.min(0.1, (now - last) / 1000);
        last = now;

        if (running) {
            offset += (linesPerMinute() / 60) * lineHeight() * dt;
            elapsed += dt;
            // Run off the bottom and start again, so it is always doing
            // something when someone scrolls back up to it.
            const end = script.scrollHeight - screen.offsetHeight * 0.3;
            if (offset > end) { offset = 0; elapsed = 0; }
            script.style.transform = `translateY(${-offset.toFixed(1)}px)`;
            paintClock();
            highlight();
        }
        requestAnimationFrame(frame);
    };

    if (toggle) toggle.addEventListener('click', () => setRunning(!running));
    if (restart) restart.addEventListener('click', () => { reset(); setRunning(true); });

    // Nothing should animate off-screen: it is a demo, not a background task.
    if ('IntersectionObserver' in window) {
        let seen = true;
        const io = new IntersectionObserver(([entry]) => {
            if (!entry) return;
            if (entry.isIntersecting && !seen && !reduced) { seen = true; setRunning(true); }
            else if (!entry.isIntersecting && seen) { seen = false; running = false; }
        }, { threshold: 0.15 });
        io.observe(deck);
    }

    setRunning(running);
    reset();
    requestAnimationFrame(frame);
}

/* The menu on narrow screens. The links are a plain block that is hidden by a
   media query and shown by this class, so with no JS at all the nav is still a
   row of working links rather than a button that does nothing. */
function initNavToggle() {
    const toggle = document.getElementById('nav-toggle');
    const links = document.getElementById('nav-links');
    if (!toggle || !links) return;

    toggle.addEventListener('click', () => {
        const open = links.classList.toggle('open');
        toggle.setAttribute('aria-expanded', String(open));
    });

    // Following a link should close the menu behind you.
    links.addEventListener('click', (event) => {
        if (event.target.closest('a')) {
            links.classList.remove('open');
            toggle.setAttribute('aria-expanded', 'false');
        }
    });
}

/* The header's download menu.

   It is a <details>, so it already opens and closes with no JavaScript at all.
   Everything here is a nicety on top: close when you click away from it, close
   on Escape, and put focus back on the button when Escape closes it. */
function initDownloadMenu() {
    const menu = document.getElementById('nav-get');
    if (!menu) return;

    document.addEventListener('click', (event) => {
        if (menu.open && !menu.contains(event.target)) menu.open = false;
    });

    document.addEventListener('keydown', (event) => {
        if (event.key !== 'Escape' || !menu.open) return;
        menu.open = false;
        const summary = menu.querySelector('summary');
        if (summary) summary.focus();
    });

    // Following a link out of the menu should not leave it hanging open when
    // the page is restored from the back/forward cache.
    menu.addEventListener('click', (event) => {
        if (event.target.closest('a')) menu.open = false;
    });
}

/* Reveal on scroll.

   Purely additive: the elements start at opacity 0 in the stylesheet, and a
   <noscript> rule in the head undoes that, so a reader without JS sees the page
   rather than a column of blanks. */
function initScrollReveal() {
    const items = document.querySelectorAll('.reveal, .feature-card, .faq-item');
    if (!items.length) return;

    if (!('IntersectionObserver' in window) ||
        window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
        items.forEach(el => el.classList.add('in', 'revealed'));
        return;
    }

    const observer = new IntersectionObserver(entries => {
        for (const entry of entries) {
            if (!entry.isIntersecting) continue;
            entry.target.classList.add('in', 'revealed');
            observer.unobserve(entry.target);
        }
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.05 });

    items.forEach(el => observer.observe(el));
}

// Smooth Scroll for Anchor Links
function initSmoothScroll() {
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            const href = this.getAttribute('href');
            if (!href || href === '#') return;
            const target = document.querySelector(href);
            if (target) {
                // If target is a details element, open it
                if (target.tagName === 'DETAILS' && !target.open) {
                    target.open = true;
                }

                target.scrollIntoView({
                    behavior: 'smooth',
                    block: 'center'
                });
            }
        });
    });
}

/* The masthead is opaque and sticky from the first paint, so there is no
   scrolled state to paint. The class is still toggled for anything that wants
   to hang off it. */
function initNavbarScroll() {
    const nav = document.querySelector('.nav');
    if (!nav) return;

    const onScroll = () => nav.classList.toggle('nav-scrolled', window.scrollY > 12);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
}

// FAQ Accordion Enhancement
function initFAQAccordion() {
    const faqItems = document.querySelectorAll('.faq-item');

    faqItems.forEach(item => {
        const summary = item.querySelector('summary');
        const answer = item.querySelector('.faq-answer');

        if (summary && answer) {
            // Add smooth height animation
            summary.addEventListener('click', (e) => {
                // Don't prevent default - let the details element work naturally

                // Close other items
                faqItems.forEach(otherItem => {
                    if (otherItem !== item && otherItem.open) {
                        otherItem.open = false;
                    }
                });
            });
        }
    });
}

function initFaqSearch() {
    const searchInput = document.getElementById('faq-search');
    if (!searchInput) return;

    const faqPage = searchInput.closest('[data-faq-page]') || document;
    const faqItems = Array.from(faqPage.querySelectorAll('.faq-item'));

    const indexedItems = faqItems.map((item) => ({
        item,
        text: item.textContent.toLowerCase().replace(/\s+/g, ' ').trim()
    }));

    const filterItems = () => {
        const query = searchInput.value.toLowerCase().trim();

        indexedItems.forEach(({ item, text }) => {
            const isMatch = !query || text.includes(query);
            item.style.display = isMatch ? '' : 'none';
            if (!isMatch && item.open) {
                item.open = false;
            }
        });
    };

    searchInput.addEventListener('input', filterItems);
    filterItems();
}

// Timestamp countdown animation for syntax preview
function initTimestampCountdowns() {
    const timestamps = document.querySelectorAll('.timestamp');

    timestamps.forEach(timestamp => {
        const initialSeconds = parseTimestamp(timestamp.textContent.trim(), timestamp.dataset.time);
        if (Number.isNaN(initialSeconds)) return;

        startTimestampCountdown(timestamp, initialSeconds);
    });
}

function parseTimestamp(textContent, fallbackSeconds) {
    const match = textContent.match(/\[(-?)(\d+):(\d{2})\]/);
    if (match) {
        const sign = match[1] === '-' ? -1 : 1;
        const minutes = parseInt(match[2], 10);
        const seconds = parseInt(match[3], 10);
        return sign * (minutes * 60 + seconds);
    }

    if (fallbackSeconds) {
        const parsed = parseInt(fallbackSeconds, 10);
        return Number.isNaN(parsed) ? NaN : parsed;
    }

    return NaN;
}

function startTimestampCountdown(element, initialSeconds) {
    let currentSeconds = initialSeconds;
    const minSeconds = -((59 * 60) + 59);

    const updateDisplay = () => {
        element.textContent = formatTimestamp(currentSeconds);
        updateTimestampColor(element, currentSeconds);
    };

    if (currentSeconds <= minSeconds) {
        currentSeconds = minSeconds;
        updateDisplay();
        return;
    }

    updateDisplay();

    const intervalId = setInterval(() => {
        currentSeconds -= 1;
        if (currentSeconds <= minSeconds) {
            currentSeconds = minSeconds;
            updateDisplay();
            clearInterval(intervalId);
            return;
        }
        updateDisplay();
    }, 1000);
}

// Hero badge typewriter animation
function formatTimestamp(totalSeconds) {
    const sign = totalSeconds < 0 ? '-' : '';
    const absSeconds = Math.abs(totalSeconds);
    const minutes = Math.floor(absSeconds / 60).toString().padStart(2, '0');
    const seconds = (absSeconds % 60).toString().padStart(2, '0');
    return `[${sign}${minutes}:${seconds}]`;
}

function updateTimestampColor(element, seconds) {
    element.classList.remove('timestamp-warning', 'timestamp-danger');

    if (seconds <= 0) {
        element.classList.add('timestamp-danger');
    } else if (seconds <= 10) {
        element.classList.add('timestamp-warning');
    }
}

// Handle GIF placeholder interactions
document.querySelectorAll('.gif-placeholder').forEach(placeholder => {
    placeholder.addEventListener('mouseenter', () => {
        placeholder.style.borderColor = 'rgba(255, 255, 255, 0.2)';
    });

    placeholder.addEventListener('mouseleave', () => {
        placeholder.style.borderColor = 'rgba(255, 255, 255, 0.1)';
    });
});

// Copy to clipboard for code/links (if needed later)
function copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(() => {
        // Show toast notification
        showToast('Copied to clipboard!');
    }).catch(err => {
        console.error('Failed to copy:', err);
    });
}

function showToast(message) {
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;

    const style = document.createElement('style');
    style.textContent = `
        .toast {
            position: fixed;
            bottom: 24px;
            left: 50%;
            transform: translateX(-50%) translateY(100px);
            background: #fff;
            color: #000;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 500;
            z-index: 1001;
            opacity: 0;
            transition: all 0.3s ease;
        }

        .toast.show {
            transform: translateX(-50%) translateY(0);
            opacity: 1;
        }
    `;
    document.head.appendChild(style);

    document.body.appendChild(toast);

    // Trigger animation
    setTimeout(() => toast.classList.add('show'), 10);

    // Remove after delay
    setTimeout(() => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 300);
    }, 2000);
}

// GitHub API Integration
const GITHUB_REPO = 'thisisnsh/cuecard';
// Proxy endpoint for authenticated GitHub API calls (avoids rate limiting)
// Deploy the Cloudflare Worker from /api/github-proxy-worker.js and set this URL
const GITHUB_API_PROXY = 'https://cuecard.thisisnsh.workers.dev';
let allReleases = [];

/* Two things come from GitHub: the star count, which is on every page, and the
   release list, which only the desktop download section uses.

   The download *total* deliberately does not. GitHub only counts desktop
   release assets, so a figure computed here would leave out the App Store
   entirely and understate the real number by most of it. The line on the page
   is a hand-written string in _data/site.js instead - see partials/stats.njk. */
async function initGitHubData() {
    const hasDownloadSection = !!document.getElementById('download-grid');

    try {
        const [starsResult, releasesResult] = await Promise.all([
            fetchGitHubStars(),
            hasDownloadSection ? fetchGitHubReleases() : Promise.resolve([])
        ]);

        if (starsResult) {
            updateStarsCount(starsResult);
        }

        if (!hasDownloadSection) return;

        if (releasesResult && releasesResult.length > 0) {
            allReleases = releasesResult;
        } else {
            console.log('No releases found, using sample data');
            allReleases = getSampleReleaseData();
        }

        populateReleaseDropdown();
        displayRelease(allReleases[0]); // Show latest release by default
    } catch (error) {
        console.error('Error fetching GitHub data:', error);
        if (!hasDownloadSection) return;
        // Fall back to sample data on error
        allReleases = getSampleReleaseData();
        populateReleaseDropdown();
        displayRelease(allReleases[0]);
    }
}

function getSampleReleaseData() {
    return [];

    const sampleVersion = '1.0.0';
    const sampleDate = new Date().toISOString();

    return [
        {
            tag_name: `v${sampleVersion}`,
            name: `CueCard ${sampleVersion}`,
            prerelease: false,
            published_at: sampleDate,
            body: `## What's New\n\n- Initial release of CueCard\n- Ghost mode for hiding from screen recordings\n- Google Slides sync support\n- Timer and note tags\n\n## Installation\n\nDownload the appropriate installer for your platform below.`,
            assets: [
                // macOS
                {
                    name: `CueCard_${sampleVersion}_universal.dmg`,
                    size: 45 * 1024 * 1024,
                    download_count: 1250,
                    browser_download_url: '#'
                },
                // Windows x64
                {
                    name: `CueCard_${sampleVersion}_x64-setup.exe`,
                    size: 38 * 1024 * 1024,
                    download_count: 2340,
                    browser_download_url: '#'
                },
                {
                    name: `CueCard_${sampleVersion}_x64.msi`,
                    size: 40 * 1024 * 1024,
                    download_count: 890,
                    browser_download_url: '#'
                },
                // Windows ARM64
                {
                    name: `CueCard_${sampleVersion}_arm64-setup.exe`,
                    size: 36 * 1024 * 1024,
                    download_count: 450,
                    browser_download_url: '#'
                },
                {
                    name: `CueCard_${sampleVersion}_arm64.msi`,
                    size: 38 * 1024 * 1024,
                    download_count: 220,
                    browser_download_url: '#'
                },
                // Safari Extension
                {
                    name: `CueCard_${sampleVersion}_safari.dmg`,
                    size: 12 * 1024 * 1024,
                    download_count: 890,
                    browser_download_url: '#'
                },
                // Chrome Extension
                {
                    name: `CueCard_${sampleVersion}_chrome.zip`,
                    size: 2 * 1024 * 1024,
                    download_count: 560,
                    browser_download_url: '#'
                },
                // Firefox Extension
                {
                    name: `CueCard_${sampleVersion}_firefox.zip`,
                    size: 2 * 1024 * 1024,
                    download_count: 340,
                    browser_download_url: '#'
                },
                // Files that should be filtered out
                {
                    name: `CueCard.app.tar.gz`,
                    size: 42 * 1024 * 1024,
                    download_count: 100,
                    browser_download_url: '#'
                },
                {
                    name: `CueCard.app.tar.gz.sig`,
                    size: 1024,
                    download_count: 50,
                    browser_download_url: '#'
                },
                {
                    name: `darwin-x86_64-latest.json`,
                    size: 512,
                    download_count: 200,
                    browser_download_url: '#'
                },
                {
                    name: `windows-x86_64-latest.json`,
                    size: 512,
                    download_count: 150,
                    browser_download_url: '#'
                },
                {
                    name: `CueCard_${sampleVersion}_x64-setup.exe.sig`,
                    size: 1024,
                    download_count: 30,
                    browser_download_url: '#'
                },
                {
                    name: `CueCard_${sampleVersion}_x64.msi.sig`,
                    size: 1024,
                    download_count: 25,
                    browser_download_url: '#'
                }
            ]
        }
    ];
}

async function fetchGitHubStars() {
    try {
        const response = await fetch(`${GITHUB_API_PROXY}/repos/${GITHUB_REPO}`);
        if (!response.ok) throw new Error('Failed to fetch repo data');
        const data = await response.json();
        return data.stargazers_count;
    } catch (error) {
        console.error('Error fetching stars:', error);
        return null;
    }
}

async function fetchGitHubReleases() {
    try {
        const response = await fetch(`${GITHUB_API_PROXY}/repos/${GITHUB_REPO}/releases`);
        if (!response.ok) throw new Error('Failed to fetch releases');
        const releases = await response.json();
        return releases;
    } catch (error) {
        console.error('Error fetching releases:', error);
        return [];
    }
}

/* The star count, wherever it appears - the stat line runs on every page and
   the footer carries it too, so this writes to all of them. Each one's list
   item starts hidden and is only revealed here, so a page that never hears
   back from GitHub shows nothing rather than a placeholder that jumps. */
function updateStarsCount(count) {
    document.querySelectorAll('[data-github-stars]').forEach((el) => {
        el.textContent = formatNumber(count);
        const item = el.closest('[data-stars-item]');
        if (item) item.hidden = false;
    });
}

function formatNumber(num) {
    if (num >= 1000000) {
        return (num / 1000000).toFixed(1) + 'M';
    } else if (num >= 1000) {
        return (num / 1000).toFixed(1) + 'k';
    }
    return num.toString();
}

function populateReleaseDropdown() {
    const dropdown = document.getElementById('release-select');
    if (!dropdown) return;

    dropdown.innerHTML = '';
    allReleases.forEach((release, index) => {
        const option = document.createElement('option');
        option.value = index;
        option.textContent = `${release.tag_name}${index === 0 ? ' (Latest)' : ''}${release.prerelease ? ' (Pre-release)' : ''}`;
        dropdown.appendChild(option);
    });

    dropdown.addEventListener('change', (e) => {
        const selectedRelease = allReleases[parseInt(e.target.value)];
        if (selectedRelease) {
            displayRelease(selectedRelease);
        }
    });
}

function displayRelease(release) {
    displayDownloadAssets(release.assets);
    displayReleaseNotes(release);
}

function displayDownloadAssets(assets) {
    const grid = document.getElementById('download-grid');
    if (!grid) return;

    if (!assets || assets.length === 0) {
        grid.innerHTML = '<div class="download-loading">No downloads available for this release.</div>';
        return;
    }

    // Filter assets based on specific combinations:
    // - "universal" + "dmg" -> macOS
    // - "x64" + "exe" -> Windows Personal x64
    // - "x64" + "msi" -> Windows Enterprise x64
    // - "arm" + "exe" -> Windows Personal ARM
    // - "arm" + "msi" -> Windows Enterprise ARM
    // - "safari" + "dmg" -> Safari Extension
    // - "chrome" + "zip" -> Chrome Extension
    // - "firefox" + "zip" -> Firefox Extension
    const filteredAssets = assets.filter(asset => {
        const name = asset.name.toLowerCase();
        const ext = name.split('.').pop();

        // macOS: universal + dmg
        if (name.includes('universal') && ext === 'dmg') return true;

        // Windows x64: x64 + (exe or msi)
        if (name.includes('x64') && (ext === 'exe' || ext === 'msi')) return true;

        // Windows ARM: arm + (exe or msi)
        if (name.includes('arm') && (ext === 'exe' || ext === 'msi')) return true;

        // Safari: safari + dmg
        if (name.includes('safari') && ext === 'dmg') return true;

        // Chrome: chrome + zip
        if (name.includes('chrome') && ext === 'zip') return true;

        // Firefox: firefox + zip
        if (name.includes('firefox') && ext === 'zip') return true;

        return false;
    });

    if (filteredAssets.length === 0) {
        grid.innerHTML = '<div class="download-loading">No downloads available for this release.</div>';
        return;
    }

    // Group assets by platform
    const platforms = groupAssetsByPlatform(filteredAssets);

    grid.innerHTML = '';

    // Render platform cards
    const platformOrder = ['windows_x64', 'windows_arm', 'macos', 'safari', 'chrome', 'firefox'];
    platformOrder.forEach(platformKey => {
        if (platforms[platformKey] && platforms[platformKey].assets.length > 0) {
            const card = createPlatformCard(platformKey, platforms[platformKey]);
            grid.appendChild(card);
        }
    });

    // Mobile cards removed from main download grid
}

function groupAssetsByPlatform(assets) {
    const platforms = {
        windows_x64: {
            name: 'Windows x64',
            subtitle: 'For Intel & AMD processors',
            icon: getWindowsIcon(),
            assets: [],
            totalSize: 0,
            instructions: [
                'Download EXE (personal) or MSI (enterprise)',
                'Run the installer and follow prompts',
                'If SmartScreen appears, click "More info" then "Run anyway"',
                'Launch CueCard from Start Menu'
            ],
        },
        windows_arm: {
            name: 'Windows ARM',
            subtitle: 'For Surface & Snapdragon devices',
            icon: getWindowsIcon(),
            assets: [],
            totalSize: 0,
            instructions: [
                'Download EXE (personal) or MSI (enterprise)',
                'Run the installer and follow prompts',
                'If SmartScreen appears, click "More info" then "Run anyway"',
                'Launch CueCard from Start Menu'
            ],
        },
        macos: {
            name: 'macOS',
            subtitle: 'Universal (Intel + Apple Silicon)',
            icon: getMacIcon(),
            assets: [],
            totalSize: 0,
            instructions: [
                'Open the downloaded .dmg file',
                'Drag CueCard to your Applications folder',
                'Open CueCard from Applications',
                'If prompted, click "Open" to confirm'
            ]
        },
        safari: {
            name: 'Safari Extension',
            subtitle: 'Sync notes from Google Slides',
            icon: getSafariIcon(),
            assets: [],
            totalSize: 0,
            instructions: [
                'Open the downloaded .dmg file',
                'Drag CueCard Extension to Applications',
                'Open CueCard Extension app once to install the Safari extension',
                'Go to Safari → Settings → Extensions and enable CueCard',
                'You can close the app after enabling — it only needs to run once'
            ]
        },
        chrome: {
            name: 'Chrome Extension',
            subtitle: 'Sync notes from Google Slides',
            icon: getChromeIcon(),
            assets: [],
            totalSize: 0,
            storeUrl: 'https://chromewebstore.google.com/detail/mfphcgcbbahhahofibnenonbgjnabamg',
            instructions: [
                'Download and extract the ZIP file',
                'Move the extracted folder to Documents',
                'Open Chrome and go to chrome://extensions',
                'Enable "Developer mode" in the top right',
                'Click "Load unpacked" and select the extracted folder',
            ]
        },
        firefox: {
            name: 'Firefox Extension',
            subtitle: 'Sync notes from Google Slides',
            icon: getFirefoxIcon(),
            assets: [],
            totalSize: 0,
            storeUrl: 'https://addons.mozilla.org/en-US/firefox/addon/cuecard-extension/',
            instructions: [
                'Download and extract the ZIP file',
                'Move the extracted folder to Documents',
                'Open Firefox and go to about:debugging#/runtime/this-firefox',
                'Click "Load Temporary Add-on"',
                'Select manifest.json in the extracted folder',
            ]
        }
    };

    assets.forEach(asset => {
        const name = asset.name.toLowerCase();
        const ext = name.split('.').pop();

        // macOS: universal + dmg (not safari)
        if (name.includes('universal') && ext === 'dmg' && !name.includes('safari')) {
            platforms.macos.assets.push(asset);
            platforms.macos.totalSize += asset.size;
        }
        // Safari: safari + dmg
        else if (name.includes('safari') && ext === 'dmg') {
            platforms.safari.assets.push(asset);
            platforms.safari.totalSize += asset.size;
        }
        // Chrome: chrome + zip
        else if (name.includes('chrome') && ext === 'zip') {
            platforms.chrome.assets.push(asset);
            platforms.chrome.totalSize += asset.size;
        }
        // Firefox: firefox + zip
        else if (name.includes('firefox') && ext === 'zip') {
            platforms.firefox.assets.push(asset);
            platforms.firefox.totalSize += asset.size;
        }
        // Windows x64: x64 + (exe or msi)
        else if (name.includes('x64') && (ext === 'exe' || ext === 'msi')) {
            platforms.windows_x64.assets.push(asset);
            platforms.windows_x64.totalSize += asset.size;
        }
        // Windows ARM: arm + (exe or msi)
        else if (name.includes('arm') && (ext === 'exe' || ext === 'msi')) {
            platforms.windows_arm.assets.push(asset);
            platforms.windows_arm.totalSize += asset.size;
        }
    });

    return platforms;
}

function createPlatformCard(platformKey, platform) {
    const card = document.createElement('div');
    card.className = 'platform-card';

    const downloadButtons = platform.assets.map(asset => {
        const { label, subtitle } = getDownloadButtonLabel(asset.name, asset.size, platformKey);
        const subtitleHtml = subtitle ? `<span class="btn-subtitle">${subtitle}</span>` : '';
        return `
            <a href="${asset.browser_download_url}" class="platform-download-btn" download>
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16">
                    <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
                    <polyline points="7 10 12 15 17 10"/>
                    <line x1="12" y1="15" x2="12" y2="3"/>
                </svg>
                <span class="btn-label">${label}</span>
            </a>
            ${subtitleHtml}
        `;
    }).join('');

    // Build instructions accordion
    const instructionsHtml = platform.instructions ? `
        <details class="install-instructions">
            <summary class="install-instructions-summary">
                <span>Installation Instructions</span>
                <svg class="install-instructions-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M6 9l6 6 6-6"/>
                </svg>
            </summary>
            <ol class="install-instructions-list">
                ${platform.instructions.map(step => `<li>${step}</li>`).join('')}
            </ol>
        </details>
    ` : '';

    // Add badge if present (for Chrome "Coming to Store" label)
    const badgeHtml = platform.badge ? `<span class="platform-badge">${platform.badge}</span>` : '';

    // Check if platform has a store URL (like Firefox Add-ons)
    if (platform.storeUrl) {
        // Build manual install section with download buttons
        const manualInstallHtml = platform.assets.length > 0 ? `
            <details class="manual-install-section">
                <summary class="manual-install-summary">
                    <span>Download and Install Manually</span>
                    <svg class="manual-install-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M6 9l6 6 6-6"/>
                    </svg>
                </summary>
                <div class="manual-install-content">
                    <div class="platform-downloads">
                        ${downloadButtons}
                    </div>
                    ${instructionsHtml}
                </div>
            </details>
        ` : '';

        card.innerHTML = `
            <div class="platform-card-header">
                <div class="platform-icon">${platform.icon}</div>
                <h3 class="platform-name">${platform.name}</h3>
                <p class="platform-subtitle">${platform.subtitle}</p>
            </div>
            <div class="platform-downloads">
                <a href="${platform.storeUrl}" class="platform-download-btn" target="_blank" rel="noopener noreferrer">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16">
                        <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>
                        <polyline points="15 3 21 3 21 9"/>
                        <line x1="10" y1="14" x2="21" y2="3"/>
                    </svg>
                    <span class="btn-label">Add to ${platformKey === 'chrome' ? 'Chrome' : 'Firefox'}</span>
                </a>
            </div>
            ${manualInstallHtml}
        `;
    } else {
        card.innerHTML = `
            <div class="platform-card-header">
                <div class="platform-icon">${platform.icon}</div>
                <h3 class="platform-name">${platform.name}</h3>
                <p class="platform-subtitle">${platform.subtitle}</p>
            </div>
            <div class="platform-downloads">
                ${downloadButtons}
            </div>
            ${instructionsHtml}
            ${badgeHtml}
        `;
    }

    return card;
}

function getDownloadButtonLabel(filename, size, platformKey) {
    const name = filename.toLowerCase();
    const ext = name.split('.').pop().toUpperCase();
    const sizeStr = formatFileSize(size).replace(' ', '');

    // Extract version from filename (e.g., CueCard_1.0.1_universal.dmg -> 1.0.1)
    // Supports 1, 1.1, or 1.2.3 formats and normalizes to X.Y.Z
    const versionMatch = filename.match(/[\d]+(?:\.[\d]+)?(?:\.[\d]+)?/);
    let version = '';
    if (versionMatch) {
        const parts = versionMatch[0].split('.');
        const major = parts[0] || '0';
        const minor = parts[1] || '0';
        const patch = parts[2] || '0';
        version = `v${major}.${minor}.${patch}`;
    }

    // Format: size EXT (version)
    const versionPart = version ? ` <span class="btn-version">(${version})</span>` : '';

    if (platformKey === 'macos' || platformKey === 'safari') {
        return {
            label: `${sizeStr} DMG${versionPart}`,
            subtitle: null
        };
    }

    if (platformKey === 'windows_x64' || platformKey === 'windows_arm') {
        return {
            label: `${sizeStr} ${ext}${versionPart}`,
            subtitle: null
        };
    }

    if (platformKey === 'chrome' || platformKey === 'firefox') {
        return {
            label: `${sizeStr} ZIP${versionPart}`,
            subtitle: null
        };
    }

    return { label: `${sizeStr} ${ext}${versionPart}`, subtitle: null };
}

function getMacIcon() {
    return `<svg viewBox="0 0 24 24" fill="currentColor" width="32" height="32">
        <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
    </svg>`;
}

function getWindowsIcon() {
    return `<svg viewBox="0 0 24 24" fill="currentColor" width="32" height="32">
        <path d="M3 12V6.75l6-1.32v6.48L3 12zm17-9v8.75l-10 .15V5.21L20 3zM3 13l6 .09v6.81l-6-1.15V13zm17 .25V22l-10-1.91V13.1l10 .15z"/>
    </svg>`;
}

function getSafariIcon() {
    return `<svg viewBox="0 0 24 24" fill="currentColor" width="32" height="32">
        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm-5.5-2.5l7.5-3.5 3.5-7.5-7.5 3.5-3.5 7.5zm5.5-6a1 1 0 110 2 1 1 0 010-2z"/>
    </svg>`;
}

function getChromeIcon() {
    return `<svg viewBox="0 0 24 24" fill="currentColor" width="32" height="32">
        <circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="1.5"/>
        <circle cx="12" cy="12" r="4" fill="currentColor"/>
        <path d="M21.17 8H12" stroke="currentColor" stroke-width="1.5" fill="none"/>
        <path d="M7.4 19.45L12 12" stroke="currentColor" stroke-width="1.5" fill="none"/>
        <path d="M7.4 4.55L12 12" stroke="currentColor" stroke-width="1.5" fill="none"/>
    </svg>`;
}

function getFirefoxIcon() {
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="32" height="32" fill="currentColor" aria-hidden="true">
        <path d="M12 2c-2.64 0-5.1 1.03-6.97 2.9C3.16 6.78 2 9.3 2 12c0 2.7 1.16 5.22 3.03 7.1C6.9 20.97 9.36 22 12 22c3.07 0 5.9-1.4 7.77-3.84.9-1.18 1.41-2.62 1.41-4.16 0-3.37-2.38-6.3-5.64-6.97-.45-.1-.9-.14-1.35-.14-.38 0-.76.04-1.13.1.64.35 1.2.84 1.63 1.42.53.7.82 1.55.82 2.42 0 2.25-1.82 4.07-4.07 4.07-2.25 0-4.07-1.82-4.07-4.07 0-1.4.7-2.64 1.77-3.38-.3.05-.6.12-.9.2-.7.2-1.34.53-1.9.97C7.02 7.08 6.2 8.5 6.2 10.1c0 3.2 2.6 5.8 5.8 5.8 3.2 0 5.8-2.6 5.8-5.8 0-1.93-.95-3.64-2.42-4.7C14.45 4.8 13.25 4.5 12 4.5c-.6 0-1.2.07-1.77.2C10.8 3.1 11.4 2 12 2z"/>
    </svg>`;
}

function getAppleIcon() {
    return `<svg viewBox="0 0 24 24" fill="currentColor" width="32" height="32">
        <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
    </svg>`;
}

function getAndroidIcon() {
    return `<svg viewBox="0 0 24 24" fill="currentColor" width="32" height="32">
        <path d="M17.6 9.48l1.43-2.49a.25.25 0 0 0-.09-.34.25.25 0 0 0-.34.09l-1.45 2.5A7.007 7.007 0 0 0 12 8c-1.84 0-3.55.7-4.8 1.84L5.75 7.09a.25.25 0 0 0-.34-.09.25.25 0 0 0-.09.34l1.43 2.49A5.987 5.987 0 0 0 4 14.5V19c0 .55.45 1 1 1h1v2c0 .55.45 1 1 1s1-.45 1-1v-2h8v2c0 .55.45 1 1 1s1-.45 1-1v-2h1c.55 0 1-.45 1-1v-4.5c0-1.56-.6-3-1.6-4.02zM8 14a1 1 0 1 1 0-2 1 1 0 0 1 0 2zm8 0a1 1 0 1 1 0-2 1 1 0 0 1 0 2z"/>
    </svg>`;
}

function createComingSoonCard(platformKey, platform) {
    const card = document.createElement('div');
    card.className = 'platform-card platform-card-coming-soon';

    card.innerHTML = `
        <div class="platform-card-header">
            <div class="platform-icon">${platform.icon}</div>
            <h3 class="platform-name">${platform.name}</h3>
            <p class="platform-subtitle">${platform.subtitle}</p>
        </div>
        <div class="platform-downloads">
            <span class="coming-soon-badge">Coming Soon</span>
        </div>
    `;

    return card;
}

function formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function displayReleaseNotes(release) {
    const releaseNotesBtn = document.getElementById('release-notes-btn');
    if (!releaseNotesBtn) return;

    // Update button to link to the specific release page
    if (release.html_url) {
        releaseNotesBtn.href = release.html_url;
    } else {
        releaseNotesBtn.href = `https://github.com/thisisnsh/cuecard/releases/tag/${release.tag_name}`;
    }
}

function parseMarkdown(text) {
    // Simple markdown parser
    let html = text
        // Escape HTML
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        // Headers
        .replace(/^### (.*$)/gim, '<h3>$1</h3>')
        .replace(/^## (.*$)/gim, '<h2>$1</h2>')
        .replace(/^# (.*$)/gim, '<h1>$1</h1>')
        // Bold
        .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
        // Italic
        .replace(/\*(.*?)\*/g, '<em>$1</em>')
        // Code blocks
        .replace(/```([\s\S]*?)```/g, '<pre><code>$1</code></pre>')
        // Inline code
        .replace(/`([^`]+)`/g, '<code>$1</code>')
        // Links
        .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>')
        // Unordered lists
        .replace(/^\s*[-*]\s+(.*)$/gim, '<li>$1</li>')
        // Paragraphs (double newlines)
        .replace(/\n\n/g, '</p><p>')
        // Single newlines to br
        .replace(/\n/g, '<br>');

    // Wrap consecutive li elements in ul
    html = html.replace(/(<li>.*?<\/li>)+/gs, '<ul>$&</ul>');

    // Wrap in paragraph tags
    html = '<p>' + html + '</p>';

    // Clean up empty paragraphs
    html = html.replace(/<p><\/p>/g, '');
    html = html.replace(/<p><br>/g, '<p>');
    html = html.replace(/<br><\/p>/g, '</p>');

    return html;
}

function showDownloadError() {
    const grid = document.getElementById('download-grid');
    if (grid) {
        grid.innerHTML = `
            <div class="download-loading">
                Unable to load releases.
                <a href="https://github.com/${GITHUB_REPO}/releases" target="_blank" rel="noopener">
                    View releases on GitHub
                </a>
            </div>
        `;
    }
}
