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
  SETTINGS_SHORTCUTS_ENABLED: 'settings_shortcuts_enabled',
  SETTINGS_AUTO_SCROLL_SPEED: 'settings_auto_scroll_speed',
  ADD_NOTES_CONTENT: 'add_notes_content',
  SAVED_NOTES: 'saved_notes'
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

// =============================================================================
// SAVED NOTES LIST MANAGEMENT
// =============================================================================

// Get all saved notes from storage
async function getSavedNotes() {
  const savedNotes = await getStoredValue(STORAGE_KEYS.SAVED_NOTES);
  return savedNotes || [];
}

// Save current note to the saved notes list
async function saveNoteToList() {
  if (!notesInput || !notesInput.value.trim()) return;

  const content = notesInput.value;
  const now = new Date().toISOString();

  const savedNotes = await getSavedNotes();

  // Check if we're updating an existing note
  if (currentNoteId) {
    const existingIndex = savedNotes.findIndex(n => n.id === currentNoteId);
    if (existingIndex !== -1) {
      // Update existing note
      savedNotes[existingIndex].content = content;
      savedNotes[existingIndex].updatedAt = now;

      // Move to beginning of list (most recently updated)
      const updatedNote = savedNotes.splice(existingIndex, 1)[0];
      savedNotes.unshift(updatedNote);

      await setStoredValue(STORAGE_KEYS.SAVED_NOTES, savedNotes);
      console.log("Note updated in list");
      return;
    }
  }

  // Create new note object with unique id
  const newNote = {
    id: Date.now().toString(),
    content: content,
    updatedAt: now
  };

  // Set the current note ID to the new note
  currentNoteId = newNote.id;

  // Add to beginning of list (most recent first)
  savedNotes.unshift(newNote);

  await setStoredValue(STORAGE_KEYS.SAVED_NOTES, savedNotes);
  console.log("Note saved to list");
}

// Load a note from the saved notes list (updates the time)
async function loadNoteFromList(noteId) {
  const savedNotes = await getSavedNotes();
  const noteIndex = savedNotes.findIndex(n => n.id === noteId);

  if (noteIndex === -1) return;

  const note = savedNotes[noteIndex];

  // Set current note ID for future updates
  currentNoteId = note.id;

  // Update the updatedAt time
  note.updatedAt = new Date().toISOString();

  // Move to beginning of list (most recently used)
  savedNotes.splice(noteIndex, 1);
  savedNotes.unshift(note);

  await setStoredValue(STORAGE_KEYS.SAVED_NOTES, savedNotes);

  // Load the note into the input
  notesInput.value = note.content;

  // Also update the current notes storage
  await setStoredValue(STORAGE_KEYS.ADD_NOTES_CONTENT, note.content);

  // Trigger the highlight update
  if (notesInputHighlight) {
    const event = new Event('input', { bubbles: true });
    notesInput.dispatchEvent(event);
  }

  console.log("Note loaded from list");

  // Navigate to add-notes view
  showView('add-notes');

  // Set to done mode (readonly, highlighted)
  isEditMode = false;
  notesInputWrapper.classList.remove('edit-mode');
  notesInput.readOnly = true;
  editNoteBtn.textContent = 'Edit Note';

  // Update button visibility
  updateEditNoteButtonVisibility();
  updateTimerButtonVisibility();
}

// Delete a note from the saved notes list
async function deleteNoteFromList(noteId) {
  const savedNotes = await getSavedNotes();
  const filteredNotes = savedNotes.filter(n => n.id !== noteId);

  await setStoredValue(STORAGE_KEYS.SAVED_NOTES, filteredNotes);
  console.log("Note deleted from list");

  // Re-render the list
  renderSavedNotesList();
}

// Get first line of note content for preview
function getFirstLinePreview(content) {
  if (!content) return '';

  // Split by newlines and find first non-empty line after stripping tags
  const lines = content.split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed) {
      // Remove any [time] or [note] tags for cleaner preview
      const cleaned = trimmed
        .replace(/\[time\s+\d{1,2}:\d{2}\]/gi, '')
        .replace(/\[note\s+[^\]]+\]/gi, '')
        .trim();
      // If line has actual content after stripping tags, use it
      if (cleaned) {
        return cleaned;
      }
      // Otherwise continue to next line
    }
  }
  // Fallback: strip tags from entire content and take first 50 chars
  const fallback = content
    .replace(/\[time\s+\d{1,2}:\d{2}\]/gi, '')
    .replace(/\[note\s+[^\]]+\]/gi, '')
    .trim();
  return fallback.substring(0, 50) || 'Untitled Note';
}

