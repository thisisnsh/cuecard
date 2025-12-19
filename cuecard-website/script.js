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

// Intersection Observer for performance (alternative to scroll event)
function initIntersectionObserver() {
    const options = {
        root: null,
        rootMargin: '0px',
        threshold: 0.1
    };

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('in-view');
            }
        });
    }, options);

    document.querySelectorAll('.use-case-card, .feature-card').forEach(el => {
        observer.observe(el);
    });
}

// Preload fonts for better performance
function preloadFonts() {
    const fonts = [
        'https://fonts.googleapis.com/css2?family=Syne:wght@700;800&display=swap',
        'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap'
    ];

    fonts.forEach(font => {
        const link = document.createElement('link');
        link.rel = 'preload';
        link.as = 'style';
        link.href = font;
        document.head.appendChild(link);
    });
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
                    size: 45 * 1024 * 1024, // 45 MB
                    download_count: 1250,
                    browser_download_url: '#'
                },
                // Safari Extension
                {
                    name: `CueCard_Extension_${sampleVersion}_universal.dmg`,
                    size: 12 * 1024 * 1024, // 12 MB
                    download_count: 890,
                    browser_download_url: '#'
                },
                // Windows x64
                {
                    name: `CueCard_${sampleVersion}_x64-setup.exe`,
                    size: 38 * 1024 * 1024, // 38 MB
                    download_count: 2340,
                    browser_download_url: '#'
                },
                {
                    name: `CueCard_${sampleVersion}_x64.msi`,
                    size: 40 * 1024 * 1024, // 40 MB
                    download_count: 890,
                    browser_download_url: '#'
                },
                // Windows ARM64
                {
                    name: `CueCard_${sampleVersion}_arm64-setup.exe`,
                    size: 36 * 1024 * 1024, // 36 MB
                    download_count: 450,
                    browser_download_url: '#'
                },
                {
                    name: `CueCard_${sampleVersion}_arm64.msi`,
                    size: 38 * 1024 * 1024, // 38 MB
                    download_count: 220,
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

    // Update hero source button with stars
    const heroStarsText = document.getElementById('hero-stars-text');
    // Show github stars in hero if needed
    // if (heroStarsText) {
    // heroStarsText.textContent = formatNumber(count) + " GitHub Stars";
    // }
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

    // Filter to only show .dmg, .exe, .msi files
    const allowedExtensions = ['.dmg', '.exe', '.msi'];
    const filteredAssets = assets.filter(asset => {
        const name = asset.name.toLowerCase();
        return allowedExtensions.some(ext => name.endsWith(ext));
    });

    if (filteredAssets.length === 0) {
        grid.innerHTML = '<div class="download-loading">No downloads available for this release.</div>';
        return;
    }

    // Group assets by platform
    const platforms = groupAssetsByPlatform(filteredAssets);

    grid.innerHTML = '';

    // Render platform cards in 2x2 grid: Row 1 = macOS + Safari, Row 2 = Windows x64 + Windows ARM
    const platformOrder = ['macos', 'safari', 'windows_x64', 'windows_arm'];
    platformOrder.forEach(platformKey => {
        if (platforms[platformKey] && platforms[platformKey].assets.length > 0) {
            const card = createPlatformCard(platformKey, platforms[platformKey]);
            grid.appendChild(card);
        }
    });
}

