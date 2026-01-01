/**
 * CueCard - Main Frontend Application
 *
 * This file contains the main frontend logic for the CueCard application:
 * - Analytics tracking for usage insights
 * - Firestore integration for user profiles
 * - Persistent storage management
 * - Google OAuth authentication UI
 * - Notes display and syntax highlighting
 * - Timer functionality for presentations
 * - Settings management (opacity, screenshot protection)
 */

// =============================================================================
// TAURI API INITIALIZATION
// =============================================================================

// Check if Tauri is available
if (!window.__TAURI__) {
  console.error("Tauri runtime not available! Make sure you're running the app with 'npm run tauri dev' or as a built Tauri app.");
}

const { invoke } = window.__TAURI__?.core || {};
const { listen } = window.__TAURI__?.event || {};
const { openUrl } = window.__TAURI__?.opener || {};
const { getCurrentWindow } = window.__TAURI__?.window || {};
const { check } = window.__TAURI__?.updater || {};
const { relaunch } = window.__TAURI__?.process || {};

// =============================================================================
// ANALYTICS (BACKEND)
// =============================================================================

async function initAnalytics() {
  if (!invoke) return;
  try {
    const { platform, operatingSystem } = getPlatformInfo();
    await invoke('init_analytics', {
      platform,
      operatingSystem,
    });
  } catch (error) {
    console.debug('Analytics init error:', error);
  }
}

async function sendAnalyticsEvent(eventName, params) {
  if (!invoke) return;
  try {
    const payload = { eventName };
    if (params && Object.keys(params).length > 0) {
      payload.params = params;
    }
    await invoke('send_event', payload);
  } catch (error) {
    console.debug('Analytics error:', error);
  }
}

async function setAnalyticsUserId(email) {
  if (!invoke || !email) return;
  try {
    await invoke('set_analytics_user_id', { email });
    console.log('Analytics: User ID set');
  } catch (error) {
    console.debug('Analytics setUserId error:', error);
  }
}

async function clearAnalyticsUserId() {
  if (!invoke) return;
  try {
    await invoke('clear_analytics_user_id');
  } catch (error) {
    console.debug('Analytics clearUserId error:', error);
  }
}

function trackAppOpen() {
  void sendAnalyticsEvent('app_open');
}

function trackSessionStart() {
  void sendAnalyticsEvent('start_session');
}

function trackLogin(method = 'google') {
  void sendAnalyticsEvent('login', { method });
}

function trackLogout() {
  void sendAnalyticsEvent('logout');
  void clearAnalyticsUserId();
}

function trackScreenView(screenName, pageTitle = null) {
  void sendAnalyticsEvent('screen_view', {
    screen_name: screenName,
    page_title: pageTitle || screenName,
    screen_class: 'CueCard'
  });
}

async function trackFirstOpen() {
  if (!invoke) return;
  try {
    const isFirstOpen = await invoke('check_and_mark_first_open');
    if (isFirstOpen) {
      // Using 'app_first_launch' instead of 'first_open' as first_open is a restricted GA4 event
      await sendAnalyticsEvent('app_first_launch');
      console.log('Analytics: First launch tracked');
    }
  } catch (error) {
    console.debug('Analytics first_launch error:', error);
  }
}

function trackNotesPaste() {
  void sendAnalyticsEvent('notes_paste');
}

function trackSlidesSync() {
  void sendAnalyticsEvent('slides_sync');
}

function trackTimerAction(action) {
  void sendAnalyticsEvent('timer_action', { action });
}

function trackSettingChange(setting, value) {
  void sendAnalyticsEvent('setting_change', {
    setting_name: setting,
    setting_value: String(value)
  });
}

function trackSlideUpdate() {
  void sendAnalyticsEvent('slide_update');
}

function trackEditAction(action) {
  void sendAnalyticsEvent('edit_action', { action });
}

// =============================================================================
// PLATFORM-SPECIFIC STYLES
// =============================================================================

function getPlatformInfo() {
  const platformSource = (navigator.userAgentData && navigator.userAgentData.platform)
    || navigator.platform
    || navigator.userAgent
    || '';

  if (/win/i.test(platformSource)) {
    return { platform: 'windows', operatingSystem: 'windows' };
  }
  if (/mac/i.test(platformSource)) {
    return { platform: 'macos', operatingSystem: 'mac' };
  }
  if (/linux/i.test(platformSource)) {
    return { platform: 'linux', operatingSystem: 'linux' };
  }
  return { platform: 'unknown', operatingSystem: 'unknown' };
}

function setPlatformClass() {
  const root = document.documentElement;
  const { platform } = getPlatformInfo();

  if (platform === 'windows') {
    root.classList.add('platform-windows');
  } else if (platform === 'macos') {
    root.classList.add('platform-mac');
  }
}

setPlatformClass();

// =============================================================================
// FIRESTORE INTEGRATION
// =============================================================================

// Firestore REST API Configuration
let FIRESTORE_PROJECT_ID = null;
let FIRESTORE_BASE_URL = null;

// Initialize Firestore configuration
async function initFirestoreConfig() {
  if (!invoke) {
    console.error("Tauri invoke API not available");
    return;
  }
  try {
    FIRESTORE_PROJECT_ID = await invoke("get_firestore_project_id");
    FIRESTORE_BASE_URL = `https://firestore.googleapis.com/v1/projects/${FIRESTORE_PROJECT_ID}/databases/(default)/documents`;
    console.log("Firestore configuration initialized");
  } catch (error) {
    console.error("Error getting Firestore project ID:", error);
  }
}

// Get Firebase ID token for authenticated Firestore requests
async function getFirebaseIdToken() {
  if (!invoke) return null;
  try {
    return await invoke("get_firebase_id_token");
  } catch (error) {
    console.log("Could not get Firebase ID token:", error);
    return null;
  }
}

// Get or create user profile in Firestore
async function saveUserProfile(email, name) {
  if (!email || !FIRESTORE_BASE_URL) return;

  // Get Firebase ID token for authenticated request
  const token = await getFirebaseIdToken();
  if (!token) {
    console.log("No Firebase token available, skipping Firestore save");
    return;
  }

  const documentPath = `Profiles/${encodeURIComponent(email)}`;
  const url = `${FIRESTORE_BASE_URL}/${documentPath}`;

  try {
    // First, try to get the existing document
    const getResponse = await fetch(url, {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    });

    if (getResponse.ok) {
      // Document exists, just update name and email (don't touch creationDate)
      const updateUrl = `${url}?updateMask.fieldPaths=name&updateMask.fieldPaths=email`;

      await fetch(updateUrl, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({
          fields: {
            name: { stringValue: name },
            email: { stringValue: email }
          }
        })
      });
      console.log("User profile updated in Firestore");
    } else if (getResponse.status === 404) {
      // Document doesn't exist, create new one with all fields
      const now = new Date().toISOString();

      await fetch(url, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({
          fields: {
            name: { stringValue: name },
            email: { stringValue: email },
            creationDate: { timestampValue: now },
            usage: {
              mapValue: {
                fields: {
                  paste: { integerValue: '0' },
                  slide: { integerValue: '0' }
                }
              }
            }
          }
        })
      });
      console.log("New user profile created in Firestore");
    }
  } catch (error) {
    console.error("Error saving user profile to Firestore:", error);
  }
}


// =============================================================================
// PERSISTENT STORAGE
// =============================================================================

// Store for persistent storage
let appStore = null;

// Storage keys
const STORAGE_KEYS = {
  SETTINGS_OPACITY: 'settings_opacity',
  SETTINGS_GHOST_MODE: 'settings_ghost_mode',
  SETTINGS_THEME: 'settings_theme',
  SETTINGS_SCROLL_SPEED: 'settings_scroll_speed',
  ADD_NOTES_CONTENT: 'add_notes_content'
};

// Scroll speed presets: index -> { label, wpm }
const SCROLL_SPEED_PRESETS = [
  { label: 'Off', wpm: 0 },
  { label: 'Slow', wpm: 100 },
  { label: 'Medium', wpm: 150 },
  { label: 'Fast', wpm: 200 },
  { label: 'Extreme', wpm: 300 }
];

// Initialize the store
async function initStore() {
  try {
    // Import store dynamically for Tauri 2
    const Store = window.__TAURI__?.store?.Store;
    if (Store) {
      appStore = await Store.load('cuecard-store.json');
      console.log("Store initialized successfully");
    } else {
      console.warn("Store plugin not available");
    }
  } catch (error) {
    console.error("Error initializing store:", error);
  }
}

// Get value from store
async function getStoredValue(key) {
  if (!appStore) return null;
  try {
    return await appStore.get(key);
  } catch (error) {
    console.error(`Error getting stored value for ${key}:`, error);
    return null;
  }
}

// Set value in store
async function setStoredValue(key, value) {
  if (!appStore) return;
  try {
    await appStore.set(key, value);
    await appStore.save();
  } catch (error) {
    console.error(`Error setting stored value for ${key}:`, error);
  }
}

// Load stored notes into the add-notes textarea
async function loadStoredNotes() {
  const storedNotes = await getStoredValue(STORAGE_KEYS.ADD_NOTES_CONTENT);
  if (storedNotes && notesInput) {
    notesInput.value = storedNotes;
    // Trigger the highlight update
    if (notesInputHighlight) {
      const event = new Event('input', { bubbles: true });
      notesInput.dispatchEvent(event);
    }
    console.log("Loaded stored notes");
  }
}

// Save notes from add-notes textarea to storage
async function saveNotesToStorage() {
  if (notesInput) {
    const notes = notesInput.value;
    await setStoredValue(STORAGE_KEYS.ADD_NOTES_CONTENT, notes);
    console.log("Saved notes to storage");
  }
}