// Format date for display
function formatNoteDate(isoString) {
  const date = new Date(isoString);
  const now = new Date();
  const diffMs = now - date;
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;

  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

// Render the saved notes list in the view
async function renderSavedNotesList() {
  if (!savedNotesList || !savedNotesEmpty) return;

  const savedNotes = await getSavedNotes();

  if (savedNotes.length === 0) {
    savedNotesList.classList.add('hidden');
    savedNotesEmpty.classList.remove('hidden');
    return;
  }

  savedNotesList.classList.remove('hidden');
  savedNotesEmpty.classList.add('hidden');

  savedNotesList.innerHTML = savedNotes.map(note => `
    <div class="saved-note-item" data-note-id="${note.id}">
      <div class="saved-note-info">
        <span class="saved-note-preview">${escapeHtml(getFirstLinePreview(note.content))}</span>
        <span class="saved-note-time">${formatNoteDate(note.updatedAt)}</span>
      </div>
      <button class="saved-note-delete" data-note-id="${note.id}">Delete</button>
    </div>
  `).join('');

  // Add click handlers
  savedNotesList.querySelectorAll('.saved-note-item').forEach(item => {
    item.addEventListener('click', (e) => {
      // Don't load if clicking delete button
      if (e.target.classList.contains('saved-note-delete')) return;

      const noteId = item.dataset.noteId;
      loadNoteFromList(noteId);
    });
  });

  // Add delete handlers
  savedNotesList.querySelectorAll('.saved-note-delete').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const noteId = btn.dataset.noteId;
      deleteNoteFromList(noteId);
    });
  });
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
let btnClose, btnDownloadUpdates, downloadUpdatesSeparator, btnSignOut;
let authBtn;
let appContainer, appHeader, appHeaderTitle, viewInitial, viewAddNotes, viewNotes, viewSettings, viewShortcuts, viewSavedNotes;
let linkGoBack;
let notesInput, notesContent;
let welcomeHeading, welcomeSubtext, welcomeActions;
let bugLink, websiteLink, supportLink;
let settingsLink;
let shortcutsLink;
let refreshBtn;
let notesInputHighlight;
let btnStart, btnPause, btnReset;
let opacitySlider, opacityValue, ghostModeToggle, shortcutsToggle;
let themeSystemBtn, themeLightBtn, themeDarkBtn;
let speedSlider, speedValue;
let editNoteBtn;
let notesInputWrapper;
let ghostModeIndicator;
let headerTimer;
let savedNotesList, savedNotesEmpty;

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
let shortcutsEnabled = true; // Default: true = global shortcuts are enabled
let autoScrollSpeed = 0; // 0 to 2 (pixels per frame at 60fps), 0 = off

// Timer State
let timerState = 'stopped'; // 'stopped', 'running', 'paused'
let timerIntervals = []; // Store all timer interval IDs
let autoScrollAnimationId = null; // Store auto-scroll animation frame ID
let autoScrollAccumulator = 0; // Accumulator for sub-pixel scrolling
let autoScrollPausedByHover = false; // Tracks if auto-scroll is paused due to hover
let totalTimeSeconds = 0; // Total time from all [time] tags
let remainingTimeSeconds = 0; // Current remaining time for countdown

// Notes metadata
let notesHasTimeTags = false;

