// CueCard Extension - Content Script
// Detects slide changes in Google Slides and sends data to the CueCard app

(function() {
  'use strict';

  const CONFIG = {
    API_ENDPOINT: 'http://localhost:3642/slides',
    DEBOUNCE_MS: 50,
    RETRY_ATTEMPTS: 3,
    RETRY_DELAY_MS: 1000,
    POLL_INTERVAL_MS: 1000
  };

  // State management
  let currentSlideInfo = null;
  let isInitialized = false;
  let observers = [];

  // Detect current mode (edit vs slideshow)
  function detectMode() {
    const url = window.location.href;
    if (url.includes('/present')) {
      return 'slideshow';
    } else if (url.includes('/edit') || url.includes('/view')) {
      return 'edit';
    } else if (url.includes('/pub')) {
      return 'published';
    }
    return 'unknown';
  }

  // Extract presentation ID from URL
  function getPresentationId() {
    const match = window.location.pathname.match(/\/presentation\/d\/([a-zA-Z0-9_-]+)/);
    return match ? match[1] : null;
  }

  // Extract slide info from URL hash (edit mode)
  function getSlideFromHash() {
    const hash = window.location.hash;
    const match = hash.match(/slide=id\.([a-zA-Z0-9_-]+)/);
    return match ? match[1] : null;
  }

  // Extract slide info from URL query (slideshow mode)
  function getSlideFromQuery() {
    const params = new URLSearchParams(window.location.search);
    const slide = params.get('slide');
    if (slide) {
      const match = slide.match(/id\.([a-zA-Z0-9_-]+)/);
      return match ? match[1] : null;
    }
    return null;
  }

  // Get presentation title from DOM
  function getPresentationTitle() {
    // Edit mode: title is in the document title or specific element
    const titleElement = document.querySelector('[data-name="title"]') ||
                        document.querySelector('.docs-title-input') ||
                        document.querySelector('input.docs-title-input-label-inner');
    if (titleElement) {
      return titleElement.textContent || titleElement.value || 'Untitled Presentation';
    }
    // Fallback to document title
    const docTitle = document.title.replace(' - Google Slides', '').replace(' - Google Präsentationen', '');
    return docTitle || 'Untitled Presentation';
  }

  // Which slide of the deck this is.
  //
  // Google puts the slide's id in the URL but never its number, so the number
  // has to be read off the page: the filmstrip while editing, the counter in
  // the toolbar while presenting. Both are Google's own markup and both get
  // renamed from time to time, so each way is tried in turn and a miss just
  // means 0 — the app numbers the slide from the deck itself when it can.
  const FILMSTRIP_SELECTORS = [
    '.punch-filmstrip-thumbnail',
    '.punch-filmstrip-scroll [role="option"]',
    '[id^="filmstrip-slide"]'
  ];

  function isCurrentThumbnail(el) {
    return el.getAttribute('aria-selected') === 'true' ||
           Array.from(el.classList).some(name => name.includes('selected'));
  }

  function getSlideNumberFromFilmstrip() {
    for (const selector of FILMSTRIP_SELECTORS) {
      const thumbnails = Array.from(document.querySelectorAll(selector));
      if (thumbnails.length === 0) continue;
      const index = thumbnails.findIndex(isCurrentThumbnail);
      if (index >= 0) return index + 1;
    }
    return 0;
  }

  // Presenting: the navigation bar counts the deck off as "3 / 12".
  function getSlideNumberFromCounter() {
    const counter = document.querySelector(
      '[class*="slidecount"], [class*="slide-count"], [class*="page-number"]'
    );
    const match = counter && counter.textContent.match(/(\d+)\s*\/\s*\d+/);
    return match ? Number(match[1]) : 0;
  }

  function getSlideNumber() {
    return getSlideNumberFromFilmstrip() || getSlideNumberFromCounter();
  }

  // Build slide info object
  function buildSlideInfo() {
    const slideId = getSlideFromHash() || getSlideFromQuery();
    return {
      presentationId: getPresentationId(),
      slideId: slideId,
      slideNumber: getSlideNumber(),
      title: getPresentationTitle(),
      mode: detectMode(),
      timestamp: Date.now(),
      url: window.location.href
    };
  }

  // Get browser API (cross-browser compatibility)
  const browserAPI = typeof browser !== 'undefined' ? browser : chrome;

  // Send slide info via background script (avoids mixed content issues)
  async function sendSlideInfo(slideInfo) {
    try {
      const response = await browserAPI.runtime.sendMessage({
        type: 'SLIDE_CHANGE',
        data: slideInfo
      });

      if (response && response.success) {
        console.log('[CueCard] Successfully sent slide info');
        return true;
      }
      console.warn('[CueCard] Failed to send:', response?.error || 'Unknown error');
      return false;
    } catch (error) {
      console.error('[CueCard] Failed to send slide info:', error.message);
      return false;
    }
  }

  // Debounce utility
  function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
      const later = () => {
        clearTimeout(timeout);
        func(...args);
      };
      clearTimeout(timeout);
      timeout = setTimeout(later, wait);
    };
  }

  // Check if slide changed
  function hasSlideChanged(newInfo) {
    if (!currentSlideInfo) return true;
    return currentSlideInfo.slideId !== newInfo.slideId ||
           currentSlideInfo.slideNumber !== newInfo.slideNumber ||
           currentSlideInfo.mode !== newInfo.mode;
  }

  // Handle slide change
  const handleSlideChange = debounce(() => {
    const newSlideInfo = buildSlideInfo();

    if (hasSlideChanged(newSlideInfo)) {
      console.log('[CueCard] Slide changed');
      currentSlideInfo = newSlideInfo;
      sendSlideInfo(newSlideInfo);
    }
  }, CONFIG.DEBOUNCE_MS);

  // Clean up observers
  function cleanupObservers() {
    observers.forEach(observer => observer.disconnect());
    observers = [];
  }

  // Initialize edit mode detection
  function initEditModeDetection() {
    console.log('[CueCard] Initializing edit mode detection');

    // Listen for hash changes (slide navigation)
    window.addEventListener('hashchange', handleSlideChange);

    // Observe DOM for slide changes (keyboard navigation might not change hash immediately)
    const filmstrip = document.querySelector('.punch-filmstrip-scroll');
    if (filmstrip) {
      const observer = new MutationObserver(handleSlideChange);
      observer.observe(filmstrip, {
        attributes: true,
        attributeFilter: ['class', 'aria-selected'],
        subtree: true
      });
      observers.push(observer);
    }

    // Also observe the main slide area for changes
    const slideArea = document.querySelector('.punch-viewer-container') ||
                     document.querySelector('.punch-present-container');
    if (slideArea) {
      const observer = new MutationObserver(handleSlideChange);
      observer.observe(slideArea, {
        childList: true,
        subtree: true
      });
      observers.push(observer);
    }
  }

  // Initialize slideshow mode detection
  function initSlideshowDetection() {
    console.log('[CueCard] Initializing slideshow mode detection');

    // MutationObserver for slide transitions
    const slideContainer = document.querySelector('.punch-viewer-content') ||
                          document.querySelector('.punch-present-iframe') ||
                          document.querySelector('[class*="viewer-content"]') ||
                          document.body;

    if (slideContainer) {
      const observer = new MutationObserver(handleSlideChange);
      observer.observe(slideContainer, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['class', 'style', 'transform']
      });
      observers.push(observer);
    }

    // Listen for keyboard events (arrow keys, etc.)
    document.addEventListener('keydown', (e) => {
      if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown',
           'PageUp', 'PageDown', 'Space', 'Enter', 'Backspace'].includes(e.key)) {
        setTimeout(handleSlideChange, 10); // Small delay for DOM update
      }
    });

    // Listen for click navigation
    document.addEventListener('click', () => {
      setTimeout(handleSlideChange, 10);
    });

    // Listen for URL changes (some navigations change query params)
    let lastUrl = window.location.href;
    const urlObserver = setInterval(() => {
      if (window.location.href !== lastUrl) {
        lastUrl = window.location.href;
        handleSlideChange();
      }
    }, 500);

    // Store interval for cleanup
    observers.push({ disconnect: () => clearInterval(urlObserver) });
  }

  // Main initialization
  function init() {
    if (isInitialized) {
      cleanupObservers();
    }
    isInitialized = true;

    const mode = detectMode();
    console.log('[CueCard] Initializing in mode:', mode);

    // Send initial slide info
    currentSlideInfo = buildSlideInfo();
    sendSlideInfo(currentSlideInfo);

    // Set up mode-specific detection
    if (mode === 'edit' || mode === 'published') {
      initEditModeDetection();
    } else if (mode === 'slideshow') {
      initSlideshowDetection();
    } else {
      // Unknown mode - try both detection methods
      initEditModeDetection();
      initSlideshowDetection();
    }

    // Watch for mode changes (e.g., entering/exiting presentation mode)
    let lastMode = mode;
    let lastUrl = window.location.href;
    setInterval(() => {
      const currentMode = detectMode();
      const currentUrl = window.location.href;

      // Re-initialize if mode or significant URL change
      if (currentMode !== lastMode ||
          (currentUrl !== lastUrl && !currentUrl.includes('#'))) {
        console.log('[CueCard] Mode/URL change detected, reinitializing');
        lastMode = currentMode;
        lastUrl = currentUrl;
        init();
      }
    }, CONFIG.POLL_INTERVAL_MS);
  }

  // Wait for DOM to be ready
  function waitForSlides() {
    // Check if Google Slides has loaded
    const filmstrip = document.querySelector('.punch-filmstrip-scroll');
    const presentView = document.querySelector('.punch-viewer-content');

    if (filmstrip || presentView || document.querySelector('[class*="punch-"]')) {
      init();
    } else {
      // Google Slides not ready yet, wait and retry
      setTimeout(waitForSlides, 500);
    }
  }

  // Start initialization
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      setTimeout(waitForSlides, 1000);
    });
  } else {
    // DOM already loaded, wait for Google Slides to initialize
    setTimeout(waitForSlides, 1000);
  }

  console.log('[CueCard] Extension loaded');
})();