// Check if a specific scope is granted (backend handles scope tracking)
async function hasScope(scopeType) {
  if (!invoke) return false;
  try {
    if (scopeType === 'slides') {
      return await invoke("has_slides_scope");
    }
    // Profile scope is implied by being authenticated
    return await invoke("get_auth_status");
  } catch (error) {
    console.error("Error checking scope:", error);
    return false;
  }
}

// =============================================================================
// DOM ELEMENTS AND STATE
// =============================================================================

// DOM Elements
let btnClose, btnDownloadUpdates, downloadUpdatesSeparator;
let authBtn;
let appContainer, appHeader, appHeaderTitle, viewInitial, viewAddNotes, viewNotes, viewSettings, viewShortcuts;
let linkGoBack;
let notesInput, notesContent;
let welcomeHeading, welcomeSubtext;
let bugLink, websiteLink, supportLink;
let settingsLink;
let shortcutsLink;
let refreshBtn;
let notesInputHighlight;
let btnStart, btnPause, btnReset;
let opacitySlider, opacityValue, ghostModeToggle;
let scrollSpeedSlider, scrollSpeedValue;
let themeSystemBtn, themeLightBtn, themeDarkBtn;
let editNoteBtn;
let notesInputWrapper;
let ghostModeIndicator;
let headerTimer;

// State
let isAuthenticated = false;
let userName = '';
let currentView = 'initial'; // 'initial', 'add-notes', 'notes', 'settings'
let previousView = null; // 'initial', 'add-notes', 'notes', 'settings'
let manualNotes = ''; // Notes pasted by the user
let currentSlideData = null; // Store current slide data
let currentOpacity = 100; // Store current opacity value (10-100)
let ghostMode = true; // Default: true = hidden from screenshots (ghost mode ON)
let currentTheme = 'system'; // 'system', 'light', 'dark'
let scrollSpeedIndex = 0; // Default: 0 = Off (see SCROLL_SPEED_PRESETS)

// Timer State
let timerState = 'stopped'; // 'stopped', 'running', 'paused'
let timerIntervals = []; // Store all timer interval IDs
let totalTimeSeconds = 0; // Total time from all [time] tags
let remainingTimeSeconds = 0; // Current remaining time for countdown

// Auto-scroll State
let autoScrollRafId = null;
let autoScrollLastTimestamp = null;
let isSyncingAddNotesScroll = false;

// Hover pause state
let isHoveringApp = false;
let autoScrollPausedByHover = false;
let autoScrollPausedBySettings = false;

// Scroll position tracking for reset on hover leave
let savedScrollPosition = null;
let userScrolledDuringHover = false;

// Notes metadata
let notesHasTimeTags = false;

// Edit Mode State
let isEditMode = false; // false = done mode (readonly, highlighted), true = edit mode (editable, not highlighted)

// Analytics State
let sessionTracked = false; // Prevent duplicate session tracking

// =============================================================================
// APPLICATION INITIALIZATION
// =============================================================================

// Initialize the app
window.addEventListener("DOMContentLoaded", async () => {
  console.log("App initializing...");

  // Initialize analytics
  await initAnalytics();

  // Initialize Firestore configuration from environment variables
  await initFirestoreConfig();

  // Initialize the store for persistent storage
  await initStore();

  // Get DOM elements
  btnClose = document.getElementById("btn-close");
  btnDownloadUpdates = document.getElementById("btn-download-updates");
  downloadUpdatesSeparator = document.getElementById("download-updates-separator");
  authBtn = document.getElementById("auth-btn");
  appContainer = document.querySelector(".app-container");
  appHeader = document.querySelector(".app-header");
  appHeaderTitle = document.getElementById("app-header-title");
  viewInitial = document.getElementById("view-initial");
  viewAddNotes = document.getElementById("view-add-notes");
  viewNotes = document.getElementById("view-notes");
  viewSettings = document.getElementById("view-settings");
  viewShortcuts = document.getElementById("view-shortcuts");
  linkGoBack = document.getElementById("link-go-back");
  notesInput = document.getElementById("notes-input");
  notesContent = document.getElementById("notes-content");
  welcomeHeading = document.getElementById("welcome-heading");
  welcomeSubtext = document.getElementById("welcome-subtext");
  bugLink = document.getElementById("bug-link");
  websiteLink = document.getElementById("website-link");
  supportLink = document.getElementById("support-link");
  settingsLink = document.getElementById("settings-link");
  shortcutsLink = document.getElementById("shortcuts-link");
  refreshBtn = document.getElementById("refresh-btn");
  notesInputHighlight = document.getElementById("notes-input-highlight");
  btnStart = document.getElementById("btn-start");
  btnPause = document.getElementById("btn-pause");
  btnReset = document.getElementById("btn-reset");
  opacitySlider = document.getElementById("opacity-slider");
  opacityValue = document.getElementById("opacity-value");
  ghostModeToggle = document.getElementById("ghost-mode-toggle");
  scrollSpeedSlider = document.getElementById("scroll-speed-slider");
  scrollSpeedValue = document.getElementById("scroll-speed-value");
  themeSystemBtn = document.getElementById("theme-system");
  themeLightBtn = document.getElementById("theme-light");
  themeDarkBtn = document.getElementById("theme-dark");
  editNoteBtn = document.getElementById("edit-note-btn");
  notesInputWrapper = document.querySelector(".notes-input-wrapper");
  ghostModeIndicator = document.getElementById("ghost-mode-indicator");
  headerTimer = document.getElementById("header-timer");

  // Set up navigation handlers
  setupNavigation();

  // Set up auth handlers
  setupAuth();

  // Set up header handlers
  setupHeader();

  // Set up footer handlers
  setupFooter();

  // Set up update checker
  setupUpdateChecker();

  // Set up refresh button handler
  setupRefreshButton();

  // Set up timer control buttons
  setupTimerControls();

  // Set up hover pause functionality
  setupHoverPause();

  // Set up syntax highlighting for notes input
  setupNotesInputHighlighting();

  // Set up notes scroll sync
  setupNotesScrollSync();

  // Set up edit note button
  setupEditNoteButton();

  // Set up settings handlers
  setupSettings();

  // Set up global shortcut listener
  await setupShortcutListener();

  // Load stored settings
  await loadStoredSettings();

  // Check auth status on load
  await checkAuthStatus();

  // Track first_open for new users (must be before app_open)
  await trackFirstOpen();

  // Track app open event (after auth check so we have user info if available)
  trackAppOpen();

  // Track initial screen view
  trackScreenView('initial', 'CueCard Home');

  // Check for existing slide data
  await checkCurrentSlide();

  // Listen for slide updates from the backend
  if (listen) {
    await listen("slide-update", (event) => {
      handleSlideUpdate(event.payload);
    });
  }

  // Listen for auth status changes
  if (listen) {
    await listen("auth-status", async (event) => {
      // Auth status changed
      console.log("Auth status event:", event.payload);

      // Save user profile to Firestore when authenticated
      if (event.payload.authenticated && event.payload.user_email) {
        saveUserProfile(event.payload.user_email, event.payload.user_name || '');
        // Set analytics user ID and track login (new login from OAuth)
        setAnalyticsUserId(event.payload.user_email);
        trackLogin('google');
        // Only track session if not already tracked (prevents duplicate counting)
        if (!sessionTracked) {
          trackSessionStart();
          sessionTracked = true;
        }
      }

      // Update auth UI (only for profile auth, not slides)
      if (event.payload.requested_scope === 'profile' || !event.payload.slides_authorized) {
        updateAuthUI(event.payload.authenticated, event.payload.user_name);
      }

      // If slides scope was just granted, show the notes view
      if (event.payload.slides_authorized) {
        // Show notes view with slide data or default message
        if (currentSlideData) {
          showView('notes');
        } else {
          displayNotes('Open a Google Slides presentation to see notes here.\n[note Install CueCard Extension to sync notes]');
          window.title = 'No Slide Open';
          showView('notes');
        }
      }
    });
  }

  console.log("App initialization complete!");
});

// =============================================================================
// NAVIGATION
// =============================================================================

// Navigation Handlers
function setupNavigation() {
  linkGoBack.addEventListener("click", async (e) => {
    e.preventDefault();

    if (currentView === 'settings') {
      showView(previousView);
      return;
    }

    showView('initial');

    // Reset all states
    resetAllStates();
  });
}

// Reset all states and internal storages
function resetAllStates() {
  // Clear the input and highlight
  notesInput.value = '';
  if (notesInputHighlight) {
    notesInputHighlight.innerHTML = '';
  }

  // Clear notes content
  notesContent.innerHTML = '';
  notesHasTimeTags = false;
  updateHeaderTimerVisibility();

  // Clear slide info
  window.title = '';

  // Reset slide data
  currentSlideData = null;
  manualNotes = '';

  // Stop and reset all timers
  stopAllTimers();
  timerState = 'stopped';

  // Stop auto-scroll
  stopAutoScroll();

  // Update timer button visibility
  updateTimerButtonVisibility();
}

// =============================================================================
// AUTHENTICATION
// =============================================================================

// Auth Handlers
function setupAuth() {
  authBtn.addEventListener("click", async (e) => {
    e.stopPropagation(); // Prevent event from bubbling to viewInitial
    if (isAuthenticated) {
      trackLogout();
      await handleLogout();
    } else {
      await handleLogin();
    }
  });
}