function groupAssetsByPlatform(assets) {
    const platforms = {
        macos: {
            name: 'macOS',
            subtitle: 'Native macOS application',
            icon: getMacIcon(),
            assets: [],
            totalSize: 0
        },
        safari: {
            name: 'Safari Extension',
            subtitle: 'Browser extension for Safari',
            icon: getSafariIcon(),
            assets: [],
            totalSize: 0
        },
        windows_x64: {
            name: 'Windows x64',
            subtitle: 'For Intel & AMD processors',
            icon: getWindowsIcon(),
            assets: [],
            totalSize: 0
        },
        windows_arm: {
            name: 'Windows ARM',
            subtitle: 'For Surface & Snapdragon',
            icon: getWindowsIcon(),
            assets: [],
            totalSize: 0
        }
    };

    assets.forEach(asset => {
        const name = asset.name.toLowerCase();
        const ext = name.split('.').pop();
        const isExtension = name.includes('extension');
        const isArm = name.includes('arm64') || name.includes('aarch64');

        if (isExtension && ext === 'dmg') {
            platforms.safari.assets.push(asset);
            platforms.safari.totalSize += asset.size;
        } else if (ext === 'dmg') {
            platforms.macos.assets.push(asset);
            platforms.macos.totalSize += asset.size;
        } else if (ext === 'exe' || ext === 'msi') {
            if (isArm) {
                platforms.windows_arm.assets.push(asset);
                platforms.windows_arm.totalSize += asset.size;
            } else {
                platforms.windows_x64.assets.push(asset);
                platforms.windows_x64.totalSize += asset.size;
            }
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

    card.innerHTML = `
        <div class="platform-card-header">
            <div class="platform-icon">${platform.icon}</div>
            <h3 class="platform-name">${platform.name}</h3>
            <p class="platform-subtitle">${platform.subtitle}</p>
        </div>
        <div class="platform-downloads">
            ${downloadButtons}
        </div>
    `;

    return card;
}

function getDownloadButtonLabel(filename, size, platformKey) {
    const name = filename.toLowerCase();
    const ext = name.split('.').pop();
    const sizeStr = formatFileSize(size);

    // Extract version from filename (e.g., CueCard_1.0.1_universal.dmg -> 1.0.1)
    // Supports 1, 1.1, or 1.2.3 formats and normalizes to X.Y.Z
    const versionMatch = filename.match(/[\d]+(?:\.[\d]+)?(?:\.[\d]+)?/);
    let version = '';
    if (versionMatch) {
        const parts = versionMatch[0].split('.');
        const major = parts[0] || '0';
        const minor = parts[1] || '0';
        const patch = parts[2] || '0';
        version = `(v${major}.${minor}.${patch})`;
    }

    if (platformKey === 'macos') {
        if (name.includes('universal')) {
            return {
                label: `Universal ${version} - ${sizeStr}`,
                subtitle: 'Intel + Apple Silicon'
            };
        } else if (name.includes('arm64') || name.includes('aarch64')) {
            return {
                label: `Apple Silicon ${version} - ${sizeStr}`,
                subtitle: null
            };
        } else if (name.includes('x64') || name.includes('x86_64')) {
            return {
                label: `Intel ${version} - ${sizeStr}`,
                subtitle: null
            };
        }
        return { label: `Download ${version} - ${sizeStr}`, subtitle: null };
    }

    if (platformKey === 'safari') {
        if (name.includes('universal')) {
            return {
                label: `Universal ${version} - ${sizeStr}`,
                subtitle: 'Intel + Apple Silicon'
            };
        }
        return { label: `Download ${version} - ${sizeStr}`, subtitle: null };
    }

    if (platformKey === 'windows_x64' || platformKey === 'windows_arm') {
        if (ext === 'exe') {
            return {
                label: `EXE Personal ${version} - ${sizeStr}`,
                subtitle: null
            };
        } else if (ext === 'msi') {
            return {
                label: `MSI Enterprise ${version} - ${sizeStr}`,
                subtitle: null
            };
        }
    }

    return { label: `Download ${version} - ${sizeStr}`, subtitle: null };
}

function getAssetDisplayInfo(filename) {
    // Get extension
    const ext = filename.split('.').pop().toLowerCase();
    const nameLower = filename.toLowerCase();

    // Check if it's an extension/Safari file
    const isExtension = nameLower.includes('extension');

    // Remove extension from filename for display
    const nameWithoutExt = filename.replace(/\.[^/.]+$/, '');

    // Parse the filename: CueCard_Extension_1.0.0_universal or CueCard_1.0.0_universal
    // Remove "CueCard" prefix and clean up
    let displayName = nameWithoutExt
        .replace(/^CueCard[_\s]*/i, '') // Remove CueCard prefix
        .replace(/_/g, ' ')
        .replace(/-setup/gi, '')
        .replace(/\s+/g, ' ')
        .trim();

    // If it starts with "Extension", extract just "Extension" as the main name
    // and append architecture info
    if (displayName.toLowerCase().startsWith('extension')) {
        // CueCard_Extension_1.0.0_universal -> "Extension 1.0.0 universal"
        displayName = displayName
            .replace(/^extension\s*/i, 'Extension ')
            .trim();
    }

    // Replace "universal" with "Intel + Apple Silicon"
    displayName = displayName
        .replace(/\buniversal\b/gi, 'Intel + Apple Silicon')
        .replace(/\bx64\b/gi, 'x64')
        .replace(/\bx86\b/gi, 'x86')
        .replace(/\barm64\b/gi, 'ARM64');

    // Clean up any double spaces
    displayName = displayName.replace(/\s+/g, ' ').trim();

    // Friendly type names
    const friendlyTypes = {
        'dmg': 'DMG Disk Image',
        'exe': 'EXE Personal',
        'msi': 'MSI Enterprise'
    };

    const friendlyType = friendlyTypes[ext] || ext.toUpperCase();

    // Determine platform icon
    let platformIcon;
    if (isExtension && ext === 'dmg') {
        // Safari icon for Extension .dmg
        platformIcon = getSafariIcon();
    } else if (ext === 'dmg') {
        // macOS icon for regular .dmg
        platformIcon = getMacIcon();
    } else if (ext === 'exe' || ext === 'msi') {
        // Windows icon
        platformIcon = getWindowsIcon();
    } else {
        // Default file icon
        platformIcon = getDefaultFileIcon();
    }

    return {
        displayName,
        extension: ext.toUpperCase(),
        friendlyType,
        platformIcon
    };
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

function getDefaultFileIcon() {
    return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="32" height="32">
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
        <polyline points="14 2 14 8 20 8"/>
    </svg>`;
}

function getAssetIcon(filename) {
    const ext = filename.split('.').pop().toLowerCase();
    const name = filename.toLowerCase();

    // macOS
    if (name.includes('darwin') || name.includes('macos') || name.includes('mac') || ext === 'dmg') {
        return `<svg viewBox="0 0 24 24" fill="currentColor">
            <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
        </svg>`;
    }

    // Windows
    if (name.includes('windows') || name.includes('win') || ext === 'exe' || ext === 'msi') {
        return `<svg viewBox="0 0 24 24" fill="currentColor">
            <path d="M3 12V6.75l6-1.32v6.48L3 12zm17-9v8.75l-10 .15V5.21L20 3zM3 13l6 .09v6.81l-6-1.15V13zm17 .25V22l-10-1.91V13.1l10 .15z"/>
        </svg>`;
    }

    // Linux
    if (name.includes('linux') || ext === 'deb' || ext === 'rpm' || ext === 'appimage') {
        return `<svg viewBox="0 0 24 24" fill="currentColor">
            <path d="M12.504 0c-.155 0-.315.008-.48.021-4.226.333-3.105 4.807-3.17 6.298-.076 1.092-.3 1.953-1.05 3.02-.885 1.051-2.127 2.75-2.716 4.521-.278.832-.41 1.684-.287 2.489a.424.424 0 00-.11.135c-.26.268-.45.6-.663.839-.199.199-.485.267-.797.4-.313.136-.658.269-.864.68-.09.189-.136.394-.132.602 0 .199.027.4.055.536.058.399.116.728.04.97-.249.68-.28 1.145-.106 1.484.174.334.535.47.94.601.81.2 1.91.135 2.774.6.926.466 1.866.67 2.616.47.526-.116.97-.464 1.208-.946.587-.003 1.23-.269 2.26-.334.699-.058 1.574.267 2.577.2.025.134.063.198.114.333l.003.003c.391.778 1.113 1.132 1.884 1.071.771-.06 1.592-.536 2.257-1.306.631-.765 1.683-1.084 2.378-1.503.348-.199.629-.469.649-.853.023-.4-.2-.811-.714-1.376v-.097l-.003-.003c-.17-.2-.25-.535-.338-.926-.085-.401-.182-.786-.492-1.046h-.003c-.059-.054-.123-.067-.188-.135a.357.357 0 00-.19-.064c.431-1.278.264-2.55-.173-3.694-.533-1.41-1.465-2.638-2.175-3.483-.796-1.005-1.576-1.957-1.56-3.368.026-2.152.236-6.133-3.544-6.139zm.529 3.405h.013c.213 0 .396.062.584.198.19.135.33.332.438.533.105.259.158.459.166.724 0-.02.006-.04.006-.06v.105a.086.086 0 01-.004-.021l-.004-.024a1.807 1.807 0 01-.15.706.953.953 0 01-.213.335.71.71 0 00-.088-.042c-.104-.045-.198-.064-.284-.133a1.312 1.312 0 00-.22-.066c.05-.06.146-.133.183-.198.053-.128.082-.262.083-.402 0-.037-.007-.066-.007-.106a.18.18 0 01-.007-.035.14.14 0 01-.01-.039c-.01-.04-.04-.134-.04-.2a.29.29 0 01-.01-.06c0-.04.006-.063.006-.1 0-.03-.012-.06-.012-.09a.559.559 0 00-.01-.053.232.232 0 01-.004-.037c-.01-.06-.023-.11-.023-.17l-.01-.03c-.004-.008-.008-.02-.014-.027-.008-.014-.025-.024-.05-.042-.06-.036-.15-.053-.27-.053-.038 0-.096.003-.142.01-.106.01-.197.037-.27.066a.727.727 0 00-.262.177c-.053.058-.098.118-.16.197-.078.098-.177.266-.228.399l-.004.007-.004.007c-.017.055-.033.098-.05.137-.024.062-.04.11-.05.16-.01.03-.02.057-.027.086l-.01.03c-.023.078-.044.175-.078.276-.04.105-.09.242-.128.392l-.004.013a1.3 1.3 0 00-.05.246c.023-.5.033-.86.073-1.133.04-.27.09-.47.16-.615.07-.145.14-.24.25-.31a.56.56 0 01.168-.09.86.86 0 01.175-.04zm-4.23.638l.004.034.002.027v.002l.003.02.006.012.003.01.003.01.002.006.002.008v.004c.005.016.013.032.02.049l.002.003c.004.01.013.013.013.02l.014.018c.01.014.017.028.03.04.01.013.02.02.03.024a.062.062 0 00.018.01c.004.002.006.002.01.004.01.01.015.01.024.013.01.004.02.002.027.003.01 0 .016.002.025.002.007 0 .016-.002.024-.002.01 0 .02-.01.03-.01.007-.01.013-.01.02-.02l.01-.01c.003-.003.007-.003.01-.007a.14.14 0 00.01-.02c.015-.02.027-.04.04-.06l.002-.01c.016-.03.03-.052.05-.092.02-.04.03-.073.04-.11l.01-.034c.01-.028.017-.06.02-.096l.004-.04c.014-.16.014-.34-.044-.53-.023-.077-.034-.16-.066-.253a2.13 2.13 0 00-.176-.399c-.11-.175-.243-.326-.428-.437a.848.848 0 00-.252-.108.824.824 0 00-.299-.03c-.062.01-.145.017-.21.05a.725.725 0 00-.192.1.675.675 0 00-.15.147.66.66 0 00-.09.169.62.62 0 00-.04.2c-.003.066.006.14.02.2.016.077.03.15.063.23a.76.76 0 00.096.17c.04.063.09.11.14.15.03.02.05.04.08.05l.04.02c.016.01.03.013.043.02.01.002.016.004.024.006a.17.17 0 00.034.004c.01 0 .02 0 .027-.003a.093.093 0 00.03-.01c.018-.006.03-.016.04-.024l.03-.023a.18.18 0 00.02-.026c.003-.003.003-.006.006-.01l.007-.014a.13.13 0 00.007-.02.16.16 0 00.007-.02l.003-.014.003-.01v-.008l.002-.02v-.01a.14.14 0 000-.014l-.004-.016a.05.05 0 00-.003-.013z"/>
        </svg>`;
    }

    // ZIP file
    if (ext === 'zip') {
        return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/>
        </svg>`;
    }

    // Default file icon
    return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
        <polyline points="14 2 14 8 20 8"/>
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
