// CueCard Extension - Content Script
// Detects slide changes in Google Slides and extracts speaker notes directly from the DOM
// This approach doesn't require any Google API scopes - notes are extracted from the page itself

(function() {
  'use strict';

  const CONFIG = {
    API_ENDPOINT: 'http://localhost:3642/slides',
    DEBOUNCE_MS: 50,
    RETRY_ATTEMPTS: 3,
    RETRY_DELAY_MS: 1000,
    POLL_INTERVAL_MS: 1000,
    NOTES_POLL_INTERVAL_MS: 500
  };

  // State management
  let currentSlideInfo = null;
  let isInitialized = false;
  let observers = [];
  let eventListeners = [];
  let intervals = [];
  let lastNotesContent = null;
  let modeWatcherId = null;

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
    const titleElement = document.querySelector('[data-name="title"]') ||
                        document.querySelector('.docs-title-input') ||
                        document.querySelector('input.docs-title-input-label-inner');
    if (titleElement) {
      return titleElement.textContent || titleElement.value || 'Untitled Presentation';
    }
    const docTitle = document.title.replace(' - Google Slides', '').replace(' - Google Präsentationen', '');
    return docTitle || 'Untitled Presentation';
  }

  // Helper to extract text from SVG elements without duplicates
  function extractTextFromSvgElements(container) {
    const textElements = container.querySelectorAll('text');
    if (textElements.length > 0) {
      let result = '';
      textElements.forEach(el => {
        const text = el.textContent || '';
        if (text.trim()) {
          result += text + '\n';
        }
      });
      if (result.trim()) {
        return result.trim();
      }
    }

    const tspanElements = container.querySelectorAll('tspan');
    if (tspanElements.length > 0) {
      let result = '';
      tspanElements.forEach(el => {
        if (el.querySelectorAll('tspan').length === 0) {
          const text = el.textContent || '';
          if (text.trim()) {
            result += text;
          }
        }
      });
      if (result.trim()) {
        return result.trim();
      }
    }

    return null;
  }

  // Extract speaker notes from DOM (edit mode)
  function extractSpeakerNotesFromEditMode() {
    const notesPanelSelectors = [
      '.punch-viewer-speakernotes-container',
      '.punch-viewer-speakernotes',
      '.punch-viewer-speakernotes-pageelement'
    ];

    for (const selector of notesPanelSelectors) {
      const panel = document.querySelector(selector);
      if (panel) {
        const text = extractTextFromSvgElements(panel);
        if (text) {
          console.log('[CueCard] Found notes in panel:', selector);
          return text;
        }
      }
    }

    const directTextSelectors = [
      '.punch-viewer-speakernotes-text',
      '.punch-viewer-speaker-notes-text',
      '.punch-viewer-speakernotes-pageelement .sketchy-text-content-text',
      '.punch-viewer-svgpage-speakernotes .sketchy-text-content-text'
    ];

    for (const selector of directTextSelectors) {
      const elements = document.querySelectorAll(selector);
      if (elements.length > 0) {
        let notesText = '';
        elements.forEach(el => {
          const text = el.innerText || el.textContent || '';
          if (text.trim()) {
            notesText += text + '\n';
          }
        });
        if (notesText.trim()) {
          console.log('[CueCard] Found notes using selector:', selector);
          return notesText.trim();
        }
      }
    }

    return null;
  }

  // Extract speaker notes from DOM (slideshow/presentation mode)
  function extractSpeakerNotesFromPresentationMode() {
    const presenterPanelSelectors = [
      '.punch-present-speaker-notes',
      '.punch-present-speakernotes',
      '.punch-present-container .punch-viewer-speakernotes-pageelement'
    ];

    for (const selector of presenterPanelSelectors) {
      const panel = document.querySelector(selector);
      if (panel) {
        const text = extractTextFromSvgElements(panel);
        if (text) {
          console.log('[CueCard] Found presenter notes in panel:', selector);
          return text;
        }
      }
    }

    const presenterTextSelectors = [
      '.punch-present-speaker-notes-text',
      '.punch-present-speakernotes-text',
      '.punch-viewer-speakernotes-text',
      '[data-slide-notes-text]'
    ];

    for (const selector of presenterTextSelectors) {
      const elements = document.querySelectorAll(selector);
      if (elements.length > 0) {
        let notesText = '';
        elements.forEach(el => {
          const text = el.innerText || el.textContent || '';
          if (text.trim()) {
            notesText += text + '\n';
          }
        });
        if (notesText.trim()) {
          console.log('[CueCard] Found presenter notes using selector:', selector);
          return notesText.trim();
        }
      }
    }

    return extractSpeakerNotesFromEditMode();
  }

  // Main function to extract speaker notes based on current mode
  function extractSpeakerNotes() {
    const mode = detectMode();

    let notes = null;
    if (mode === 'slideshow') {
      notes = extractSpeakerNotesFromPresentationMode();
    } else {
      notes = extractSpeakerNotesFromEditMode();
    }

    if (!notes) {
      const allContainers = document.querySelectorAll('[class*="speakernotes"], [class*="speaker-notes"]');
      for (const container of allContainers) {
        const svgText = extractTextFromSvgElements(container);
        if (svgText && !svgText.includes('Click to add speaker notes')) {
          console.log('[CueCard] Found notes using generic SVG search');
          notes = svgText;
          break;
        }

        const innerText = container.innerText || '';
        if (innerText.trim() && !innerText.includes('Click to add speaker notes')) {
          console.log('[CueCard] Found notes using generic innerText search');
          notes = innerText.trim();
          break;
        }
      }
    }

    return notes || '';
  }

  // Build slide info object with notes included
  function buildSlideInfo() {
    const slideId = getSlideFromHash() || getSlideFromQuery();
    const notes = extractSpeakerNotes();

    return {
      presentationId: getPresentationId(),
      slideId: slideId,
      slideNumber: 0,
      title: getPresentationTitle(),
      mode: detectMode(),
      timestamp: Date.now(),
      url: window.location.href,
      notes: notes
    };
  }

  // Get browser API (cross-browser compatibility)
  const browserAPI = typeof browser !== 'undefined' ? browser : chrome;

  // Send slide info via background script
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

  // Check if notes content has changed
  function hasNotesChanged(newNotes) {
    const changed = lastNotesContent !== newNotes;
    if (changed) {
      lastNotesContent = newNotes;
    }
    return changed;
  }

  // Handle slide change
  const handleSlideChange = debounce(() => {
    const newSlideInfo = buildSlideInfo();

    const slideChanged = hasSlideChanged(newSlideInfo);
    const notesChanged = hasNotesChanged(newSlideInfo.notes);

    if (slideChanged || notesChanged) {
      console.log('[CueCard] Update detected - slide changed:', slideChanged, 'notes changed:', notesChanged);
      currentSlideInfo = newSlideInfo;
      sendSlideInfo(newSlideInfo);
    }
  }, CONFIG.DEBOUNCE_MS);

  // Clean up observers, event listeners, and intervals
  function cleanup() {
    observers.forEach(observer => {
      if (observer && typeof observer.disconnect === 'function') {
        observer.disconnect();
      }
    });
    observers = [];

    eventListeners.forEach(({ target, type, handler }) => {
      target.removeEventListener(type, handler);
    });
    eventListeners = [];

    intervals.forEach(id => clearInterval(id));
    intervals = [];
  }

  // Helper to add tracked event listener
  function addTrackedEventListener(target, type, handler) {
    target.addEventListener(type, handler);
    eventListeners.push({ target, type, handler });
  }

  // Initialize edit mode detection
  function initEditModeDetection() {
    console.log('[CueCard] Initializing edit mode detection');

    addTrackedEventListener(window, 'hashchange', handleSlideChange);

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

    const keyHandler = (e) => {
      if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown',
           'PageUp', 'PageDown', 'Space', 'Enter', 'Backspace'].includes(e.key)) {
        setTimeout(handleSlideChange, 100);
      }
    };
    addTrackedEventListener(document, 'keydown', keyHandler);

    const clickHandler = () => {
      setTimeout(handleSlideChange, 100);
    };
    addTrackedEventListener(document, 'click', clickHandler);

    let lastUrl = window.location.href;
    const urlObserverId = setInterval(() => {
      if (window.location.href !== lastUrl) {
        lastUrl = window.location.href;
        handleSlideChange();
      }
    }, 500);
    intervals.push(urlObserverId);
  }

  // Initialize notes panel observer
  function initNotesObserver() {
    const notesContainerSelectors = [
      '.punch-viewer-speakernotes-container',
      '.punch-viewer-speakernotes',
      '.punch-present-speaker-notes',
      '[class*="speakernotes"]',
      '[class*="speaker-notes"]'
    ];

    for (const selector of notesContainerSelectors) {
      const container = document.querySelector(selector);
      if (container) {
        const observer = new MutationObserver(() => {
          setTimeout(handleSlideChange, 100);
        });
        observer.observe(container, {
          childList: true,
          subtree: true,
          characterData: true
        });
        observers.push(observer);
        console.log('[CueCard] Notes observer attached to:', selector);
      }
    }
  }

  // Poll for notes that may load after initial render
  function startNotesPolling() {
    let pollCount = 0;
    const maxPolls = 20;

    const pollIntervalId = setInterval(() => {
      pollCount++;

      const notes = extractSpeakerNotes();
      if (notes && hasNotesChanged(notes)) {
        console.log('[CueCard] Notes detected via polling');
        const slideInfo = buildSlideInfo();
        currentSlideInfo = slideInfo;
        sendSlideInfo(slideInfo);
      }

      if (pollCount >= maxPolls) {
        clearInterval(pollIntervalId);
        const idx = intervals.indexOf(pollIntervalId);
        if (idx > -1) intervals.splice(idx, 1);
        console.log('[CueCard] Stopped initial notes polling');
      }
    }, CONFIG.NOTES_POLL_INTERVAL_MS);

    intervals.push(pollIntervalId);
  }

  // Main initialization
  function init() {
    if (isInitialized) {
      cleanup();
    }
    isInitialized = true;

    const mode = detectMode();
    console.log('[CueCard] Initializing in mode:', mode);

    lastNotesContent = null;

    currentSlideInfo = buildSlideInfo();
    sendSlideInfo(currentSlideInfo);

    if (mode === 'edit' || mode === 'published') {
      initEditModeDetection();
    } else if (mode === 'slideshow') {
      initSlideshowDetection();
    } else {
      initEditModeDetection();
      initSlideshowDetection();
    }

    initNotesObserver();
    startNotesPolling();

    if (!modeWatcherId) {
      let lastMode = mode;
      let lastUrl = window.location.href;
      modeWatcherId = setInterval(() => {
        const currentMode = detectMode();
        const currentUrl = window.location.href;

        if (currentMode !== lastMode ||
            (currentUrl !== lastUrl && !currentUrl.includes('#'))) {
          console.log('[CueCard] Mode/URL change detected, reinitializing');
          lastMode = currentMode;
          lastUrl = currentUrl;
          init();
        }
      }, CONFIG.POLL_INTERVAL_MS);
    }
  }

  // Wait for DOM to be ready
  function waitForSlides() {
    const filmstrip = document.querySelector('.punch-filmstrip-scroll');
    const presentView = document.querySelector('.punch-viewer-content');

    if (filmstrip || presentView || document.querySelector('[class*="punch-"]')) {
      init();
    } else {
      setTimeout(waitForSlides, 500);
    }
  }

  // Start initialization
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      setTimeout(waitForSlides, 1000);
    });
  } else {
    setTimeout(waitForSlides, 1000);
  }

  console.log('[CueCard] Extension loaded');
})();