// Refresh Button Handler
function setupRefreshButton() {
  if (!refreshBtn) return;

  refreshBtn.addEventListener("click", async (e) => {
    e.preventDefault();
    e.stopPropagation();

    if (!invoke) {
      console.error("Tauri invoke API not available");
      return;
    }

    // Store original text
    const originalText = refreshBtn.textContent;
    refreshBtn.textContent = 'Refreshing...';
    refreshBtn.disabled = true;

    try {
      console.log("Refreshing notes...");
      await invoke("refresh_notes");
      console.log("Notes refreshed successfully");

      // Reset timer and show start button
      resetTimerCountdown();
    } catch (error) {
      console.error("Error refreshing notes:", error);
    } finally {
      // Restore original text
      refreshBtn.textContent = originalText;
      refreshBtn.disabled = false;
    }
  });
}

// =============================================================================
// TIMER FUNCTIONALITY
// =============================================================================

// Timer Control Buttons Setup
function setupTimerControls() {
  if (!btnStart || !btnPause || !btnReset) return;

  btnStart.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    startTimerCountdown();
  });

  btnPause.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    pauseTimerCountdown();
  });

  btnReset.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    resetTimerCountdown();
  });
}

// Start/Resume timer countdown
function startTimerCountdown() {
  console.log('[Timer] startTimerCountdown called, timerState:', timerState);
  if (timerState === 'running') return;

  trackTimerAction('start');
  timerState = 'running';
  updateTimerButtonVisibility();

  // Start auto-scroll
  console.log('[Timer] Starting auto-scroll...');
  autoScrollPausedByHover = false;
  userScrolledDuringHover = false;
  savedScrollPosition = null;
  startAutoScroll();

  // Track elapsed time for count-up mode (when no [time] tags)
  let elapsedSeconds = 0;

  // Update the single header timer every second
  const interval = setInterval(() => {
    if (timerState !== 'running') {
      clearInterval(interval);
      return;
    }

    if (totalTimeSeconds > 0) {
      // Count down mode (has [time] tags)
      remainingTimeSeconds--;

      const minutes = Math.floor(Math.abs(remainingTimeSeconds) / 60);
      const seconds = Math.abs(remainingTimeSeconds) % 60;
      const displayTime = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;

      // Update the header timer display
      if (remainingTimeSeconds < 0) {
        headerTimer.textContent = `-${displayTime}`;
        headerTimer.classList.add('time-overtime');
        headerTimer.classList.remove('time-warning');
      } else if (remainingTimeSeconds < 10) {
        headerTimer.textContent = displayTime;
        headerTimer.classList.add('time-warning');
        headerTimer.classList.remove('time-overtime');
      } else {
        headerTimer.textContent = displayTime;
        headerTimer.classList.remove('time-warning', 'time-overtime');
      }
    } else {
      // Count up mode (no [time] tags)
      elapsedSeconds++;
      const minutes = Math.floor(elapsedSeconds / 60);
      const seconds = elapsedSeconds % 60;
      const displayTime = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
      headerTimer.textContent = displayTime;
      headerTimer.classList.remove('time-warning', 'time-overtime');
    }
  }, 1000);

  timerIntervals.push(interval);
}

// Pause timer countdown
function pauseTimerCountdown() {
  if (timerState !== 'running') return;

  trackTimerAction('pause');
  timerState = 'paused';
  stopAllTimers();
  updateTimerButtonVisibility();

  // Pause auto-scroll
  stopAutoScroll();
  autoScrollPausedByHover = false;
}

// Reset timer countdown to original values
function resetTimerCountdown() {
  trackTimerAction('reset');
  stopAllTimers();
  timerState = 'stopped';

  // Reset auto-scroll
  stopAutoScroll();
  autoScrollPausedByHover = false;
  userScrolledDuringHover = false;
  savedScrollPosition = null;

  // Reset scroll position to top
  const container = getAutoScrollContainer();
  if (container) {
    container.scrollTop = 0;
    if (currentView === 'add-notes') {
      syncAddNotesScroll(container);
    }
  }

  // Reset remaining time to total time
  remainingTimeSeconds = totalTimeSeconds;

  // Update header timer display
  if (headerTimer) {
    const minutes = Math.floor(totalTimeSeconds / 60);
    const seconds = totalTimeSeconds % 60;
    const displayTime = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
    headerTimer.textContent = displayTime;
    headerTimer.classList.remove('time-warning', 'time-overtime');
  }

  updateTimerButtonVisibility();
}

// Stop all running timer intervals
function stopAllTimers() {
  timerIntervals.forEach(interval => clearInterval(interval));
  timerIntervals = [];
}

// =============================================================================
// AUTO-SCROLL (TELEPROMPTER)
// =============================================================================

function getAutoScrollContainer() {
  if (currentView === 'add-notes') {
    if (isEditMode) {
      return notesInput;
    }
    return notesInputHighlight || notesInput;
  }
  if (currentView === 'notes') {
    return notesContent;
  }
  return null;
}

function syncAddNotesScroll(source) {
  if (!notesInput || !notesInputHighlight) return;
  if (isSyncingAddNotesScroll) return;
  isSyncingAddNotesScroll = true;
  if (source === notesInput) {
    notesInputHighlight.scrollTop = notesInput.scrollTop;
  } else {
    notesInput.scrollTop = notesInputHighlight.scrollTop;
  }
  isSyncingAddNotesScroll = false;
}

// Get current WPM from scroll speed preset
function getCurrentWPM() {
  return SCROLL_SPEED_PRESETS[scrollSpeedIndex]?.wpm || 0;
}

// Check if auto-scroll is enabled (not "Off")
function isAutoScrollEnabled() {
  return scrollSpeedIndex > 0;
}

// Start auto-scroll for the current view
function startAutoScroll() {
  stopAutoScroll();

  console.log('[AutoScroll] startAutoScroll called');
  console.log('[AutoScroll] isAutoScrollEnabled:', isAutoScrollEnabled(), 'scrollSpeedIndex:', scrollSpeedIndex);

  if (!isAutoScrollEnabled()) {
    console.log('[AutoScroll] RETURN: auto-scroll not enabled');
    return;
  }

  const wordsPerMinute = getCurrentWPM();
  console.log('[AutoScroll] WPM:', wordsPerMinute);
  if (wordsPerMinute === 0) {
    console.log('[AutoScroll] RETURN: WPM is 0');
    return;
  }

  // Get the scrollable container for the current view
  const container = getAutoScrollContainer();
  console.log('[AutoScroll] container:', container, 'currentView:', currentView, 'isEditMode:', isEditMode);
  if (!container) {
    console.log('[AutoScroll] RETURN: no container');
    return;
  }

  // Wait for next frame to ensure layout is ready
  requestAnimationFrame(() => {
    console.log('[AutoScroll] RAF - scrollHeight:', container.scrollHeight, 'clientHeight:', container.clientHeight);
    // Check if container is scrollable
    if (container.scrollHeight <= container.clientHeight) {
      console.log('[AutoScroll] RETURN: container not scrollable');
      return;
    }

    console.log('[AutoScroll] Starting animation loop');
    autoScrollLastTimestamp = null;

    // Simple smooth scroll speed based on reading speed (WPM)
    const wordsPerLine = 8;
    const computedStyles = getComputedStyle(container);
    const fontSize = parseFloat(computedStyles.fontSize) || 20;
    const lineHeightValue = computedStyles.lineHeight;
    let lineHeight = parseFloat(lineHeightValue);
    if (!lineHeightValue || lineHeightValue === 'normal') {
      lineHeight = fontSize * 1.2;
    } else if (!lineHeightValue.endsWith('px')) {
      lineHeight = lineHeight * fontSize;
    }
    const pixelsPerWord = lineHeight / wordsPerLine;
    const pixelsPerSecond = (wordsPerMinute / 60) * pixelsPerWord;

    const step = (timestamp) => {
      if (!autoScrollRafId) return;

      // Re-check container in case view changed
      const currentContainer = getAutoScrollContainer();
      if (!currentContainer || currentContainer !== container) {
        stopAutoScroll();
        return;
      }

      if (!autoScrollLastTimestamp) {
        autoScrollLastTimestamp = timestamp;
        autoScrollRafId = requestAnimationFrame(step);
        return;
      }

      const deltaMs = timestamp - autoScrollLastTimestamp;
      autoScrollLastTimestamp = timestamp;
      const scrollDelta = (pixelsPerSecond * deltaMs) / 1000;
      const nextScrollTop = container.scrollTop + scrollDelta;

      if (nextScrollTop + container.clientHeight >= container.scrollHeight) {
        container.scrollTop = container.scrollHeight - container.clientHeight;
        stopAutoScroll();
        return;
      }

      container.scrollTop = nextScrollTop;
      if (currentView === 'add-notes') {
        syncAddNotesScroll(container);
      }
      autoScrollRafId = requestAnimationFrame(step);
    };

    autoScrollRafId = requestAnimationFrame(step);
  });
}

// Stop auto-scroll
function stopAutoScroll() {
  if (autoScrollRafId) {
    cancelAnimationFrame(autoScrollRafId);
    autoScrollRafId = null;
  }
  autoScrollLastTimestamp = null;
}

// Restart auto-scroll with current settings
function restartAutoScroll() {
  stopAutoScroll();
  if (isAutoScrollEnabled() && timerState === 'running' && !isHoveringApp) {
    startAutoScroll();
  }
}

// =============================================================================
// HOVER PAUSE FUNCTIONALITY
// =============================================================================

// Pause auto-scroll on hover (but not timers)
function pauseOnHover() {
  isHoveringApp = true;

  // Pause auto-scroll if running and save position
  if (autoScrollRafId) {
    autoScrollPausedByHover = true;
    const container = getAutoScrollContainer();
    if (container) {
      savedScrollPosition = container.scrollTop;
    }
    stopAutoScroll();
    userScrolledDuringHover = false;
  }
}

