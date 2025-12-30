/**
 * CueCard - Main Frontend Application
 *
 * This file contains the main frontend logic for the CueCard application:
 * - Firebase Analytics for usage tracking
 * - Firestore integration for user profiles
 * - Persistent storage management
 * - Google OAuth authentication UI
 * - Notes display and syntax highlighting
 * - Timer functionality for presentations
 * - Settings management (opacity, screenshot protection)
 */

// =============================================================================
// ANALYTICS IMPORTS
// =============================================================================

import {
  initAnalytics,
  setAnalyticsUserId,
  trackAppOpen,
  trackSessionStart,
  trackLogin,
  trackLogout,
  trackScreenView,
  trackNotesPaste,
  trackSlidesSync,
  trackTimerAction,
  trackSettingChange,
  trackSlideUpdate,
  trackEditAction
} from './analytics.js';

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
// PLATFORM-SPECIFIC STYLES
// =============================================================================

function setPlatformClass() {
  const root = document.documentElement;
  const platform = (navigator.userAgentData && navigator.userAgentData.platform)
    || navigator.platform
    || navigator.userAgent
    || '';

  if (/win/i.test(platform)) {
    root.classList.add('platform-windows');
  } else if (/mac/i.test(platform)) {
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
  SETTINGS_SHOW_IN_SCREENSHOT: 'settings_show_in_screenshot',
  SETTINGS_LIGHT_MODE: 'settings_light_mode',
  ADD_NOTES_CONTENT: 'add_notes_content'
};

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
let appContainer, appHeader, appHeaderTitle, viewInitial, viewAddNotes, viewNotes, viewSettings;
let linkGoBack, backSeparator;
let notesInput, notesContent;
let welcomeHeading, welcomeSubtext;
let bugLink, websiteLink, websiteSeparator, supportLink, supportSeparator;
let settingsLink, settingsSeparator;
let refreshBtn, refreshSeparator;
let notesInputHighlight;
let timerSeparator, timerStartSeparator, timerPauseSeparator;
let btnStart, btnPause, btnReset;
let opacitySlider, opacityValue, screenCaptureToggle, lightModeToggle;
let editNoteBtn, editNoteSeparator;
let notesInputWrapper;
let ghostModeIndicator;

// State
let isAuthenticated = false;
let userName = '';
let currentView = 'initial'; // 'initial', 'add-notes', 'notes', 'settings'
let previousView = null; // 'initial', 'add-notes', 'notes', 'settings'
let manualNotes = ''; // Notes pasted by the user
let currentSlideData = null; // Store current slide data
let currentOpacity = 100; // Store current opacity value (10-100)
let showInScreenshot = false; // Default: false = hidden from screenshots
let isLightMode = false; // Default: dark mode

// Timer State
let timerState = 'stopped'; // 'stopped', 'running', 'paused'
let timerIntervals = []; // Store all timer interval IDs

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

  // Initialize Firebase Analytics
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
  linkGoBack = document.getElementById("link-go-back");
  backSeparator = document.getElementById("back-separator");
  notesInput = document.getElementById("notes-input");
  notesContent = document.getElementById("notes-content");
  welcomeHeading = document.getElementById("welcome-heading");
  welcomeSubtext = document.getElementById("welcome-subtext");
  bugLink = document.getElementById("bug-link");
  websiteLink = document.getElementById("website-link");
  websiteSeparator = document.getElementById("website-separator");
  supportLink = document.getElementById("support-link");
  supportSeparator = document.getElementById("support-separator");
  settingsLink = document.getElementById("settings-link");
  settingsSeparator = document.getElementById("settings-separator");
  refreshBtn = document.getElementById("refresh-btn");
  refreshSeparator = document.getElementById("refresh-separator");
  notesInputHighlight = document.getElementById("notes-input-highlight");
  timerSeparator = document.getElementById("timer-separator");
  timerStartSeparator = document.getElementById("timer-start-separator");
  timerPauseSeparator = document.getElementById("timer-pause-separator");
  btnStart = document.getElementById("btn-start");
  btnPause = document.getElementById("btn-pause");
  btnReset = document.getElementById("btn-reset");
  opacitySlider = document.getElementById("opacity-slider");
  opacityValue = document.getElementById("opacity-value");
  screenCaptureToggle = document.getElementById("screen-capture-toggle");
  lightModeToggle = document.getElementById("light-mode-toggle");
  editNoteBtn = document.getElementById("edit-note-btn");
  editNoteSeparator = document.getElementById("edit-note-separator");
  notesInputWrapper = document.querySelector(".notes-input-wrapper");
  ghostModeIndicator = document.getElementById("ghost-mode-indicator");

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

  // Set up syntax highlighting for notes input
  setupNotesInputHighlighting();

  // Set up edit note button
  setupEditNoteButton();

  // Set up settings handlers
  setupSettings();

  // Load stored settings
  await loadStoredSettings();

  // Check auth status on load
  await checkAuthStatus();

  // Track app open event (after auth check so we have user info if available)
  trackAppOpen();

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

  // Clear slide info
  window.title = '';

  // Reset slide data
  currentSlideData = null;
  manualNotes = '';

  // Stop and reset all timers
  stopAllTimers();
  timerState = 'stopped';

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
  if (timerState === 'running') return;

  trackTimerAction('start');
  timerState = 'running';
  updateTimerButtonVisibility();

  // Get timestamps based on current view
  let timestamps;
  if (currentView === 'add-notes') {
    // In add-notes view, get timestamps from the highlight preview
    timestamps = notesInputHighlight.querySelectorAll('.timestamp[data-time]');
  } else {
    // In notes view, get timestamps from the content display
    timestamps = document.querySelectorAll('.timestamp[data-time]');
  }

  timestamps.forEach((timestamp, index) => {
    // Get current remaining time from data attribute
    let remainingSeconds = parseInt(timestamp.getAttribute('data-remaining') || timestamp.getAttribute('data-time'));

    // Update the timer every second
    const interval = setInterval(() => {
      if (timerState !== 'running') {
        clearInterval(interval);
        return;
      }

      remainingSeconds--;
      timestamp.setAttribute('data-remaining', remainingSeconds);

      const minutes = Math.floor(Math.abs(remainingSeconds) / 60);
      const seconds = Math.abs(remainingSeconds) % 60;
      const displayTime = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;

      // Update the display
      if (remainingSeconds < 0) {
        timestamp.textContent = `[-${displayTime}]`;
        timestamp.classList.add('time-overtime');
        timestamp.classList.remove('time-warning');
      } else if (remainingSeconds < 10) {
        timestamp.textContent = `[${displayTime}]`;
        timestamp.classList.add('time-warning');
        timestamp.classList.remove('time-overtime');
      } else {
        timestamp.textContent = `[${displayTime}]`;
        timestamp.classList.remove('time-warning', 'time-overtime');
      }
    }, 1000);

    timerIntervals.push(interval);
  });
}