// Edit Mode State
let isEditMode = false; // false = done mode (readonly, highlighted), true = edit mode (editable, not highlighted)
let currentNoteId = null; // Track the ID of the currently loaded note for updates

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
  btnSignOut = document.getElementById("btn-signout");
  authBtn = document.getElementById("auth-btn");
  appContainer = document.querySelector(".app-container");
  appHeader = document.querySelector(".app-header");
  appHeaderTitle = document.getElementById("app-header-title");
  viewInitial = document.getElementById("view-initial");
  viewAddNotes = document.getElementById("view-add-notes");
  viewNotes = document.getElementById("view-notes");
  viewSettings = document.getElementById("view-settings");
  viewShortcuts = document.getElementById("view-shortcuts");
  viewSavedNotes = document.getElementById("view-saved-notes");
  linkGoBack = document.getElementById("link-go-back");
  notesInput = document.getElementById("notes-input");
  notesContent = document.getElementById("notes-content");
  welcomeHeading = document.getElementById("welcome-heading");
  welcomeSubtext = document.getElementById("welcome-subtext");
  welcomeActions = document.getElementById("welcome-actions");
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
  shortcutsToggle = document.getElementById("shortcuts-toggle");
  themeSystemBtn = document.getElementById("theme-system");
  themeLightBtn = document.getElementById("theme-light");
  themeDarkBtn = document.getElementById("theme-dark");
  speedSlider = document.getElementById("speed-slider");
  speedValue = document.getElementById("speed-value");
  editNoteBtn = document.getElementById("edit-note-btn");
  notesInputWrapper = document.querySelector(".notes-input-wrapper");
  ghostModeIndicator = document.getElementById("ghost-mode-indicator");
  headerTimer = document.getElementById("header-timer");
  savedNotesList = document.getElementById("saved-notes-list");
  savedNotesEmpty = document.getElementById("saved-notes-empty");

  // Set up navigation handlers
  setupNavigation();

  // Set up auth handlers
  setupAuth();

  // Set up welcome action handlers
  setupWelcomeActions();

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

  // Set up auto-scroll hover listeners
  setupAutoScrollHoverListeners();

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

    if (currentView === 'saved-notes') {
      showView('initial');
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

  // Reset current note ID
  currentNoteId = null;

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

  if (btnSignOut) {
    btnSignOut.addEventListener("click", async (e) => {
      e.preventDefault();
      e.stopPropagation();
      if (!isAuthenticated) return;
      trackLogout();
      await handleLogout();
    });
  }
}

// Welcome Actions (New Note / Load Note / Slides)
function setupWelcomeActions() {
  const pasteNotesLink = document.getElementById('paste-notes-link');
  if (pasteNotesLink) {
    pasteNotesLink.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      trackNotesPaste();
      // Clear current note ID for new note
      currentNoteId = null;
      // Clear any existing notes for a fresh start
      if (notesInput) {
        notesInput.value = '';
        if (notesInputHighlight) {
          notesInputHighlight.innerHTML = '';
        }
      }
      // Clear stored notes
      setStoredValue(STORAGE_KEYS.ADD_NOTES_CONTENT, '');
      // Reset timer state for new note
      stopAllTimers();
      timerState = 'stopped';
      totalTimeSeconds = 0;
      remainingTimeSeconds = 0;
      if (headerTimer) {
        headerTimer.textContent = '00:00';
        headerTimer.classList.remove('time-warning', 'time-overtime');
        headerTimer.classList.add('time-countup');
      }
      showView('add-notes');
      // Start in edit mode for new note
      isEditMode = true;
      notesInputWrapper.classList.add('edit-mode');
      notesInput.readOnly = false;
      editNoteBtn.textContent = 'Done';
      notesInput.focus();
    });
  }

  const loadNotesLink = document.getElementById('load-notes-link');
  if (loadNotesLink) {
    loadNotesLink.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      showView('saved-notes');
    });
  }

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
        displayNotes('Open a Google Slides presentation to see notes here.\n[note Install CueCard Extension to sync notes]');
        window.title = 'No Slide Open';
        showView('notes');
      }
    });
  }
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

  // Start auto-scroll if enabled
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
      headerTimer.classList.remove('time-countup');
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
      // Count up mode (no [time] tags) - white color
      elapsedSeconds++;
      const minutes = Math.floor(elapsedSeconds / 60);
      const seconds = elapsedSeconds % 60;
      const displayTime = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
      headerTimer.textContent = displayTime;
      headerTimer.classList.remove('time-warning', 'time-overtime');
      headerTimer.classList.add('time-countup');
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
  stopAutoScroll();
  updateTimerButtonVisibility();
}