// Resume auto-scroll on mouse leave
function resumeOnLeave() {
  isHoveringApp = false;

  // Resume auto-scroll if it was paused by hover and timer is still running
  if (autoScrollPausedByHover && timerState === 'running' && isAutoScrollEnabled()) {
    autoScrollPausedByHover = false;

    // If user scrolled manually during hover, reset to saved position
    if (userScrolledDuringHover && savedScrollPosition !== null) {
      const container = getAutoScrollContainer();
      if (container) {
        container.scrollTop = savedScrollPosition;
        if (currentView === 'add-notes') {
          syncAddNotesScroll(container);
        }
      }
    }

    userScrolledDuringHover = false;
    savedScrollPosition = null;
    startAutoScroll();
  }
}

// Pause auto-scroll when opening settings
function pauseAnimationsForSettings() {
  console.log('[Settings] pauseAnimationsForSettings called, timerState:', timerState, 'isAutoScrollEnabled:', isAutoScrollEnabled());
  // Mark that settings was opened while auto-scroll should be running
  // Check if auto-scroll SHOULD be running, not just if it IS running
  // (it might be paused by hover)
  if (timerState === 'running' && isAutoScrollEnabled()) {
    autoScrollPausedBySettings = true;
    console.log('[Settings] autoScrollPausedBySettings set to true');
  }
  // Always stop auto-scroll when entering settings (safe to call even if not running)
  stopAutoScroll();
}

// Resume auto-scroll when closing settings
function resumeAnimationsAfterSettings() {
  console.log('[Settings] resumeAnimationsAfterSettings called, timerState:', timerState, 'isAutoScrollEnabled:', isAutoScrollEnabled());
  autoScrollPausedBySettings = false;

  // Don't resume if timer is not running
  if (timerState !== 'running') {
    console.log('[Settings] RETURN: timer not running');
    return;
  }

  // Don't resume if auto-scroll is disabled (Off)
  if (!isAutoScrollEnabled()) {
    console.log('[Settings] RETURN: auto-scroll not enabled');
    return;
  }

  // Reset hover state - user needs to move mouse out and back in to re-enable hover pause
  // This prevents the hover state from blocking auto-scroll when returning from settings
  console.log('[Settings] Resetting hover state and starting auto-scroll');
  isHoveringApp = false;
  autoScrollPausedByHover = false;
  userScrolledDuringHover = false;
  savedScrollPosition = null;

  // Start auto-scroll
  startAutoScroll();
}

// Track manual scroll during hover
function handleManualScroll() {
  if (isHoveringApp && autoScrollPausedByHover) {
    userScrolledDuringHover = true;
  }
}

// Setup hover listeners on the app container
function setupHoverPause() {
  if (appContainer) {
    appContainer.addEventListener('mouseenter', pauseOnHover);
    appContainer.addEventListener('mouseleave', resumeOnLeave);
  }

  // Add scroll listeners to track manual scrolling during hover
  if (notesContent) {
    notesContent.addEventListener('scroll', handleManualScroll);
  }
  if (notesInput) {
    notesInput.addEventListener('scroll', handleManualScroll);
  }
  if (notesInputHighlight) {
    notesInputHighlight.addEventListener('scroll', handleManualScroll);
  }
}

// Check if text contains [time mm:ss] pattern
function hasTimePattern(text) {
  const timePattern = /\[time\s+(\d{1,2}):(\d{2})\]/i;
  return timePattern.test(text);
}

// Update header timer visibility based on time tags and view
function updateHeaderTimerVisibility() {
  if (!headerTimer) return;
  const isNotesView = currentView === 'add-notes' || currentView === 'notes';
  const shouldShowHeaderTimer = isNotesView && notesHasTimeTags;
  headerTimer.classList.toggle('hidden', !shouldShowHeaderTimer);
}

// Update footer separators - add .has-separator class to visible items that follow other visible items
function updateFooterSeparators() {
  const footerLeft = document.querySelector('.footer-left');
  const footerRight = document.querySelector('.footer-right');

  [footerLeft, footerRight].forEach(container => {
    if (!container) return;

    const children = Array.from(container.children);
    let foundFirstVisible = false;

    children.forEach(child => {
      child.classList.remove('has-separator');

      if (!child.classList.contains('hidden')) {
        if (foundFirstVisible) {
          child.classList.add('has-separator');
        }
        foundFirstVisible = true;
      }
    });
  });
}

// Update timer button visibility based on state
function updateTimerButtonVisibility() {
  if (!btnStart || !btnPause || !btnReset) return;

  // Determine if we should show timer controls
  // Show when there's content (for auto-scroll), even without [time] tags
  let shouldShowTimers = false;

  if (currentView === 'add-notes') {
    // Check if input text has content AND we're not in edit mode
    shouldShowTimers = notesInput.value.trim() && !isEditMode;
  } else if (currentView === 'notes') {
    // Check if notes content exists
    shouldShowTimers = currentSlideData && notesContent && notesContent.textContent.trim();
  }

  // Show timer controls only when there's content with time pattern
  if (shouldShowTimers) {
    // Show appropriate buttons based on timer state
    switch (timerState) {
      case 'stopped':
        // Initial state: show Start only
        btnStart.classList.remove('hidden');
        btnPause.classList.add('hidden');
        btnReset.classList.add('hidden');
        break;
      case 'running':
        // Running: show Pause and Reset
        btnStart.classList.add('hidden');
        btnPause.classList.remove('hidden');
        btnReset.classList.remove('hidden');
        break;
      case 'paused':
        // Paused: show Start and Reset
        btnStart.classList.remove('hidden');
        btnPause.classList.add('hidden');
        btnReset.classList.remove('hidden');
        break;
    }
  } else {
    // Hide all timer controls
    btnStart.classList.add('hidden');
    btnPause.classList.add('hidden');
    btnReset.classList.add('hidden');
  }

  updateFooterSeparators();
}

// =============================================================================
// NOTES INPUT AND SYNTAX HIGHLIGHTING
// =============================================================================

// Setup syntax highlighting for notes input
function setupNotesInputHighlighting() {
  if (!notesInput || !notesInputHighlight) return;

  // Function to update the highlighted preview
  function updateHighlight() {
    const text = notesInput.value;
    if (!text) {
      notesInputHighlight.innerHTML = '';
      notesHasTimeTags = false;
      updateHeaderTimerVisibility();
      // Update timer button visibility when content changes
      updateTimerButtonVisibility();
      // Update edit note button visibility when content changes
      updateEditNoteButtonVisibility();
      return;
    }

    // Apply the same highlighting as in displayNotes
    const highlighted = highlightNotesForInput(text);
    notesInputHighlight.innerHTML = highlighted;

    // Update timer button visibility when content changes
    updateTimerButtonVisibility();
    // Update edit note button visibility when content changes
    updateEditNoteButtonVisibility();
  }

  // Listen for input changes
  notesInput.addEventListener('input', updateHighlight);
  notesInput.addEventListener('scroll', () => {
    if (currentView !== 'add-notes') return;
    syncAddNotesScroll(notesInput);
  });
  if (notesInputHighlight) {
    notesInputHighlight.addEventListener('scroll', () => {
      if (currentView !== 'add-notes' || isEditMode) return;
      syncAddNotesScroll(notesInputHighlight);
    });
  }

  // Initial update if there's already content
  updateHighlight();
}

function setupNotesScrollSync() {
  if (!notesContent) return;
}

// =============================================================================
// EDIT NOTE BUTTON
// =============================================================================

// Setup edit note button
function setupEditNoteButton() {
  if (!editNoteBtn || !notesInputWrapper) return;

  // Add click handler
  editNoteBtn.addEventListener("click", toggleEditMode);
}

// Toggle between edit and done modes
function toggleEditMode() {
  isEditMode = !isEditMode;

  if (isEditMode) {
    // Edit mode: input is editable, not highlighted
    trackEditAction('edit');
    notesInputWrapper.classList.add('edit-mode');
    notesInput.readOnly = false;
    editNoteBtn.textContent = 'Save Note';
    notesInput.focus();
  } else {
    // Done mode: input is readonly, highlighted
    trackEditAction('save');
    notesInputWrapper.classList.remove('edit-mode');
    notesInput.readOnly = true;
    editNoteBtn.textContent = 'Edit Note';
  }

  // Reset timer and auto-scroll when toggling edit/done
  resetTimerCountdown();
}

// Update edit note button visibility
function updateEditNoteButtonVisibility() {
  if (!editNoteBtn) return;

  const hasContent = notesInput.value.trim();

  // Only show button in add-notes view when there's content
  if (currentView === 'add-notes' && hasContent) {
    editNoteBtn.classList.remove('hidden');

    // If content was just added (transitioning from empty to non-empty),
    // start in edit mode (editable, not highlighted)
    if (!notesInputWrapper.classList.contains('edit-mode') && !notesInput.readOnly) {
      // User is actively typing/pasting - keep in edit mode
      isEditMode = true;
      notesInputWrapper.classList.add('edit-mode');
      notesInput.readOnly = false;
      editNoteBtn.textContent = 'Save Note';
    } else {
      // Update button text based on current mode
      editNoteBtn.textContent = isEditMode ? 'Save Note' : 'Edit Note';
    }
  } else {
    editNoteBtn.classList.add('hidden');

    // Reset to edit mode when content is cleared
    if (!hasContent) {
      isEditMode = true;
      notesInputWrapper.classList.add('edit-mode');
      notesInput.readOnly = false;
    }
  }

  updateFooterSeparators();
}

function trimSpacesPreserveNewlines(text) {
  return text.replace(/^[ \t]+|[ \t]+$/g, '');
}