// Pause timer countdown
function pauseTimerCountdown() {
  if (timerState !== 'running') return;

  trackTimerAction('pause');
  timerState = 'paused';
  stopAllTimers();
  updateTimerButtonVisibility();
}

// Reset timer countdown to original values
function resetTimerCountdown() {
  trackTimerAction('reset');
  stopAllTimers();
  timerState = 'stopped';

  // Get timestamps based on current view
  let timestamps;
  if (currentView === 'add-notes') {
    timestamps = notesInputHighlight.querySelectorAll('.timestamp[data-time]');
  } else {
    timestamps = document.querySelectorAll('.timestamp[data-time]');
  }

  timestamps.forEach((timestamp) => {
    const originalTime = parseInt(timestamp.getAttribute('data-time'));
    timestamp.setAttribute('data-remaining', originalTime);

    const minutes = Math.floor(originalTime / 60);
    const seconds = originalTime % 60;
    const displayTime = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;

    timestamp.textContent = `[${displayTime}]`;
    timestamp.classList.remove('time-warning', 'time-overtime');
  });

  updateTimerButtonVisibility();
}

// Stop all running timer intervals
function stopAllTimers() {
  timerIntervals.forEach(interval => clearInterval(interval));
  timerIntervals = [];
}

// Check if text contains [time mm:ss] pattern
function hasTimePattern(text) {
  const timePattern = /\[time\s+(\d{1,2}):(\d{2})\]/i;
  return timePattern.test(text);
}

