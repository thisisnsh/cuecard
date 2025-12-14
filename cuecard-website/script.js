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
        anchor.addEventListener('click', function(e) {
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                target.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
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
        { text: 'Sync notes from Google Slides', theme: 'yellow' },
        { text: 'Paste notes for any meeting', theme: 'green' },
        { text: 'Free and Open Source', theme: 'white' }
    ];

    const textSpan = document.createElement('span');
    textSpan.className = 'hero-badge-text';

    heroBadge.textContent = '';
    heroBadge.append(textSpan);

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
        let index = 0;
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

// Analytics placeholder (implement your own tracking)
function trackEvent(eventName, properties = {}) {
    // console.log('Event:', eventName, properties);
    // Implement your analytics here
}

// Track CTA clicks
document.querySelectorAll('.btn-primary').forEach(btn => {
    btn.addEventListener('click', () => {
        trackEvent('cta_click', {
            text: btn.textContent.trim(),
            location: window.location.pathname
        });
    });
});

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
        screenArea.style.borderColor = '#6fa8dc';
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