function stripSingleLeadingNewline(text) {
  return text.replace(/^[ \t]*\n/, '');
}

// Highlight notes for input preview, wrapping content in sections
function highlightNotesForInput(text) {
  notesHasTimeTags = hasTimePattern(text);
  updateHeaderTimerVisibility();

  // Normalize all line break types to \n first
  let safe = text
    .replace(/\\n/g, '\n')
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .replace(/\u2028/g, '\n')
    .replace(/\u2029/g, '\n')
    .replace(/\v/g, '\n');

  // Escape HTML
  safe = escapeHtml(safe);

  // Pattern for [time mm:ss] syntax
  const timePattern = /\[time\s+(\d{1,2}):(\d{2})\]/gi;

  // Pattern for [note ...] syntax
  const notePattern = /\[note\s+([^\]]+)\]/gi;

  // Split by time markers to create sections
  const parts = safe.split(timePattern);

  let result = '';
  let cumulativeTime = 0;
  let sectionIndex = 0;

  // First part (before any [time]) is the first section (no timer)
  if (parts.length > 0) {
    let sectionContent = trimSpacesPreserveNewlines(parts[0]);
    sectionContent = sectionContent.replace(notePattern, (match, note) => {
      return `<span class="action-tag">[${note}]</span>`;
    });
    // Convert newlines to <br>
    sectionContent = sectionContent.replace(/\n/g, '<br>');

    if (sectionContent.replace(/<br>/g, '').trim()) {
      result += `<div class="notes-section" data-section="${sectionIndex}">${sectionContent}</div>`;
      sectionIndex++;
    }
  }

  // Process remaining parts (minutes, seconds, content triplets)
  for (let i = 1; i < parts.length; i += 3) {
    const minutes = parseInt(parts[i]);
    const seconds = parseInt(parts[i + 1]);
    const content = parts[i + 2] || '';

    const timeInSeconds = minutes * 60 + seconds;
    cumulativeTime += timeInSeconds;

    let sectionContent = trimSpacesPreserveNewlines(content);
    sectionContent = stripSingleLeadingNewline(sectionContent);
    sectionContent = sectionContent.replace(notePattern, (match, note) => {
      return `<span class="action-tag">[${note}]</span>`;
    });
    // Convert newlines to <br>
    sectionContent = sectionContent.replace(/\n/g, '<br>');

    // Don't show [time] tags in the view - just add the content
    if (sectionContent.replace(/<br>/g, '').trim()) {
      result += `<div class="notes-section" data-section="${sectionIndex}">${sectionContent}</div>`;
      sectionIndex++;
    }
  }

  // Update the global total time and remaining time
  totalTimeSeconds = cumulativeTime;
  remainingTimeSeconds = cumulativeTime;

  // Update header timer display
  if (headerTimer) {
    const minutes = Math.floor(cumulativeTime / 60);
    const seconds = cumulativeTime % 60;
    const displayTime = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
    headerTimer.textContent = displayTime;
    headerTimer.classList.remove('time-warning', 'time-overtime');
  }

  return result;
}

// Check authentication status
async function checkAuthStatus() {
  if (!invoke) {
    console.log("Tauri not available, skipping auth check");
    return;
  }
  try {
    const status = await invoke("get_auth_status");
    // Try to get user info if authenticated
    let name = '';
    let email = '';
    if (status) {
      try {
        const userInfo = await invoke("get_user_info");
        name = userInfo?.name || '';
        email = userInfo?.email || '';
      } catch (e) {
        console.log("Could not get user info:", e);
      }

      // Save user profile to Firestore
      if (email && name) {
        saveUserProfile(email, name);
      }
      // Set analytics user ID for returning users
      if (email) {
        setAnalyticsUserId(email);
        // Only track session if not already tracked (prevents duplicate counting)
        if (!sessionTracked) {
          trackSessionStart();
          sessionTracked = true;
        }
      }
    }
    updateAuthUI(status, name);
  } catch (error) {
    console.error("Error checking auth status:", error);
    updateAuthUI(false, '');
  }
}

// Get time-based greeting
function getGreeting() {
  const hour = new Date().getHours();

  if (hour >= 5 && hour < 12) {
    return 'Morning';
  } else if (hour >= 12 && hour < 17) {
    return 'Afternoon';
  } else if (hour >= 17 && hour < 21) {
    return 'Evening';
  } else {
    return 'Hello';
  }
}

// Extract first name from full name
function getFirstName(fullName) {
  if (!fullName) return '';
  return fullName.trim().split(' ')[0];
}

// Update UI based on auth status
function updateAuthUI(authenticated, name = '') {
  isAuthenticated = authenticated;
  userName = name;

  const buttonText = authBtn.querySelector('.gsi-material-button-contents');
  const buttonIcon = authBtn.querySelector('.gsi-material-button-icon');

  if (authenticated) {
    // Update button to show "Sign out"
    if (buttonText) buttonText.textContent = 'Sign out';
    if (buttonIcon) buttonIcon.style.display = 'none';

    // Update welcome heading with greeting and first name
    const firstName = getFirstName(name);
    const greeting = getGreeting();
    const versionSpan = welcomeHeading.querySelector('.version-text');
    const versionHTML = versionSpan ? versionSpan.outerHTML : '';
    welcomeHeading.innerHTML = `${greeting}, ${firstName}!${versionHTML ? '\n' + versionHTML : ''}`;

    // Update subtext to show paste notes link
    welcomeSubtext.innerHTML = 'Speak using <a href="#" class="paste-notes-link" id="paste-notes-link">Your Notes</a>, or sync them from <a href="#" class="slides-link" id="slides-link">Google Slides</a> seamlessly — visible only to you.';

    // Add click handler for Paste your notes link
    const pasteNotesLink = document.getElementById('paste-notes-link');
    if (pasteNotesLink) {
      pasteNotesLink.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        trackNotesPaste();
        showView('add-notes');
        notesInput.focus();
      });
    }

    // Add click handler for Google Slides link
    const slidesLink = document.getElementById('slides-link');
    if (slidesLink) {
      slidesLink.addEventListener('click', async (e) => {
        e.preventDefault();
        e.stopPropagation();
        trackSlidesSync();

        // Check if we have slides scope
        const hasSlidesScope = await hasScope('slides');
        if (!hasSlidesScope) {
          // Request slides scope
          console.log("Slides scope not granted, requesting...");
          await handleLogin('slides');
          return;
        }

        // Show notes view with slide data or default message
        if (currentSlideData) {
          showView('notes');
        } else {
          // Show notes view with default message when no slide is open
          displayNotes('Open a Google Slides presentation to see notes here.\n[note Install CueCard Extension to sync notes]');
          window.title = 'No Slide Open';
          showView('notes');
        }
      });
    }
  } else {
    // Update button to show "Sign in"
    if (buttonText) buttonText.textContent = 'Sign in with Google';
    if (buttonIcon) buttonIcon.style.display = 'block';

    // Reset welcome heading to default
    welcomeHeading.innerHTML = 'CueCard\n<span class="version-text">1.2.2</span>';

    // Reset subtext
    welcomeSubtext.innerHTML = 'Speaker notes visible only to you during screen sharing — for <span class="highlight-presentations">presentations</span>, <span class="highlight-meetings">meetings</span>, and more...';
  }
}

// Handle login with specific scope
// scope: 'profile' for basic auth, 'slides' for Google Slides access
async function handleLogin(scope = 'profile') {
  try {
    if (!invoke) {
      console.error("Tauri invoke API not available");
      alert("Please run the app in Tauri mode");
      return;
    }
    await invoke("start_login", { scope });
  } catch (error) {
    console.error("Error starting login:", error);
  }
}

// Handle logout
async function handleLogout() {
  if (!invoke) {
    console.error("Tauri invoke API not available");
    return;
  }
  try {
    await invoke("logout");
    updateAuthUI(false, '');
    // Reset to initial view if viewing slide notes
    if (currentView === 'notes' && !manualNotes) {
      showView('initial');
    }
  } catch (error) {
    console.error("Error logging out:", error);
  }
}

// Check if there's already slide data
async function checkCurrentSlide() {
  if (!invoke) {
    console.log("Tauri not available, skipping slide check");
    return;
  }
  try {
    const slide = await invoke("get_current_slide");
    if (slide) {
      const notes = await invoke("get_current_notes");
      handleSlideUpdate({ slide_data: slide, notes }, false); // Don't auto-show
    }
  } catch (error) {
    console.error("Error checking current slide:", error);
  }
}

// Handle slide update from Google Slides
function handleSlideUpdate(data, autoShow = false) {
  const { slide_data, notes } = data;

  if (!slide_data) {
    return;
  }

  // Check if this is a different slide (slide changed)
  const isNewSlide = !currentSlideData ||
    currentSlideData.slideId !== slide_data.slideId ||
    currentSlideData.presentationId !== slide_data.presentationId;

  // Track slide update from extension
  if (isNewSlide) {
    trackSlideUpdate();
  }

  // Store current slide data
  currentSlideData = slide_data;

  // Display the notes
  if (notes && notes.trim()) {
    // If viewing notes and slide changed, reset timer and start fresh
    if (currentView === 'notes' && isNewSlide) {
      stopAllTimers();
      timerState = 'stopped';
    }

    displayNotes(notes, slide_data);

    // If viewing notes and slide changed, start timer automatically
    if (currentView === 'notes' && isNewSlide) {
      startTimerCountdown();
    }

    // Only auto-show if explicitly requested
    if (autoShow) {
      showView('notes');
    }
  }
}

// =============================================================================
// VIEW MANAGEMENT
// =============================================================================