// Update timer button visibility based on state
function updateTimerButtonVisibility() {
  if (!btnStart || !btnPause || !btnReset) return;

  // Determine if we should show timer controls
  // Show only if text contains [time mm:ss] pattern
  let shouldShowTimers = false;

  if (currentView === 'add-notes') {
    // Check if input text has time pattern AND we're not in edit mode
    shouldShowTimers = notesInput.value.trim() && hasTimePattern(notesInput.value) && !isEditMode;
  } else if (currentView === 'notes') {
    // Check if notes content has time pattern
    shouldShowTimers = currentSlideData && notesContent.querySelector('.timestamp[data-time]') !== null;
  }

  // Show timer controls only when there's content with time pattern
  if (shouldShowTimers) {
    // Show appropriate buttons and separators based on timer state
    switch (timerState) {
      case 'stopped':
        // Initial state: show Start only
        btnStart.classList.remove('hidden');
        timerStartSeparator.classList.remove('hidden');
        btnPause.classList.add('hidden');
        timerPauseSeparator.classList.add('hidden');
        btnReset.classList.add('hidden');
        timerSeparator.classList.add('hidden');
        break;
      case 'running':
        // Running: show Pause and Reset
        btnStart.classList.add('hidden');
        timerStartSeparator.classList.add('hidden');
        btnPause.classList.remove('hidden');
        timerPauseSeparator.classList.remove('hidden');
        btnReset.classList.remove('hidden');
        timerSeparator.classList.remove('hidden');
        break;
      case 'paused':
        // Paused: show Start and Reset
        btnStart.classList.remove('hidden');
        timerStartSeparator.classList.remove('hidden');
        btnPause.classList.add('hidden');
        timerPauseSeparator.classList.add('hidden');
        btnReset.classList.remove('hidden');
        timerSeparator.classList.remove('hidden');
        break;
    }
  } else {
    // Hide all timer controls
    btnStart.classList.add('hidden');
    timerStartSeparator.classList.add('hidden');
    btnPause.classList.add('hidden');
    timerPauseSeparator.classList.add('hidden');
    btnReset.classList.add('hidden');
    timerSeparator.classList.add('hidden');
  }
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
      // Update timer button visibility when content changes
      updateTimerButtonVisibility();
      // Update edit note button visibility when content changes
      updateEditNoteButtonVisibility();
      return;
    }

    // Apply the same highlighting as in displayNotes
    const highlighted = highlightNotesForInput(text);
    notesInputHighlight.innerHTML = highlighted;

    // Initialize timer data attributes for the preview
    initializeTimerDataAttributesForInput();

    // Update timer button visibility when content changes
    updateTimerButtonVisibility();
    // Update edit note button visibility when content changes
    updateEditNoteButtonVisibility();
  }

  // Listen for input changes
  notesInput.addEventListener('input', updateHighlight);
  notesInput.addEventListener('scroll', () => {
    // Sync scroll position
    notesInputHighlight.scrollTop = notesInput.scrollTop;
  });

  // Initial update if there's already content
  updateHighlight();
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

  // Reset timer when toggling edit/done
  resetTimerCountdown();
}

// Update edit note button visibility
function updateEditNoteButtonVisibility() {
  if (!editNoteBtn || !editNoteSeparator) return;

  const hasContent = notesInput.value.trim();

  // Only show button in add-notes view when there's content
  if (currentView === 'add-notes' && hasContent) {
    editNoteBtn.classList.remove('hidden');
    editNoteSeparator.classList.remove('hidden');

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
    editNoteSeparator.classList.add('hidden');

    // Reset to edit mode when content is cleared
    if (!hasContent) {
      isEditMode = true;
      notesInputWrapper.classList.add('edit-mode');
      notesInput.readOnly = false;
    }
  }
}

