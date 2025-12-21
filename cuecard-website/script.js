// CueCard Website - Interactions & Animations

document.addEventListener('DOMContentLoaded', () => {
    // Initialize scroll reveal animations
    initScrollReveal();

    // Initialize smooth scroll for anchor links
    initSmoothScroll();

    // Initialize navbar scroll effect
    initNavbarScroll();

    // Initialize FAQ accordion
    initFAQAccordion();

    // Initialize timestamp countdown demo
    initTimestampCountdowns();

    // Initialize Ghost Mode GIF animation
    initGhostModeAnimation();

    // Initialize hero badge typewriter
    initHeroBadgeTypewriter();

    // Initialize GitHub stats and releases
    initGitHubData();
});

// Scroll Reveal Animation
function initScrollReveal() {
    const revealElements = document.querySelectorAll('.use-case-card, .feature-card, .faq-item');

    const revealOnScroll = () => {
        const windowHeight = window.innerHeight;

        revealElements.forEach((element, index) => {
            const elementTop = element.getBoundingClientRect().top;
            const revealPoint = 100;

            if (elementTop < windowHeight - revealPoint) {
                // Add staggered delay based on index within viewport
                element.style.transitionDelay = `${(index % 4) * 0.1}s`;
                element.classList.add('revealed');
            }
        });
    };

    // Add CSS for reveal animation
    const style = document.createElement('style');
    style.textContent = `
        .use-case-card, .feature-card, .faq-item {
            opacity: 0;
            transform: translateY(30px);
            transition: opacity 0.6s ease-out, transform 0.6s ease-out;
        }

        .use-case-card.revealed, .feature-card.revealed, .faq-item.revealed {
            opacity: 1;
            transform: translateY(0);
        }
    `;
    document.head.appendChild(style);

    // Run on load and scroll
    window.addEventListener('scroll', revealOnScroll, { passive: true });
    revealOnScroll(); // Initial check
}

// Smooth Scroll for Anchor Links
function initSmoothScroll() {
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            const href = this.getAttribute('href');
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

// Navbar Background on Scroll
function initNavbarScroll() {
    const nav = document.querySelector('.nav');
    let lastScroll = 0;

    window.addEventListener('scroll', () => {
        const currentScroll = window.pageYOffset;

        // Add/remove scrolled class for styling
        if (currentScroll > 50) {
            nav.classList.add('nav-scrolled');
        } else {
            nav.classList.remove('nav-scrolled');
        }

        // Hide/show on scroll direction (optional - commented out for simplicity)
        // if (currentScroll > lastScroll && currentScroll > 100) {
        //     nav.style.transform = 'translateY(-100%)';
        // } else {
        //     nav.style.transform = 'translateY(0)';
        // }

        lastScroll = currentScroll;
    }, { passive: true });

    // Add CSS for scrolled state
    const style = document.createElement('style');
    style.textContent = `
        .nav {
            transition: background 0.3s ease, border-color 0.3s ease;
        }

        .nav-scrolled {
            background: rgba(0, 0, 0, 0.95);
            border-bottom-color: rgba(255, 255, 255, 0.1);
        }
    `;
    document.head.appendChild(style);
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
function initHeroBadgeTypewriter() {
    const heroBadge = document.querySelector('.hero-badge');
    if (!heroBadge) return;

    const messages = [
        { text: 'Paste notes for any meeting', theme: 'green' },
        { text: 'Sync notes from Google Slides', theme: 'yellow' },
        { text: 'Free and Open Source', theme: 'white' }
    ];

    // Create span for animated text
    const textSpan = document.createElement('span');
    textSpan.className = 'hero-badge-text';
    textSpan.textContent = messages[0].text;

    // Clear badge and append span
    heroBadge.textContent = '';
    heroBadge.appendChild(textSpan);

    const themes = ['hero-badge--yellow', 'hero-badge--green', 'hero-badge--white'];
    const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));

    const setTheme = (theme) => {
        heroBadge.classList.remove(...themes);
        heroBadge.classList.add(`hero-badge--${theme}`);
    };

    const typeText = async (text) => {
        for (const char of text) {
            textSpan.textContent += char;
            await wait(60);
        }
    };

    const deleteText = async () => {
        while (textSpan.textContent.length > 0) {
            textSpan.textContent = textSpan.textContent.slice(0, -1);
            await wait(35);
        }
    };

    const startTypewriter = async () => {
        let index = 1;
        await wait(1000);
        await deleteText();
        await wait(400);
        while (true) {
            const { text, theme } = messages[index];
            setTheme(theme);
            await typeText(text);
            await wait(1500);
            await deleteText();
            await wait(400);
            index = (index + 1) % messages.length;
        }
    };

    startTypewriter();
}

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