// Show a specific view
async function showView(viewName) {
  // Save notes to storage if we're in add-notes view
  if (currentView === 'add-notes') {
    await saveNotesToStorage();
  }

  previousView = currentView;
  currentView = viewName;

  // Track screen view when navigating (settings is tracked separately in footer handler)
  if (viewName !== 'settings') {
    const pageTitles = {
      'initial': 'CueCard Home',
      'add-notes': 'CueCard Add Notes',
      'notes': 'CueCard Notes'
    };
    trackScreenView(viewName, pageTitles[viewName] || 'CueCard');
  }

  if (appContainer) {
    appContainer.classList.remove('stroke-add-notes', 'stroke-slides');
    if (viewName === 'add-notes') {
      appContainer.classList.add('stroke-add-notes');
    } else if (viewName === 'notes') {
      appContainer.classList.add('stroke-slides');
    }
  }

  // Hide all views
  viewInitial.classList.add('hidden');
  viewAddNotes.classList.add('hidden');
  viewNotes.classList.add('hidden');
  viewSettings.classList.add('hidden');
  viewShortcuts.classList.add('hidden');

  // Show/hide the back button in footer based on view
  if (viewName === 'add-notes' || viewName === 'notes' || viewName === 'settings' || viewName === 'shortcuts') {
    linkGoBack.classList.remove('hidden');
  } else {
    linkGoBack.classList.add('hidden');
  }

  // Show settings and shortcuts links
  settingsLink.classList.remove('hidden');
  shortcutsLink.classList.remove('hidden');

  if (btnClose && appHeaderTitle && headerTimer) {
    const isSettingsView = viewName === 'settings';
    const isShortcutsView = viewName === 'shortcuts';
    const isNotesView = viewName === 'add-notes' || viewName === 'notes';

    // Hide close button for settings, shortcuts and notes views, show only for initial view
    btnClose.classList.toggle('hidden', isSettingsView || isShortcutsView || isNotesView);
    appHeaderTitle.classList.toggle('hidden', !isSettingsView && !isShortcutsView);

    // Update header title text
    if (isSettingsView) {
      appHeaderTitle.textContent = 'Settings';
    } else if (isShortcutsView) {
      appHeaderTitle.textContent = 'Shortcuts';
    }

    updateHeaderTimerVisibility();
  }

  // Show/hide privacy, website, and settings links based on view
  if (viewName === 'initial') {
    // Initial view: show Visit Site, Settings
    websiteLink.classList.remove('hidden');
    supportLink.classList.add('hidden');
    bugLink.classList.add('hidden');
  } else if (viewName === 'settings') {
    // Settings view: show Support, Report Bug (no Settings button or Visit Site)
    websiteLink.classList.add('hidden');
    supportLink.classList.remove('hidden');
    bugLink.classList.remove('hidden');
    settingsLink.classList.add('hidden');
    shortcutsLink.classList.add('hidden');
  } else if (viewName === 'shortcuts') {
    // Shortcuts view: hide all footer links except go back
    websiteLink.classList.add('hidden');
    supportLink.classList.add('hidden');
    bugLink.classList.add('hidden');
    settingsLink.classList.add('hidden');
    shortcutsLink.classList.add('hidden');
  } else {
    // Notes and Add-Notes views: hide all footer links except go back
    websiteLink.classList.add('hidden');
    supportLink.classList.add('hidden');
    bugLink.classList.add('hidden');
  }

  // Show/hide slide info and refresh button based on view and slide data
  if (viewName === 'notes' && currentSlideData) {
    refreshBtn.classList.remove('hidden');
  } else {
    refreshBtn.classList.add('hidden');
  }

  // Update timer button visibility
  updateTimerButtonVisibility();

  // Update edit note button visibility
  updateEditNoteButtonVisibility();

  if (viewName === 'settings' && (previousView === 'add-notes' || previousView === 'notes')) {
    pauseAnimationsForSettings();
  }

  // Stop auto-scroll when leaving a view
  if (previousView === 'add-notes' || previousView === 'notes') {
    stopAutoScroll();
  }

  // Show the requested view
  switch (viewName) {
    case 'initial':
      viewInitial.classList.remove('hidden');
      break;
    case 'add-notes':
      viewAddNotes.classList.remove('hidden');
      // Load stored notes when entering add-notes view
      // But skip loading if coming back from settings (content is already there)
      if (previousView !== 'settings') {
        await loadStoredNotes();
        // If notes were loaded from storage, start in done mode (readonly, highlighted)
        if (notesInput.value.trim()) {
          isEditMode = false;
          notesInputWrapper.classList.remove('edit-mode');
          notesInput.readOnly = true;
          editNoteBtn.textContent = 'Edit Note';
        }
      }
      // Update edit note button visibility
      updateEditNoteButtonVisibility();
      // Update timer button visibility after notes are loaded
      updateTimerButtonVisibility();
      // Don't auto-start auto-scroll - wait for Start button
      break;
    case 'notes':
      viewNotes.classList.remove('hidden');
      // In notes view, timer starts automatically if slide is present
      // But don't auto-start if we're coming back from settings (preserve timer state)
      const hasNotesContent = notesContent && notesContent.textContent.trim();
      if (!hasNotesContent) {
        notesHasTimeTags = false;
        updateHeaderTimerVisibility();
        stopAllTimers();
        timerState = 'stopped';
        stopAutoScroll();
        updateTimerButtonVisibility();
      }
      if (timerState === 'stopped' && currentSlideData && hasNotesContent && previousView !== 'settings') {
        startTimerCountdown();
      }
      // Don't auto-start auto-scroll - wait for Start button
      break;
    case 'settings':
      viewSettings.classList.remove('hidden');
      // Load current settings when showing settings view
      loadCurrentSettings();
      break;
    case 'shortcuts':
      viewShortcuts.classList.remove('hidden');
      // Populate shortcut key displays
      populateShortcutKeys();
      break;
  }

  if (previousView === 'settings' && (viewName === 'add-notes' || viewName === 'notes')) {
    resumeAnimationsAfterSettings();
  }

  updateFooterSeparators();
}

// Truncate text to max length with ellipsis
function truncateText(text, maxLength = 35) {
  if (!text) return text;
  if (text.length <= maxLength) return text;
  return text.substring(0, maxLength) + '...';
}

// =============================================================================
// NOTES DISPLAY
// =============================================================================

// Display notes with syntax highlighting
function displayNotes(text, slideData = null) {
  const highlighted = highlightNotes(text);
  notesContent.innerHTML = highlighted;

  // Update slide info if available
  if (slideData) {
    // Use camelCase property names (as sent by backend with serde rename_all = "camelCase")
    const presentationTitle = slideData.title || 'Untitled Presentation';
    window.title = truncateText(presentationTitle);

    // Show slide info and refresh button in footer when there's slide data
    if (currentView === 'notes') {
      refreshBtn.classList.remove('hidden');
    }
  } else {
    window.title = 'No Slide Open';

    // Hide slide info and refresh button when no slide
    refreshBtn.classList.add('hidden');
  }

  // Update timer button visibility
  updateTimerButtonVisibility();
}

// Highlight timestamps and action tags in notes, wrapping content in sections
function highlightNotes(text) {
  notesHasTimeTags = hasTimePattern(text);
  updateHeaderTimerVisibility();

  // Normalize all line break types to \n first
  // Handles: \r\n (Windows), \r (old Mac), \n (Unix),
  // \u2028 (Line Separator), \u2029 (Paragraph Separator), \v (Vertical Tab)
  let safe = text
    .replace(/\\n/g, '\n')
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .replace(/\u2028/g, '\n')
    .replace(/\u2029/g, '\n')
    .replace(/\v/g, '\n');

  // Escape HTML
  safe = escapeHtml(safe);

  // Pattern for [time mm:ss] syntax
  const timePattern = /\[time\s+(\d{1,2}):(\d{2})\]/gi;

  // Pattern for [note ...] syntax - matches anything between [note and ]
  const notePattern = /\[note\s+([^\]]+)\]/gi;

  // Pattern for "CueCard Extension" - replace with link
  const cuecardPattern = /CueCard Extension/gi;

  // Split by time markers to create sections
  const parts = safe.split(timePattern);

  let result = '';
  let cumulativeTime = 0;
  let sectionIndex = 0;

  // First part (before any [time]) is the first section (no timer)
  if (parts.length > 0) {
    let sectionContent = trimSpacesPreserveNewlines(parts[0]);
    // Apply note pattern and CueCard Extension link
    sectionContent = sectionContent.replace(notePattern, (match, note) => {
      return `<span class="action-tag">[${note}]</span>`;
    });
    sectionContent = sectionContent.replace(cuecardPattern, (match) => {
      return `<a href="https://cuecard.dev/#download" class="slides-link" target="_blank" rel="noopener noreferrer">${match}</a>`;
    });
    // Convert newlines to <br>
    sectionContent = sectionContent.replace(/\n/g, '<br>');

    if (sectionContent.replace(/<br>/g, '').trim()) {
      result += `<div class="notes-section" data-section="${sectionIndex}">${sectionContent}</div>`;
      sectionIndex++;
    }
  }

  // Process remaining parts (minutes, seconds, content triplets)
  for (let i = 1; i < parts.length; i += 3) {
    const minutes = parseInt(parts[i]);
    const seconds = parseInt(parts[i + 1]);
    const content = parts[i + 2] || '';

    const timeInSeconds = minutes * 60 + seconds;
    cumulativeTime += timeInSeconds;

    let sectionContent = trimSpacesPreserveNewlines(content);
    sectionContent = stripSingleLeadingNewline(sectionContent);
    // Apply note pattern and CueCard Extension link
    sectionContent = sectionContent.replace(notePattern, (match, note) => {
      return `<span class="action-tag">[${note}]</span>`;
    });
    sectionContent = sectionContent.replace(cuecardPattern, (match) => {
      return `<a href="https://cuecard.dev/#download" class="slides-link" target="_blank" rel="noopener noreferrer">${match}</a>`;
    });
    // Convert newlines to <br>
    sectionContent = sectionContent.replace(/\n/g, '<br>');

    // Don't show [time] tags in the view - just add the content
    if (sectionContent.replace(/<br>/g, '').trim()) {
      result += `<div class="notes-section" data-section="${sectionIndex}">${sectionContent}</div>`;
      sectionIndex++;
    }
  }

  // Update the global total time and remaining time
  totalTimeSeconds = cumulativeTime;
  remainingTimeSeconds = cumulativeTime;

  // Update header timer display
  if (headerTimer) {
    const minutes = Math.floor(cumulativeTime / 60);
    const seconds = cumulativeTime % 60;
    const displayTime = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
    headerTimer.textContent = displayTime;
    headerTimer.classList.remove('time-warning', 'time-overtime');
  }

  return result;
}