// Highlight notes for input preview (without timers)
function highlightNotesForInput(text) {
  // Normalize all line break types to \n first
  let safe = text
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .replace(/\u2028/g, '\n')
    .replace(/\u2029/g, '\n')
    .replace(/\v/g, '\n');

  // Escape HTML
  safe = escapeHtml(safe);

  let cumulativeTime = 0; // Track cumulative time in seconds

  // Pattern for [time mm:ss] syntax
  const timePattern = /\[time\s+(\d{1,2}):(\d{2})\]/gi;

  // Pattern for [note ...] syntax
  const notePattern = /\[note\s+([^\]]+)\]/gi;

  // Replace [time mm:ss]
  safe = safe.replace(timePattern, (match, minutes, seconds) => {
    const timeInSeconds = parseInt(minutes) * 60 + parseInt(seconds);
    cumulativeTime += timeInSeconds;

    const displayMinutes = Math.floor(cumulativeTime / 60);
    const displaySeconds = cumulativeTime % 60;
    const displayTime = `${String(displayMinutes).padStart(2, '0')}:${String(displaySeconds).padStart(2, '0')}`;

    return `<span class="timestamp" data-time="${cumulativeTime}">[${displayTime}]</span>`;
  });

  // Replace [note ...]
  safe = safe.replace(notePattern, (match, note) => {
    return `<span class="action-tag">[${note}]</span>`;
  });

  // Convert line breaks
  safe = safe.replace(/\n/g, '<br>');

  return safe;
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
    welcomeHeading.innerHTML = 'CueCard\n<span class="version-text">1.1.3</span>';

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

  // Show/hide the back button in footer based on view
  if (viewName === 'add-notes' || viewName === 'notes' || viewName === 'settings') {
    linkGoBack.classList.remove('hidden');
    backSeparator.classList.remove('hidden');
  } else {
    linkGoBack.classList.add('hidden');
    backSeparator.classList.add('hidden');
  }

  // Show settings link and separator
  settingsLink.classList.remove('hidden');
  settingsSeparator.classList.remove('hidden');

  if (btnClose && appHeaderTitle) {
    const isSettingsView = viewName === 'settings';
    btnClose.classList.toggle('hidden', isSettingsView);
    appHeaderTitle.classList.toggle('hidden', !isSettingsView);
  }

  // Show/hide privacy, website, and settings links based on view
  if (viewName === 'initial') {
    // Initial view: show Visit Site, Settings
    websiteLink.classList.remove('hidden');
    websiteSeparator.classList.add('hidden');
    supportLink.classList.add('hidden');
    supportSeparator.classList.add('hidden');
    bugLink.classList.add('hidden');
  } else if (viewName === 'settings') {
    // Settings view: show Support, Report Bug (no Settings button or Visit Site)
    websiteLink.classList.add('hidden');
    websiteSeparator.classList.add('hidden');
    supportLink.classList.remove('hidden');
    supportSeparator.classList.remove('hidden');
    bugLink.classList.remove('hidden');
    settingsLink.classList.add('hidden');
    settingsSeparator.classList.add('hidden');
  } else {
    // Notes and Add-Notes views: hide all footer links except go back
    websiteLink.classList.add('hidden');
    websiteSeparator.classList.add('hidden');
    supportLink.classList.add('hidden');
    supportSeparator.classList.add('hidden');
    bugLink.classList.add('hidden');
  }

  // Show/hide slide info and refresh button based on view and slide data
  if (viewName === 'notes' && currentSlideData) {
    refreshBtn.classList.remove('hidden');
    refreshSeparator.classList.remove('hidden');
  } else {
    refreshBtn.classList.add('hidden');
    refreshSeparator.classList.add('hidden');
  }

  // Update timer button visibility
  updateTimerButtonVisibility();

  // Update edit note button visibility
  updateEditNoteButtonVisibility();

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
      // In add-notes view, timer waits for Start button
      // Don't auto-start
      break;
    case 'notes':
      viewNotes.classList.remove('hidden');
      // In notes view, timer starts automatically if slide is present
      // But don't auto-start if we're coming back from settings (preserve timer state)
      if (timerState === 'stopped' && currentSlideData && previousView !== 'settings') {
        startTimerCountdown();
      }
      break;
    case 'settings':
      viewSettings.classList.remove('hidden');
      // Load current settings when showing settings view
      loadCurrentSettings();
      break;
  }
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
      refreshSeparator.classList.remove('hidden');
    }
  } else {
    window.title = 'No Slide Open';

    // Hide slide info and refresh button when no slide
    refreshBtn.classList.add('hidden');
    refreshSeparator.classList.add('hidden');
  }

  // Initialize timer data attributes but don't start
  // Timer start is controlled by buttons or view logic
  initializeTimerDataAttributes();

  // Update timer button visibility
  updateTimerButtonVisibility();
}