// Cursor trail effect (subtle, optional)
function initCursorEffect() {
    const cursor = document.createElement('div');
    cursor.classList.add('cursor-glow');
    document.body.appendChild(cursor);

    const style = document.createElement('style');
    style.textContent = `
        .cursor-glow {
            position: fixed;
            width: 300px;
            height: 300px;
            background: radial-gradient(circle, rgba(26, 178, 196, 0.1) 0%, transparent 70%);
            border-radius: 50%;
            pointer-events: none;
            z-index: 0;
            transform: translate(-50%, -50%);
            transition: opacity 0.3s ease;
            opacity: 0;
        }

        body:hover .cursor-glow {
            opacity: 1;
        }
    `;
    document.head.appendChild(style);

    let mouseX = 0, mouseY = 0;
    let cursorX = 0, cursorY = 0;

    document.addEventListener('mousemove', (e) => {
        mouseX = e.clientX;
        mouseY = e.clientY;
    });

    function animateCursor() {
        cursorX += (mouseX - cursorX) * 0.1;
        cursorY += (mouseY - cursorY) * 0.1;

        cursor.style.left = cursorX + 'px';
        cursor.style.top = cursorY + 'px';

        requestAnimationFrame(animateCursor);
    }

    animateCursor();
}

// Initialize cursor effect only on desktop
if (window.matchMedia('(hover: hover)').matches && window.innerWidth > 1024) {
    initCursorEffect();
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
let allReleases = [];
let totalDownloads = 0;

async function initGitHubData() {
    try {
        // Fetch stars and releases in parallel
        const [starsResult, releasesResult] = await Promise.all([
            fetchGitHubStars(),
            fetchGitHubReleases()
        ]);

        // Update stars count
        if (starsResult) {
            updateStarsCount(starsResult);
        }

        // Update releases - use sample data if no releases found
        if (releasesResult && releasesResult.length > 0) {
            allReleases = releasesResult;
        } else {
            console.log('No releases found, using sample data');
            allReleases = getSampleReleaseData();
        }

        calculateTotalDownloads();
        populateReleaseDropdown();
        displayRelease(allReleases[0]); // Show latest release by default
    } catch (error) {
        console.error('Error fetching GitHub data:', error);
        // Fall back to sample data on error
        allReleases = getSampleReleaseData();
        calculateTotalDownloads();
        populateReleaseDropdown();
        displayRelease(allReleases[0]);
    }
}

function getSampleReleaseData() {
    return [];
}

async function fetchGitHubStars() {
    try {
        const response = await fetch(`https://api.github.com/repos/${GITHUB_REPO}`);
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
        const response = await fetch(`https://api.github.com/repos/${GITHUB_REPO}/releases`);
        if (!response.ok) throw new Error('Failed to fetch releases');
        const releases = await response.json();
        return releases;
    } catch (error) {
        console.error('Error fetching releases:', error);
        return [];
    }
}

function updateStarsCount(count) {
    const starsElement = document.getElementById('github-stars');
    if (starsElement) {
        starsElement.textContent = formatNumber(count) + " GitHub Stars";
    }

}

function formatNumber(num) {
    if (num >= 1000000) {
        return (num / 1000000).toFixed(1) + 'M';
    } else if (num >= 1000) {
        return (num / 1000).toFixed(1) + 'k';
    }
    return num.toString();
}

function calculateTotalDownloads() {
    totalDownloads = 0;
    allReleases.forEach(release => {
        release.assets.forEach(asset => {
            // Exclude *latest.json files from total downloads
            if (!asset.name.toLowerCase().endsWith('latest.json')) {
                totalDownloads += asset.download_count;
            }
        });
    });

    const totalElement = document.getElementById('total-downloads');
    if (totalElement && totalDownloads > 0) {
        totalElement.innerHTML = `
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
                <polyline points="7 10 12 15 17 10"/>
                <line x1="12" y1="15" x2="12" y2="3"/>
            </svg>
            ${formatNumber(totalDownloads)} downloads
        `;
    }

    // Update nav download button with total downloads
    const navDownloadCount = document.getElementById('nav-download-count');
    if (navDownloadCount && totalDownloads > 0) {
        navDownloadCount.textContent = formatNumber(totalDownloads) + " Downloads";
    }

    // Update hero download button with total downloads
    const heroDownloadText = document.getElementById('hero-download-text');
    if (heroDownloadText && totalDownloads > 0) {
        heroDownloadText.textContent = formatNumber(totalDownloads) + " Downloads";
    }
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
            badge: 'Beta'
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
            badge: 'Beta'
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
            instructions: [
                'Download and extract the ZIP file',
                'Open Chrome and go to chrome://extensions',
                'Enable "Developer mode" in the top right',
                'Click "Load unpacked" and select the extracted folder',
            ],
            badge: 'Coming to Web Store'
        },
        firefox: {
            name: 'Firefox Extension',
            subtitle: 'Sync notes from Google Slides',
            icon: getFirefoxIcon(),
            assets: [],
            totalSize: 0,
            instructions: [
                'Download the ZIP file',
                'Open Firefox and go to about:debugging#/runtime/this-firefox',
                'Click "Load Temporary Add-on"',
                'Select the ZIP file (no need to extract)',
            ],
            badge: 'Coming to Add-ons'
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

    // Add badge if present (for Chrome/Firefox "Coming to Store" labels)
    const badgeHtml = platform.badge ? `<span class="platform-badge">${platform.badge}</span>` : '';

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

function formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function displayReleaseNotes(release) {
    const notesContainer = document.getElementById('release-notes');
    if (!notesContainer) return;

    if (!release.body) {
        notesContainer.classList.remove('has-content');
        return;
    }

    const date = new Date(release.published_at).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric'
    });

    notesContainer.innerHTML = `
        <div class="release-notes-header">
            <h3 class="release-notes-title">Release Notes - ${release.tag_name}</h3>
            <span class="release-notes-date">${date}</span>
        </div>
        <div class="release-notes-content">
            ${parseMarkdown(release.body)}
        </div>
    `;
    notesContainer.classList.add('has-content');
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

// Ghost Mode GIF Animation
function initGhostModeAnimation() {
    const demo = document.querySelector('.gif-demo-visibility');
    if (!demo) return;

    const screenArea = demo.querySelector('.demo-screen-area');
    const floatingApp = demo.querySelector('.demo-floating-app');
    const toggleTrack = demo.querySelector('.demo-toggle-track');
    const toggleThumb = demo.querySelector('.demo-toggle-thumb');
    const bannerOn = demo.querySelector('.demo-banner-on');
    const bannerOff = demo.querySelector('.demo-banner-off');
    const cursor = demo.querySelector('.demo-cursor');

    if (!screenArea || !floatingApp || !toggleTrack || !toggleThumb || !bannerOn || !bannerOff) return;

    // Animation states
    const setToggleOn = () => {
        toggleTrack.style.background = '#19c332';
        toggleThumb.style.left = '22px';
    };

    const setToggleOff = () => {
        toggleTrack.style.background = '#444';
        toggleThumb.style.left = '2px';
    };

    const showApp = () => {
        floatingApp.style.opacity = '1';
    };

    const hideApp = () => {
        floatingApp.style.opacity = '0';
    };

    const showDashedBox = () => {
        screenArea.style.borderColor = '#19c332';
    };

    const hideDashedBox = () => {
        screenArea.style.borderColor = 'transparent';
    };

    const showBannerOn = () => {
        bannerOn.style.opacity = '1';
        bannerOff.style.opacity = '0';
    };

    const showBannerOff = () => {
        bannerOn.style.opacity = '0';
        bannerOff.style.opacity = '1';
    };

    const showCursor = () => {
        if (cursor) {
            // Position cursor near the banner (bottom center area)
            cursor.style.bottom = '15px';
            cursor.style.left = 'calc(50% + 60px)';
            cursor.style.opacity = '1';
        }
    };

    const hideCursor = () => {
        if (cursor) {
            cursor.style.opacity = '0';
        }
    };

    // Animation sequence
    async function runAnimation() {
        // Initial state: Toggle ON, screen sharing active
        setToggleOn();
        showApp();
        showDashedBox();
        showBannerOn();
        hideCursor();

        await sleep(1500);

        // Step 1: Toggle OFF - CueCard hides (simulating it's hidden from screen share)
        setToggleOff();
        hideApp();

        await sleep(1500);

        // Step 2: Show cursor, then banner changes
        showCursor();
        await sleep(300);
        showBannerOff();
        hideDashedBox();
        hideCursor();

        await sleep(300);
        showApp();

        await sleep(1500);

        // Step 3: Toggle ON
        setToggleOn();

        await sleep(1500);

        // Step 4: Show cursor, then banner changes
        showCursor();
        await sleep(300);
        showBannerOn();
        showDashedBox();
        hideCursor();

        await sleep(1500);

        // Loop
        runAnimation();
    }

    function sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    // Start animation
    runAnimation();
}