// Escape HTML to prevent XSS (preserves newlines)
function escapeHtml(text) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

// =============================================================================
// HEADER, FOOTER AND EXTERNAL LINKS
// =============================================================================

// Header Handlers
function setupHeader() {
  // Close button handler
  btnClose.addEventListener("click", async (e) => {
    e.preventDefault();
    console.log("Close button clicked");
    if (getCurrentWindow) {
      await getCurrentWindow().close();
    } else {
      console.error("Tauri window API not available");
    }
  });

  // Download updates button handler
  btnDownloadUpdates.addEventListener("click", async (e) => {
    e.preventDefault();
    console.log("Download updates button clicked");

    // Disable the button during download
    btnDownloadUpdates.disabled = true;

    try {
      const update = await check();

      if (update?.available) {
        console.log(`Update available: ${update.version}`);

        // Show download progress in button text
        btnDownloadUpdates.textContent = 'Downloading...';

        // Download and install with progress tracking
        let contentLength = 0;
        let downloaded = 0;

        await update.downloadAndInstall((event) => {
          switch (event.event) {
            case 'Started':
              contentLength = event.data.contentLength || 0;
              downloaded = 0;
              btnDownloadUpdates.textContent = 'Downloading...';
              console.log(`Started downloading ${contentLength} bytes`);
              break;
            case 'Progress':
              downloaded += event.data.chunkLength;
              if (contentLength > 0) {
                const percent = Math.round((downloaded / contentLength) * 100);
                btnDownloadUpdates.textContent = `Downloading ${percent}%`;
              }
              console.log(`Downloaded ${downloaded} of ${contentLength}`);
              break;
            case 'Finished':
              btnDownloadUpdates.textContent = 'Installing...';
              console.log('Download finished');
              break;
          }
        });

        console.log('Update installed, preparing to relaunch');

        // Hide the button before relaunch
        btnDownloadUpdates.classList.add('hidden');
        downloadUpdatesSeparator.classList.add('hidden');

        // Relaunch the app
        await relaunch();
      }
    } catch (error) {
      console.error('Update failed:', error);
      btnDownloadUpdates.textContent = 'Update Failed';
      btnDownloadUpdates.disabled = false;

      // Reset button text after 3 seconds
      setTimeout(() => {
        btnDownloadUpdates.textContent = 'Download Updates';
      }, 3000);
    }
  });
}

// =============================================================================
// UPDATE CHECKER
// =============================================================================

// Set up automatic update checking
function setupUpdateChecker() {
  // Check for updates immediately on startup
  checkForUpdates();

  // Check for updates every minute (60000 ms)
  setInterval(checkForUpdates, 60000);
}

// Check for updates and show button if available
async function checkForUpdates() {
  try {
    console.log('Checking for updates...');
    const update = await check();

    if (update?.available) {
      console.log(`Update available: ${update.version}`);
      // Show the download updates button
      btnDownloadUpdates.classList.remove('hidden');
      downloadUpdatesSeparator.classList.remove('hidden');
    } else {
      console.log('No updates available');
      // Hide the button if no updates
      btnDownloadUpdates.classList.add('hidden');
      downloadUpdatesSeparator.classList.add('hidden');
    }
  } catch (error) {
    console.error('Error checking for updates:', error);
    // Hide button on error
    btnDownloadUpdates.classList.add('hidden');
    downloadUpdatesSeparator.classList.add('hidden');
  }
}

// Footer Handlers
function setupFooter() {
  bugLink.addEventListener("click", async (e) => {
    e.preventDefault();
    console.log("Bug link clicked");
    try {
      if (!openUrl) {
        console.error("Tauri opener API not available");
        window.open("https://github.com/ThisIsNSH/CueCard/issues/new/choose", "_blank", "noopener,noreferrer");
        return;
      }
      await openUrl("https://github.com/ThisIsNSH/CueCard/issues/new/choose");
    } catch (error) {
      console.error("Error opening bug report:", error);
    }
  });

  supportLink.addEventListener("click", async (e) => {
    e.preventDefault();
    console.log("Support link clicked");
    try {
      if (!openUrl) {
        console.error("Tauri opener API not available");
        window.open("mailto:support@cuecard.dev", "_blank", "noopener,noreferrer");
        return;
      }
      await openUrl("mailto:support@cuecard.dev");
    } catch (error) {
      console.error("Error opening support email:", error);
    }
  });

  websiteLink.addEventListener("click", async (e) => {
    e.preventDefault();
    console.log("Website link clicked");
    try {
      if (!openUrl) {
        console.error("Tauri opener API not available");
        window.open("https://cuecard.dev", "_blank", "noopener,noreferrer");
        return;
      }
      await openUrl("https://cuecard.dev");
    } catch (error) {
      console.error("Error opening website:", error);
    }
  });

  // Settings link handler
  settingsLink.addEventListener("click", (e) => {
    e.preventDefault();
    console.log("Settings link clicked");
    trackScreenView('settings', 'CueCard Settings');
    showView('settings');
  });

  // Shortcuts link handler
  shortcutsLink.addEventListener("click", (e) => {
    e.preventDefault();
    console.log("Shortcuts link clicked");
    trackScreenView('shortcuts', 'CueCard Shortcuts');
    showView('shortcuts');
  });
}

// =============================================================================
// SETTINGS MANAGEMENT
// =============================================================================

// Default settings values
const DEFAULT_OPACITY = 100;
const DEFAULT_GHOST_MODE = true; // true = ghost mode ON = hidden from screenshots
const DEFAULT_SCROLL_SPEED = 0; // 0 = Off (see SCROLL_SPEED_PRESETS)

// Apply theme based on preference ('system', 'light', 'dark')
function applyTheme(theme) {
  let isLight = false;
  if (theme === 'light') {
    isLight = true;
  } else if (theme === 'dark') {
    isLight = false;
  } else {
    // System preference
    isLight = window.matchMedia('(prefers-color-scheme: light)').matches;
  }
  document.documentElement.classList.toggle('theme-light', isLight);
}

// Update theme button states
function updateThemeButtons(theme) {
  if (themeSystemBtn) themeSystemBtn.classList.toggle('active', theme === 'system');
  if (themeLightBtn) themeLightBtn.classList.toggle('active', theme === 'light');
  if (themeDarkBtn) themeDarkBtn.classList.toggle('active', theme === 'dark');
}

// Load stored settings from persistent storage
async function loadStoredSettings() {
  // Load stored opacity or use default
  const storedOpacity = await getStoredValue(STORAGE_KEYS.SETTINGS_OPACITY);
  if (storedOpacity !== null && storedOpacity !== undefined) {
    currentOpacity = storedOpacity;
  } else {
    currentOpacity = DEFAULT_OPACITY;
    await setStoredValue(STORAGE_KEYS.SETTINGS_OPACITY, DEFAULT_OPACITY);
  }
  // Apply opacity via CSS variable
  document.documentElement.style.setProperty('--bg-opacity', currentOpacity / 100);

  // Load stored ghost mode setting or use default
  const storedGhostMode = await getStoredValue(STORAGE_KEYS.SETTINGS_GHOST_MODE);
  if (storedGhostMode !== null && storedGhostMode !== undefined) {
    ghostMode = storedGhostMode;
  } else {
    ghostMode = DEFAULT_GHOST_MODE;
    await setStoredValue(STORAGE_KEYS.SETTINGS_GHOST_MODE, DEFAULT_GHOST_MODE);
  }
  updateGhostModeIndicator();
  // Apply screenshot protection via Rust (protection = ghostMode)
  if (invoke) {
    try {
      await invoke("set_screenshot_protection", { enabled: ghostMode });
    } catch (error) {
      console.error("Error applying screenshot protection:", error);
    }
  }

  // Load stored theme setting or use default (system)
  const storedTheme = await getStoredValue(STORAGE_KEYS.SETTINGS_THEME);
  if (storedTheme !== null && storedTheme !== undefined) {
    currentTheme = storedTheme;
  } else {
    currentTheme = 'system';
    await setStoredValue(STORAGE_KEYS.SETTINGS_THEME, 'system');
  }
  applyTheme(currentTheme);

  // Load stored scroll speed setting or use default
  const storedScrollSpeed = await getStoredValue(STORAGE_KEYS.SETTINGS_SCROLL_SPEED);
  if (storedScrollSpeed !== null && storedScrollSpeed !== undefined) {
    scrollSpeedIndex = storedScrollSpeed;
  } else {
    scrollSpeedIndex = DEFAULT_SCROLL_SPEED;
    await setStoredValue(STORAGE_KEYS.SETTINGS_SCROLL_SPEED, DEFAULT_SCROLL_SPEED);
  }
}