// Highlight timestamps and action tags in notes
function highlightNotes(text) {

  // Normalize all line break types to \n first
  // Handles: \r\n (Windows), \r (old Mac), \n (Unix), 
  // \u2028 (Line Separator), \u2029 (Paragraph Separator), \v (Vertical Tab)
  let safe = text
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .replace(/\u2028/g, '\n')
    .replace(/\u2029/g, '\n')
    .replace(/\v/g, '\n');

  // Escape HTML
  safe = escapeHtml(safe);

  let cumulativeTime = 0; // Track cumulative time in seconds

  // Pattern for [time mm:ss] syntax - marks the START of the next block
  const timePattern = /\[time\s+(\d{1,2}):(\d{2})\]/gi;

  // Pattern for [note ...] syntax - matches anything between [note and ]
  const notePattern = /\[note\s+([^\]]+)\]/gi;

  // Pattern for "Google Slides" - replace with link
  const slidesPattern = /Google Slides/gi;

  // Pattern for "CueCard Extension" - replace with link
  const cuecardPattern = /CueCard Extension/gi;

  // Replace [time mm:ss] - add line break BEFORE it, time starts a new line
  safe = safe.replace(timePattern, (match, minutes, seconds) => {
    const timeInSeconds = parseInt(minutes) * 60 + parseInt(seconds);
    cumulativeTime += timeInSeconds;

    const displayMinutes = Math.floor(cumulativeTime / 60);
    const displaySeconds = cumulativeTime % 60;
    const displayTime = `${String(displayMinutes).padStart(2, '0')}:${String(displaySeconds).padStart(2, '0')}`;

    return `<span class="timestamp" data-time="${cumulativeTime}">[${displayTime}]</span>`;
  });

  // Replace [note ...] with [...] inline (pink)
  safe = safe.replace(notePattern, (match, note) => {
    return `<span class="action-tag">[${note}]</span>`;
  });

  // Replace "Google Slides" with link
  // safe = safe.replace(slidesPattern, (match) => {
  //   return `<a href="https://slides.google.com" class="slides-link" id="slides-link" target="_blank" rel="noopener noreferrer">${match}</a>`;
  // });

  // Replace "CueCard Extension" with link
  safe = safe.replace(cuecardPattern, (match) => {
    return `<a href="https://cuecard.dev/#download" class="slides-link" id="slides-link" target="_blank" rel="noopener noreferrer">${match}</a>`;
  });

  // Convert line breaks
  safe = safe.replace(/\n/g, '<br>');

  return safe;
}

// Initialize timer data attributes for timestamps (without starting countdown)
function initializeTimerDataAttributes() {
  const timestamps = document.querySelectorAll('.timestamp[data-time]');

  timestamps.forEach(timestamp => {
    const totalSeconds = parseInt(timestamp.getAttribute('data-time'));
    // Set initial remaining time equal to total time
    timestamp.setAttribute('data-remaining', totalSeconds);
  });
}