// Reset timer countdown to original values
function resetTimerCountdown() {
  trackTimerAction('reset');
  stopAllTimers();
  stopAutoScroll();
  timerState = 'stopped';

  // Reset scroll position to top
  const container = getScrollContainer();
  if (container) {
    container.scrollTop = 0;
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
    // Use count-up styling (white) when no [time] tags
    headerTimer.classList.toggle('time-countup', totalTimeSeconds === 0);
  }

  updateTimerButtonVisibility();
}

// Stop all running timer intervals
function stopAllTimers() {
  timerIntervals.forEach(interval => clearInterval(interval));
  timerIntervals = [];
}

// =============================================================================
// SCROLL HELPERS
// =============================================================================

function getScrollContainer() {
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

// Start auto-scroll animation
function startAutoScroll() {
  if (autoScrollSpeed <= 0 || autoScrollAnimationId !== null) return;

  const container = getScrollContainer();
  if (!container) return;
  const maxScroll = container.scrollHeight - container.clientHeight;
  if (maxScroll <= 0) {
    autoScrollAccumulator = 0;
    return;
  }

  const speed = autoScrollSpeed;

  // Reset accumulator when starting
  autoScrollAccumulator = 0;

  function scrollStep() {
    if (timerState !== 'running' || autoScrollSpeed <= 0) {
      stopAutoScroll();
      return;
    }

    // Skip scrolling if paused by hover, but keep the animation loop running
    if (!autoScrollPausedByHover) {
      const container = getScrollContainer();
      if (container) {
        const maxScroll = container.scrollHeight - container.clientHeight;
        if (maxScroll <= 0) {
          stopAutoScroll();
          return;
        }
        if (container.scrollTop < maxScroll) {
          // Accumulate fractional scroll values
          autoScrollAccumulator += speed;
          // Only update scrollTop when we have at least 1 pixel to scroll
          if (autoScrollAccumulator >= 1) {
            const pixelsToScroll = Math.floor(autoScrollAccumulator);
            container.scrollTop += pixelsToScroll;
            autoScrollAccumulator -= pixelsToScroll;
          }
        }
      }
    }

    autoScrollAnimationId = requestAnimationFrame(scrollStep);
  }

  autoScrollAnimationId = requestAnimationFrame(scrollStep);
}

// Stop auto-scroll animation
function stopAutoScroll() {
  if (autoScrollAnimationId !== null) {
    cancelAnimationFrame(autoScrollAnimationId);
    autoScrollAnimationId = null;
  }
  autoScrollAccumulator = 0;
  autoScrollPausedByHover = false;
}

// Setup hover listeners to pause auto-scroll
function setupAutoScrollHoverListeners() {
  const containers = [notesInputHighlight, notesContent];

  containers.forEach(container => {
    if (!container) return;

    container.addEventListener('mouseenter', () => {
      autoScrollPausedByHover = true;
    });

    container.addEventListener('mouseleave', () => {
      autoScrollPausedByHover = false;
    });
  });
}

// Check if text contains [time mm:ss] pattern
function hasTimePattern(text) {
  const timePattern = /\[time\s+(\d{1,2}):(\d{2})\]/i;
  return timePattern.test(text);
}

// Update header timer visibility based on view (shown in notes views for both countdown and count-up)
function updateHeaderTimerVisibility() {
  if (!headerTimer) return;
  const isNotesView = currentView === 'add-notes' || currentView === 'notes';
  headerTimer.classList.toggle('hidden', !isNotesView);
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
  // Show when there's content, even without [time] tags
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
async function toggleEditMode() {
  isEditMode = !isEditMode;

  if (isEditMode) {
    // Edit mode: input is editable, not highlighted
    trackEditAction('edit');
    notesInputWrapper.classList.add('edit-mode');
    notesInput.readOnly = false;
    editNoteBtn.textContent = 'Done';
    notesInput.focus();
  } else {
    // Done mode: input is readonly, highlighted
    trackEditAction('save');
    notesInputWrapper.classList.remove('edit-mode');
    notesInput.readOnly = true;
    editNoteBtn.textContent = 'Edit Note';

    // Auto-save note when Done is pressed
    if (notesInput && notesInput.value.trim()) {
      await saveNoteToList();
    }
  }

  // Reset timer when toggling edit/done
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
      editNoteBtn.textContent = 'Done';
    } else {
      // Update button text based on current mode
      editNoteBtn.textContent = isEditMode ? 'Done' : 'Edit Note';
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
    // Use count-up styling (white) when no [time] tags
    headerTimer.classList.toggle('time-countup', cumulativeTime === 0);
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
    authBtn.classList.add('is-authenticated');
    authBtn.classList.add('hidden');
    if (btnSignOut) {
      const shouldShowSignOut = currentView !== 'notes' && currentView !== 'add-notes';
      btnSignOut.classList.toggle('hidden', !shouldShowSignOut);
    }

    // Update welcome heading with greeting and first name
    const firstName = getFirstName(name);
    const greeting = getGreeting();
    const versionSpan = welcomeHeading.querySelector('.version-text');
    const versionHTML = versionSpan ? versionSpan.outerHTML : '';
    welcomeHeading.innerHTML = `${greeting}, ${firstName}!${versionHTML ? '\n' + versionHTML : ''}`;

    // Update subtext and show quick actions
    welcomeSubtext.innerHTML = 'Create or open notes and speak with confidence.';
    if (welcomeActions) {
      welcomeActions.classList.remove('hidden');
    }
  } else {
    // Update button to show "Sign in"
    if (buttonText) buttonText.textContent = 'Sign in with Google';
    if (buttonIcon) buttonIcon.style.display = 'block';
    authBtn.classList.remove('is-authenticated');
    authBtn.classList.remove('hidden');
    if (btnSignOut) {
      btnSignOut.classList.add('hidden');
    }

    // Reset welcome heading to default
    welcomeHeading.innerHTML = 'CueCard\n<span class="version-text">1.4.1</span>';

    // Reset subtext
    welcomeSubtext.innerHTML = 'Speaker notes visible only to you during screen sharing — for <span class="highlight-presentations">presentations</span>, <span class="highlight-meetings">meetings</span>, or <span class="highlight-demos">live demos</span>.';
    if (welcomeActions) {
      welcomeActions.classList.add('hidden');
    }
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
      stopAutoScroll();
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
  viewSavedNotes.classList.add('hidden');

  // Show/hide the back button in footer based on view
  if (viewName === 'add-notes' || viewName === 'notes' || viewName === 'settings' || viewName === 'shortcuts' || viewName === 'saved-notes') {
    linkGoBack.classList.remove('hidden');
  } else {
    linkGoBack.classList.add('hidden');
  }

  // Show settings link (shortcuts visibility handled by updateShortcutsVisibility)
  settingsLink.classList.remove('hidden');

  if (btnClose && appHeaderTitle && headerTimer) {
    const isSettingsView = viewName === 'settings';
    const isShortcutsView = viewName === 'shortcuts';
    const isSavedNotesView = viewName === 'saved-notes';
    const isNotesView = viewName === 'add-notes' || viewName === 'notes';

    // Hide close button for settings, shortcuts, saved-notes and notes views, show only for initial view
    btnClose.classList.toggle('hidden', isSettingsView || isShortcutsView || isSavedNotesView || isNotesView);
    appHeaderTitle.classList.toggle('hidden', !isSettingsView && !isShortcutsView && !isSavedNotesView);

    // Update header title text
    if (isSettingsView) {
      appHeaderTitle.textContent = 'Settings';
    } else if (isShortcutsView) {
      appHeaderTitle.textContent = 'Shortcuts';
    } else if (isSavedNotesView) {
      appHeaderTitle.textContent = 'Saved Notes';
    }

    updateHeaderTimerVisibility();
  }

  if (ghostModeIndicator) {
    const shouldShowGhost = viewName === 'notes' || viewName === 'add-notes';
    ghostModeIndicator.classList.toggle('hidden', !shouldShowGhost);
  }
  if (btnSignOut) {
    const shouldShowSignOut = isAuthenticated && viewName !== 'notes' && viewName !== 'add-notes';
    btnSignOut.classList.toggle('hidden', !shouldShowSignOut);
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
  } else if (viewName === 'shortcuts') {
    // Shortcuts view: hide all footer links except go back
    websiteLink.classList.add('hidden');
    supportLink.classList.add('hidden');
    bugLink.classList.add('hidden');
    settingsLink.classList.add('hidden');
  } else if (viewName === 'saved-notes') {
    // Saved notes view: hide all footer links except go back
    websiteLink.classList.add('hidden');
    supportLink.classList.add('hidden');
    bugLink.classList.add('hidden');
    settingsLink.classList.add('hidden');
  } else {
    // Notes and Add-Notes views: hide all footer links except go back
    websiteLink.classList.add('hidden');
    supportLink.classList.add('hidden');
    bugLink.classList.add('hidden');
  }

  // Update shortcuts button visibility (respects both setting and current view)
  updateShortcutsVisibility();

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

  // Show the requested view
  switch (viewName) {
    case 'initial':
      viewInitial.classList.remove('hidden');
      break;
    case 'add-notes':
      viewAddNotes.classList.remove('hidden');
      // Load stored notes when entering add-notes view
      // But skip loading if coming back from settings or saved-notes (content is already there)
      if (previousView !== 'settings' && previousView !== 'saved-notes') {
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
        updateTimerButtonVisibility();
      }
      if (timerState === 'stopped' && currentSlideData && hasNotesContent && previousView !== 'settings') {
        startTimerCountdown();
      }
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
    case 'saved-notes':
      viewSavedNotes.classList.remove('hidden');
      // Render the saved notes list
      renderSavedNotesList();
      break;
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
  if (notesContent) {
    notesContent.scrollTop = 0;
  }
  if (currentView === 'notes' && timerState === 'running') {
    stopAutoScroll();
    startAutoScroll();
  }

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
    // Use count-up styling (white) when no [time] tags
    headerTimer.classList.toggle('time-countup', cumulativeTime === 0);
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
const DEFAULT_SHORTCUTS_ENABLED = true; // true = global shortcuts are enabled

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

  // Load stored shortcuts enabled setting or use default
  const storedShortcutsEnabled = await getStoredValue(STORAGE_KEYS.SETTINGS_SHORTCUTS_ENABLED);
  if (storedShortcutsEnabled !== null && storedShortcutsEnabled !== undefined) {
    shortcutsEnabled = storedShortcutsEnabled;
  } else {
    shortcutsEnabled = DEFAULT_SHORTCUTS_ENABLED;
    await setStoredValue(STORAGE_KEYS.SETTINGS_SHORTCUTS_ENABLED, DEFAULT_SHORTCUTS_ENABLED);
  }
  // Update shortcuts button visibility and register/unregister shortcuts
  updateShortcutsVisibility();
  if (invoke) {
    try {
      await invoke("set_shortcuts_enabled", { enabled: shortcutsEnabled });
    } catch (error) {
      console.error("Error setting shortcuts enabled:", error);
    }
  }

  // Load stored auto-scroll speed setting or use default (0 = off)
  const storedAutoScrollSpeed = await getStoredValue(STORAGE_KEYS.SETTINGS_AUTO_SCROLL_SPEED);
  if (storedAutoScrollSpeed !== null && storedAutoScrollSpeed !== undefined) {
    // Handle migration from old string values to new numeric values
    if (typeof storedAutoScrollSpeed === 'string') {
      const migrationMap = { 'off': 0, 'low': 0.5, 'medium': 1, 'high': 2 };
      autoScrollSpeed = migrationMap[storedAutoScrollSpeed] ?? 0;
      await setStoredValue(STORAGE_KEYS.SETTINGS_AUTO_SCROLL_SPEED, autoScrollSpeed);
    } else {
      autoScrollSpeed = storedAutoScrollSpeed;
    }
  } else {
    autoScrollSpeed = 0;
    await setStoredValue(STORAGE_KEYS.SETTINGS_AUTO_SCROLL_SPEED, 0);
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

  // Shortcuts toggle handler
  if (shortcutsToggle) {
    shortcutsToggle.addEventListener("change", async (e) => {
      shortcutsEnabled = e.target.checked;
      updateShortcutsVisibility();

      // Track setting change
      trackSettingChange('shortcuts_enabled', shortcutsEnabled);

      // Enable/disable shortcuts via Tauri
      if (invoke) {
        try {
          await invoke("set_shortcuts_enabled", { enabled: shortcutsEnabled });
        } catch (error) {
          console.error("Error setting shortcuts enabled:", error);
        }
      }

      // Save to persistent storage
      await setStoredValue(STORAGE_KEYS.SETTINGS_SHORTCUTS_ENABLED, shortcutsEnabled);
    });
  }

  // Auto-scroll speed slider handler
  let speedTrackingTimeout = null;
  if (speedSlider) {
    speedSlider.addEventListener("input", async (e) => {
      const value = parseFloat(e.target.value);
      autoScrollSpeed = value;
      updateSpeedDisplay(value);

      // Save to persistent storage
      await setStoredValue(STORAGE_KEYS.SETTINGS_AUTO_SCROLL_SPEED, value);

      // Debounce analytics tracking
      clearTimeout(speedTrackingTimeout);
      speedTrackingTimeout = setTimeout(() => {
        trackSettingChange('auto_scroll_speed', value);
      }, 500);

      // If timer is running and speed changed, restart or stop auto-scroll
      if (timerState === 'running') {
        stopAutoScroll();
        if (value > 0) {
          startAutoScroll();
        }
      }
    });
  }
}

// Update speed display value
function updateSpeedDisplay(speed) {
  if (!speedValue) return;
  if (speed === 0) {
    speedValue.textContent = 'Off';
  } else {
    speedValue.textContent = `${speed}x`;
  }
}

function updateGhostModeIndicator() {
  if (!ghostModeIndicator) return;
  ghostModeIndicator.textContent = `Ghost Mode ${ghostMode ? 'Enabled' : 'Disabled'}`;
}

// Update shortcuts button visibility based on shortcutsEnabled setting and current view
function updateShortcutsVisibility() {
  if (shortcutsLink) {
    // Hide shortcuts button if:
    // 1. Shortcuts are disabled, OR
    // 2. Current view is settings, shortcuts, or saved-notes
    const shouldHide = !shortcutsEnabled || currentView === 'settings' || currentView === 'shortcuts' || currentView === 'saved-notes';
    shortcutsLink.classList.toggle('hidden', shouldHide);
  }
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

  // Shortcuts toggle
  if (shortcutsToggle) {
    shortcutsToggle.checked = shortcutsEnabled;
  }

  // Update speed slider and display
  if (speedSlider) {
    speedSlider.value = autoScrollSpeed;
  }
  updateSpeedDisplay(autoScrollSpeed);
}

// =============================================================================
// GLOBAL SHORTCUTS
// =============================================================================

// Shortcut definitions with platform-specific display
// All shortcuts use Control+Option (Mac) / Control+Alt (Windows)
// Height adjustments add Shift modifier
const SHORTCUTS = {
  'toggle-visibility': { mac: ['Ctrl', 'Option', 'C'], win: ['Ctrl', 'Alt', 'C'] },
  'opacity-down': { mac: ['Ctrl', 'Option', '-'], win: ['Ctrl', 'Alt', '-'] },
  'opacity-up': { mac: ['Ctrl', 'Option', '='], win: ['Ctrl', 'Alt', '='] },
  'height-down': { mac: ['Shift', 'Ctrl', 'Option', '↑'], win: ['Shift', 'Ctrl', 'Alt', '↑'] },
  'height-up': { mac: ['Shift', 'Ctrl', 'Option', '↓'], win: ['Shift', 'Ctrl', 'Alt', '↓'] },
  'move-left': { mac: ['Ctrl', 'Option', '←'], win: ['Ctrl', 'Alt', '←'] },
  'move-right': { mac: ['Ctrl', 'Option', '→'], win: ['Ctrl', 'Alt', '→'] },
  'move-up': { mac: ['Ctrl', 'Option', '↑'], win: ['Ctrl', 'Alt', '↑'] },
  'move-down': { mac: ['Ctrl', 'Option', '↓'], win: ['Ctrl', 'Alt', '↓'] },
  'timer-toggle': { mac: ['Ctrl', 'Option', 'Space'], win: ['Ctrl', 'Alt', 'Space'] },
  'timer-reset': { mac: ['Ctrl', 'Option', '0'], win: ['Ctrl', 'Alt', '0'] },
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
  await setStoredValue(STORAGE_KEYS.SETTINGS_OPACITY, value);
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