// Settings Handlers
function setupSettings() {
  // Opacity slider handler
  let opacityTrackingTimeout = null;
  if (opacitySlider) {
    opacitySlider.addEventListener("input", async (e) => {
      const value = parseInt(e.target.value);
      currentOpacity = value;
      opacityValue.textContent = `${value}%`;

      // Update window opacity via CSS variable
      document.documentElement.style.setProperty('--bg-opacity', value / 100);

      // Save to persistent storage
      await setStoredValue(STORAGE_KEYS.SETTINGS_OPACITY, value);

      // Debounce analytics tracking (only track final value after user stops dragging)
      clearTimeout(opacityTrackingTimeout);
      opacityTrackingTimeout = setTimeout(() => {
        trackSettingChange('opacity', value);
      }, 500);
    });
  }

  // Ghost mode toggle handler
  if (ghostModeToggle) {
    ghostModeToggle.addEventListener("change", async (e) => {
      ghostMode = e.target.checked;
      updateGhostModeIndicator();

      // Track setting change
      trackSettingChange('ghost_mode', ghostMode);

      // Update screenshot protection via Tauri (protection = ghostMode)
      if (invoke) {
        try {
          await invoke("set_screenshot_protection", { enabled: ghostMode });
        } catch (error) {
          console.error("Error setting screenshot protection:", error);
        }
      }

      // Save to persistent storage
      await setStoredValue(STORAGE_KEYS.SETTINGS_GHOST_MODE, ghostMode);
    });
  }

  // Theme button handlers
  const themeButtons = [themeSystemBtn, themeLightBtn, themeDarkBtn];
  themeButtons.forEach(btn => {
    if (btn) {
      btn.addEventListener("click", async (e) => {
        const theme = btn.dataset.theme;
        currentTheme = theme;
        applyTheme(theme);
        updateThemeButtons(theme);

        // Track setting change
        trackSettingChange('theme', theme);

        // Save to persistent storage
        await setStoredValue(STORAGE_KEYS.SETTINGS_THEME, theme);
      });
    }
  });

  // Scroll speed slider handler (combined toggle + speed)
  let scrollSpeedTrackingTimeout = null;
  if (scrollSpeedSlider) {
    scrollSpeedSlider.addEventListener("input", async (e) => {
      const value = parseInt(e.target.value);
      scrollSpeedIndex = value;
      const preset = SCROLL_SPEED_PRESETS[value];
      scrollSpeedValue.textContent = preset.label;

      // Save to persistent storage
      await setStoredValue(STORAGE_KEYS.SETTINGS_SCROLL_SPEED, value);

      // Start, restart, or stop auto-scroll based on new speed
      if (currentView === 'add-notes' || currentView === 'notes') {
        if (isAutoScrollEnabled() && timerState === 'running') {
          restartAutoScroll();
        } else {
          stopAutoScroll();
        }
      }

      // Debounce analytics tracking
      clearTimeout(scrollSpeedTrackingTimeout);
      scrollSpeedTrackingTimeout = setTimeout(() => {
        trackSettingChange('scroll_speed', preset.label);
      }, 500);
    });
  }
}

function updateGhostModeIndicator() {
  if (!ghostModeIndicator) return;
  ghostModeIndicator.textContent = `Ghost Mode ${ghostMode ? 'Enabled' : 'Disabled'}`;
}

// Load current settings values
async function loadCurrentSettings() {
  // Load current opacity from CSS variable
  const opacity = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--bg-opacity')) || 1;
  const opacityPercent = Math.round(opacity * 100);
  currentOpacity = opacityPercent;
  if (opacitySlider) {
    opacitySlider.value = opacityPercent;
  }
  if (opacityValue) {
    opacityValue.textContent = `${opacityPercent}%`;
  }

  // Ghost mode toggle: checkbox reflects ghostMode directly
  if (ghostModeToggle) {
    ghostModeToggle.checked = ghostMode;
  }
  updateGhostModeIndicator();

  // Update theme buttons
  updateThemeButtons(currentTheme);

  // Scroll speed slider
  if (scrollSpeedSlider) {
    scrollSpeedSlider.value = scrollSpeedIndex;
  }
  if (scrollSpeedValue) {
    const preset = SCROLL_SPEED_PRESETS[scrollSpeedIndex];
    scrollSpeedValue.textContent = preset.label;
  }
}

// =============================================================================
// GLOBAL SHORTCUTS
// =============================================================================

// Shortcut definitions with platform-specific display
const SHORTCUTS = {
  'toggle-visibility': { mac: ['Option', 'Shift', 'C'], win: ['Alt', 'Shift', 'C'] },
  'opacity-down': { mac: ['Option', 'Shift', '-'], win: ['Alt', 'Shift', '-'] },
  'opacity-up': { mac: ['Option', 'Shift', '='], win: ['Alt', 'Shift', '='] },
  'height-down': { mac: ['Option', 'Shift', '↑'], win: ['Alt', 'Shift', '↑'] },
  'height-up': { mac: ['Option', 'Shift', '↓'], win: ['Alt', 'Shift', '↓'] },
  'move-left': { mac: ['Option', 'Shift', '←'], win: ['Alt', 'Shift', '←'] },
  'move-right': { mac: ['Option', 'Shift', '→'], win: ['Alt', 'Shift', '→'] },
  'move-up': { mac: ['Option', 'Ctrl', '↑'], win: ['Alt', 'Ctrl', '↑'] },
  'move-down': { mac: ['Option', 'Ctrl', '↓'], win: ['Alt', 'Ctrl', '↓'] },
  'timer-toggle': { mac: ['Option', 'Shift', 'Space'], win: ['Alt', 'Shift', 'Space'] },
  'timer-reset': { mac: ['Option', 'Shift', '0'], win: ['Alt', 'Shift', '0'] },
};

// Check if running on macOS
function isMac() {
  return navigator.platform.toUpperCase().indexOf('MAC') >= 0;
}

// Populate shortcut key displays in the shortcuts view
function populateShortcutKeys() {
  const platform = isMac() ? 'mac' : 'win';

  Object.entries(SHORTCUTS).forEach(([action, keys]) => {
    const element = document.getElementById(`shortcut-${action}`);
    if (element) {
      const keyList = keys[platform];
      element.innerHTML = keyList.map(key => `<kbd>${key}</kbd>`).join(' ');
    }
  });
}

// Handle shortcut actions
async function handleShortcutAction(action) {
  const window = getCurrentWindow ? getCurrentWindow() : null;
  if (!window) return;

  switch (action) {
    case 'toggle-visibility':
      const isVisible = await window.isVisible();
      if (isVisible) {
        await window.hide();
      } else {
        await window.show();
      }
      break;

    case 'opacity-down':
      currentOpacity = Math.max(10, currentOpacity - 10);
      await applyOpacity(currentOpacity);
      break;

    case 'opacity-up':
      currentOpacity = Math.min(100, currentOpacity + 10);
      await applyOpacity(currentOpacity);
      break;

    case 'height-down':
      const sizeDown = await window.innerSize();
      const scaleDown = await window.scaleFactor();
      const logicalWidthDown = Math.round(sizeDown.width / scaleDown);
      const logicalHeightDown = Math.round(sizeDown.height / scaleDown);
      const minHeight = 300; // Match minHeight from tauri.conf.json
      if (logicalHeightDown > minHeight) {
        const newHeightDown = Math.max(minHeight, logicalHeightDown - 50);
        await window.setSize({ width: logicalWidthDown, height: newHeightDown, type: 'Logical' });
      }
      break;

    case 'height-up':
      const sizeUp = await window.innerSize();
      const scaleUp = await window.scaleFactor();
      const logicalWidthUp = Math.round(sizeUp.width / scaleUp);
      const logicalHeightUp = Math.round(sizeUp.height / scaleUp);
      const newHeightUp = logicalHeightUp + 50;
      await window.setSize({ width: logicalWidthUp, height: newHeightUp, type: 'Logical' });
      break;

    case 'move-left':
      const posLeft = await window.outerPosition();
      await window.setPosition({ x: posLeft.x - 50, y: posLeft.y, type: 'Physical' });
      break;

    case 'move-right':
      const posRight = await window.outerPosition();
      await window.setPosition({ x: posRight.x + 50, y: posRight.y, type: 'Physical' });
      break;

    case 'move-up':
      const posUp = await window.outerPosition();
      await window.setPosition({ x: posUp.x, y: posUp.y - 50, type: 'Physical' });
      break;

    case 'move-down':
      const posDown = await window.outerPosition();
      await window.setPosition({ x: posDown.x, y: posDown.y + 50, type: 'Physical' });
      break;

    case 'timer-toggle':
      if (timerState === 'running') {
        pauseTimerCountdown();
      } else {
        startTimerCountdown();
      }
      break;

    case 'timer-reset':
      resetTimerCountdown();
      break;
  }
}

// Apply opacity change from shortcut
async function applyOpacity(value) {
  document.documentElement.style.setProperty('--bg-opacity', value / 100);
  if (opacitySlider) opacitySlider.value = value;
  if (opacityValue) opacityValue.textContent = `${value}%`;
  await storeValue(STORAGE_KEYS.SETTINGS_OPACITY, value);
}

// Setup shortcut event listener
async function setupShortcutListener() {
  if (!listen) return;

  await listen("shortcut-triggered", (event) => {
    const action = event.payload;
    console.log("Shortcut triggered:", action);
    handleShortcutAction(action);
  });
}