// Initialize timer data attributes for timestamps in input preview
function initializeTimerDataAttributesForInput() {
  const timestamps = notesInputHighlight.querySelectorAll('.timestamp[data-time]');

  timestamps.forEach(timestamp => {
    const totalSeconds = parseInt(timestamp.getAttribute('data-time'));
    // Set initial remaining time equal to total time
    timestamp.setAttribute('data-remaining', totalSeconds);
  });
}

// Escape HTML to prevent XSS
function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
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
    trackScreenView('settings');
    showView('settings');
  });
}

// =============================================================================
// SETTINGS MANAGEMENT
// =============================================================================

// Default settings values
const DEFAULT_OPACITY = 100;
const DEFAULT_SHOW_IN_SCREENSHOT = false; // false = hidden from screenshots
const DEFAULT_LIGHT_MODE = false;

function applyTheme(isLight) {
  document.documentElement.classList.toggle('theme-light', isLight);
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

  // Load stored show in screenshot setting or use default
  const storedShowInScreenshot = await getStoredValue(STORAGE_KEYS.SETTINGS_SHOW_IN_SCREENSHOT);
  if (storedShowInScreenshot !== null && storedShowInScreenshot !== undefined) {
    showInScreenshot = storedShowInScreenshot;
  } else {
    showInScreenshot = DEFAULT_SHOW_IN_SCREENSHOT;
    await setStoredValue(STORAGE_KEYS.SETTINGS_SHOW_IN_SCREENSHOT, DEFAULT_SHOW_IN_SCREENSHOT);
  }
  updateGhostModeIndicator();
  // Apply screenshot protection via Rust (protection = !showInScreenshot)
  if (invoke) {
    try {
      await invoke("set_screenshot_protection", { enabled: !showInScreenshot });
    } catch (error) {
      console.error("Error applying screenshot protection:", error);
    }
  }

  // Load stored light mode setting or use default
  const storedLightMode = await getStoredValue(STORAGE_KEYS.SETTINGS_LIGHT_MODE);
  if (storedLightMode !== null && storedLightMode !== undefined) {
    isLightMode = storedLightMode;
  } else {
    isLightMode = DEFAULT_LIGHT_MODE;
    await setStoredValue(STORAGE_KEYS.SETTINGS_LIGHT_MODE, DEFAULT_LIGHT_MODE);
  }
  applyTheme(isLightMode);
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

  // Screen capture toggle handler
  if (screenCaptureToggle) {
    screenCaptureToggle.addEventListener("change", async (e) => {
      showInScreenshot = e.target.checked;
      updateGhostModeIndicator();

      // Track setting change
      trackSettingChange('ghost_mode', !showInScreenshot);

      // Update screenshot protection via Tauri (protection = !showInScreenshot)
      if (invoke) {
        try {
          await invoke("set_screenshot_protection", { enabled: !showInScreenshot });
        } catch (error) {
          console.error("Error setting screenshot protection:", error);
        }
      }

      // Save to persistent storage
      await setStoredValue(STORAGE_KEYS.SETTINGS_SHOW_IN_SCREENSHOT, showInScreenshot);
    });
  }

  if (lightModeToggle) {
    lightModeToggle.addEventListener("change", async (e) => {
      isLightMode = e.target.checked;
      applyTheme(isLightMode);

      // Track setting change
      trackSettingChange('light_mode', isLightMode);

      // Save to persistent storage
      await setStoredValue(STORAGE_KEYS.SETTINGS_LIGHT_MODE, isLightMode);
    });
  }
}

function updateGhostModeIndicator() {
  if (!ghostModeIndicator) return;
  const ghostModeOn = !showInScreenshot;
  ghostModeIndicator.textContent = `Ghost Mode: ${ghostModeOn ? 'On' : 'Off'}`;
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

  // Screen capture toggle: checkbox reflects showInScreenshot directly
  if (screenCaptureToggle) {
    screenCaptureToggle.checked = showInScreenshot;
  }
  updateGhostModeIndicator();

  if (lightModeToggle) {
    lightModeToggle.checked = isLightMode;
  }
}
