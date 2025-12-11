// Google Slides Tracker - Content Script
// Detects slide changes in both edit and slideshow modes

(function() {
  'use strict';

  const CONFIG = {
    API_ENDPOINT: 'http://localhost:3000/slides',
    DEBOUNCE_MS: 300,
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

  // Calculate slide number from slide ID (best effort)
  function getSlideNumber() {
    const mode = detectMode();

    if (mode === 'edit' || mode === 'published') {
      // In edit mode, try to find the slide thumbnail with active class
      const filmstrip = document.querySelector('.punch-filmstrip-scroll');
      if (filmstrip) {
        const slides = filmstrip.querySelectorAll('.punch-filmstrip-thumbnail');
        const activeSlide = filmstrip.querySelector('.punch-filmstrip-thumbnail[aria-selected="true"]') ||
                          filmstrip.querySelector('.punch-filmstrip-thumbnail-selected');
        if (activeSlide) {
          return Array.from(slides).indexOf(activeSlide) + 1;
        }
      }

      // Alternative: check for slide number in thumbnail label
      const selectedThumb = document.querySelector('.punch-filmstrip-thumbnail[aria-selected="true"]');
      if (selectedThumb) {
        const label = selectedThumb.getAttribute('aria-label');
        if (label) {
          const match = label.match(/(\d+)/);
          if (match) return parseInt(match[1], 10);
        }
      }
    } else if (mode === 'slideshow') {
      // In slideshow, check for slide indicator
      const indicator = document.querySelector('.punch-viewer-nav-label') ||
                       document.querySelector('[class*="nav-label"]');
      if (indicator) {
        const match = indicator.textContent.match(/(\d+)/);
        return match ? parseInt(match[1], 10) : 1;
      }

      // Alternative: check URL for slide parameter
      const slideId = getSlideFromQuery();
      if (slideId) {
        // Extract number from slide ID if it's in format like "p3" or "g123"
        const numMatch = slideId.match(/\d+/);
        if (numMatch) return parseInt(numMatch[0], 10);
      }
    }

    return 1; // Default to slide 1
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
        console.log('[SlidesTracker] Successfully sent slide info:', slideInfo);
        return true;
      }
      console.warn('[SlidesTracker] Failed to send:', response?.error || 'Unknown error');
      return false;
    } catch (error) {
      console.error('[SlidesTracker] Failed to send slide info:', error.message);
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
      console.log('[SlidesTracker] Slide changed:', newSlideInfo);
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
    console.log('[SlidesTracker] Initializing edit mode detection');

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
    console.log('[SlidesTracker] Initializing slideshow mode detection');

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
        setTimeout(handleSlideChange, 100); // Small delay for DOM update
      }
    });

    // Listen for click navigation
    document.addEventListener('click', () => {
      setTimeout(handleSlideChange, 100);
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
    console.log('[SlidesTracker] Initializing in mode:', mode);

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
        console.log('[SlidesTracker] Mode/URL change detected, reinitializing');
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

  console.log('[SlidesTracker] Content script loaded');
})();
