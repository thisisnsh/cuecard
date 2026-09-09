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

import {
  CUE_TAG_PREFIX,
  EMPTY_CUE_TAG,
  CUE_COLORS,
  DEFAULT_CUE_COLOR,
  cueColorVariable,
  cueMatches,
  cueTagContaining,
  emptyCueInsertion,
  emptyCueSurrounding,
  formatTime,
  withoutCues,
} from './parser.js';

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
  SETTINGS_LINES_PER_MINUTE: 'settings_lines_per_minute',
  SETTINGS_CUE_COLOR: 'settings_cue_color',
  SETTINGS_TIMER_MINUTES: 'settings_timer_minutes',
  SETTINGS_TIMER_SECONDS: 'settings_timer_seconds',
  SETTINGS_COUNTDOWN_SECONDS: 'settings_countdown_seconds',
  MIGRATED_TIME_TAGS: 'migrated_time_tags',
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

  dismissSheet();
  await showView('add-notes');

  // Set to done mode (readonly, highlighted)
  isEditMode = false;
  notesInputWrapper.classList.remove('edit-mode');
  notesInput.readOnly = true;
  editNoteBtn.textContent = 'Edit Note';

  // Update button visibility
  updateEditNoteButtonVisibility();
  updateTransport();
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
      // Strip the timing and the cues, so the preview is what gets said
      const cleaned = withoutCues(trimmed.replace(/\[time\s+\d{1,2}:\d{2}\]/gi, '')).trim();
      // If line has actual content after stripping tags, use it
      if (cleaned) {
        return cleaned;
      }
      // Otherwise continue to next line
    }
  }
  // Fallback: strip tags from entire content and take first 50 chars
  const fallback = withoutCues(content.replace(/\[time\s+\d{1,2}:\d{2}\]/gi, '')).trim();
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
let btnClose, btnDownloadUpdates;
let authBtn;
let appContainer, appToolbar, toolbarTitle, viewInitial, viewAddNotes, viewNotes;
let sheetBackdrop, sheets = {};
let btnMenu, appMenu, menuBadge, menuSeparatorNote, menuSeparatorAccount, btnSignOut, btnSavedNotes;
let notesInput, notesContent;
let welcomeHeading, welcomeSubtext, welcomeActions;
let bugLink, websiteLink, supportLink;
let settingsLink;
let shortcutsLink;
let refreshBtn;
let notesInputHighlight;
let btnPlay, btnRestart, iconPlay, iconPause;
let editorControls, timerControl, btnSetTimer, timerPicker, btnCloseTimerPicker;
let timerMinutesField, timerSecondsField;
let opacitySlider, opacityValue, ghostModeToggle, shortcutsToggle;
let cueColorSwatches;
let countdownField;
let themeSystemBtn, themeLightBtn, themeDarkBtn;
let speedField;
let editNoteBtn;
let notesInputWrapper;
let ghostModeIndicator;
let headerTimer;
let savedNotesList, savedNotesEmpty;

// State
let isAuthenticated = false;
let userName = '';
let currentView = 'initial'; // 'initial', 'add-notes', 'notes'
let currentSheet = null; // 'settings', 'shortcuts', 'saved-notes', or nothing
let manualNotes = ''; // Notes pasted by the user
let currentSlideData = null; // Store current slide data
let currentOpacity = 100; // Store current opacity value (10-100)
let ghostMode = true; // Default: true = hidden from screenshots (ghost mode ON)
let currentTheme = 'system'; // 'system', 'light', 'dark'
let shortcutsEnabled = true; // Default: true = global shortcuts are enabled
// Scroll speed, in lines of the script as the editor renders them. Zero is off,
// which iOS has no equivalent of but an always-on-top window wants.
let linesPerMinute = 0;
let cueColor = DEFAULT_CUE_COLOR; // the colour every cue in every script is drawn in

// Timer State
let timerState = 'stopped'; // 'stopped', 'running', 'paused'
let timerIntervals = []; // Store all timer interval IDs
let autoScrollAnimationId = null; // Store auto-scroll animation frame ID
let autoScrollHeldSeconds = 0; // Time spent hovering, which the script sits out
let autoScrollHeldSince = null;
let programmaticScrollTop = null; // The last scrollTop we set ourselves
let autoScrollPausedByHover = false; // Tracks if auto-scroll is paused due to hover
let timerMinutes = 1; // The run's length, set on the Set Timer pill
let timerSeconds = 0;
let elapsedSeconds = 0; // How far into the run we are; the clock everything reads
let countdownSeconds = 5; // Delay before the script starts moving
let countdownValue = 0; // What the delay is showing right now
let countdownInterval = null;
// Whether the run has begun since the last restart. The delay runs on the first
// play only; resuming from a pause starts straight away.
let hasStarted = false;

// Notes metadata

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
  authBtn = document.getElementById("auth-btn");
  appContainer = document.querySelector(".app-container");
  appToolbar = document.querySelector(".app-toolbar");
  toolbarTitle = document.getElementById("toolbar-title");
  btnMenu = document.getElementById("btn-menu");
  appMenu = document.getElementById("app-menu");
  menuBadge = document.getElementById("menu-badge");
  menuSeparatorNote = document.getElementById("menu-separator-note");
  menuSeparatorAccount = document.getElementById("menu-separator-account");
  btnSignOut = document.getElementById("btn-signout");
  btnSavedNotes = document.getElementById("btn-saved-notes");
  viewInitial = document.getElementById("view-initial");
  viewAddNotes = document.getElementById("view-add-notes");
  viewNotes = document.getElementById("view-notes");
  sheetBackdrop = document.getElementById("sheet-backdrop");
  sheets = {
    settings: document.getElementById("sheet-settings"),
    shortcuts: document.getElementById("sheet-shortcuts"),
    'saved-notes': document.getElementById("sheet-saved-notes"),
  };
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
  btnPlay = document.getElementById("btn-play");
  btnRestart = document.getElementById("btn-restart");
  iconPlay = btnPlay ? btnPlay.querySelector('.icon-play') : null;
  iconPause = btnPlay ? btnPlay.querySelector('.icon-pause') : null;
  editorControls = document.getElementById("editor-controls");
  timerControl = document.getElementById("timer-control");
  btnSetTimer = document.getElementById("btn-set-timer");
  timerPicker = document.getElementById("timer-picker");
  timerMinutesField = document.getElementById("timer-minutes");
  timerSecondsField = document.getElementById("timer-seconds");
  btnCloseTimerPicker = document.getElementById("btn-close-timer-picker");
  opacitySlider = document.getElementById("opacity-slider");
  opacityValue = document.getElementById("opacity-value");
  ghostModeToggle = document.getElementById("ghost-mode-toggle");
  shortcutsToggle = document.getElementById("shortcuts-toggle");
  cueColorSwatches = document.getElementById("cue-color-swatches");
  countdownField = document.getElementById("countdown-field");
  themeSystemBtn = document.getElementById("theme-system");
  themeLightBtn = document.getElementById("theme-light");
  themeDarkBtn = document.getElementById("theme-dark");
  speedField = document.getElementById("speed-field");
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

  // Set up the ellipsis menu and the links inside it
  setupMenu();

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

  // Check for existing slide data
  await checkCurrentSlide();

  // Open on the script, the way the phone app does. The welcome hero is for a
  // first run only: nobody signed in, and nothing ever written.
  await showView(await shouldShowWelcome() ? 'initial' : 'add-notes');

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
          displayNotes('Open a Google Slides presentation to see notes here.\n[cue Install CueCard Extension to sync notes]');
          window.title = 'No Slide Open';
          showView('notes');
        }
      }
    });
  }

  console.log("App initialization complete!");
});

// Whether this is a first run — the only time the welcome hero is what someone
// wants to see. Anyone who has signed in or written a script gets the editor.
async function shouldShowWelcome() {
  if (isAuthenticated) return false;
  const storedNotes = await getStoredValue(STORAGE_KEYS.ADD_NOTES_CONTENT);
  if (storedNotes && storedNotes.trim()) return false;
  const savedNotes = await getSavedNotes();
  return savedNotes.length === 0;
}

// =============================================================================
// NAVIGATION
// =============================================================================

// A sheet is dismissed with Done, with Escape, or by clicking behind it.
function setupNavigation() {
  document.querySelectorAll('[data-sheet-done]').forEach(btn => {
    btn.addEventListener("click", (e) => {
      e.preventDefault();
      dismissSheet();
    });
  });

  if (sheetBackdrop) {
    sheetBackdrop.addEventListener("click", () => dismissSheet());
  }

  document.addEventListener("keydown", (e) => {
    if (e.key === 'Escape' && currentSheet) dismissSheet();
  });
}

// Present one of the three over whatever is underneath it.
function showSheet(name) {
  const sheet = sheets[name];
  if (!sheet) return;

  if (currentSheet && currentSheet !== name) dismissSheet();

  currentSheet = name;
  trackScreenView(name, `CueCard ${sheet.querySelector('.sheet-title').textContent}`);

  if (sheetBackdrop) sheetBackdrop.classList.remove('hidden');
  sheet.classList.add('sheet-hiding');
  sheet.classList.remove('hidden');
  // One frame on the far side of the transition, so it has somewhere to travel from.
  requestAnimationFrame(() => sheet.classList.remove('sheet-hiding'));

  switch (name) {
    case 'settings':
      loadCurrentSettings();
      break;
    case 'shortcuts':
      populateShortcutKeys();
      break;
    case 'saved-notes':
      renderSavedNotesList();
      break;
  }
}

// A sheet always returns to what is underneath it, so there is nothing to remember.
function dismissSheet() {
  const sheet = sheets[currentSheet];
  currentSheet = null;
  if (sheetBackdrop) sheetBackdrop.classList.add('hidden');
  if (!sheet) return;

  sheet.classList.add('sheet-hiding');
  const done = () => {
    sheet.classList.add('hidden');
    sheet.removeEventListener('transitionend', done);
  };
  sheet.addEventListener('transitionend', done);
}

// Clear the editor and everything hanging off it, for a fresh note.
function startNewNote() {
  // Clear the input and highlight
  notesInput.value = '';
  if (notesInputHighlight) {
    notesInputHighlight.innerHTML = '';
  }

  // Clear notes content
  notesContent.innerHTML = '';
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

  updateTransport();
  updateMenuItems();
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
      elapsedSeconds = 0;
      updateTimerDisplay();
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
      showSheet('saved-notes');
    });
  }

  const slidesLink = document.getElementById('slides-link');
  if (slidesLink) {
    slidesLink.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      syncSlideNotes();
    });
  }
}

// Show the notes for the slide that is open, asking for the scope if we have
// not been given it yet.
async function syncSlideNotes() {
  trackSlidesSync();

  const hasSlidesScope = await hasScope('slides');
  if (!hasSlidesScope) {
    console.log("Slides scope not granted, requesting...");
    await handleLogin('slides');
    return;
  }

  if (currentSlideData) {
    await showView('notes');
  } else {
    displayNotes('Open a Google Slides presentation to see notes here.\n[cue Install CueCard Extension to sync notes]');
    window.title = 'No Slide Open';
    await showView('notes');
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

// Transport: one button carries play, pause and — held down — restart.
function setupTimerControls() {
  if (!btnPlay) return;

  // A long press or a right-click restarts, which is iOS's third control.
  let holdTimeout = null;
  let didRestartOnHold = false;

  btnPlay.addEventListener("mousedown", (e) => {
    if (e.button !== 0) return;
    didRestartOnHold = false;
    holdTimeout = setTimeout(() => {
      didRestartOnHold = true;
      resetTimerCountdown();
    }, 550);
  });

  const clearHold = () => {
    clearTimeout(holdTimeout);
    holdTimeout = null;
  };
  btnPlay.addEventListener("mouseup", clearHold);
  btnPlay.addEventListener("mouseleave", clearHold);

  btnPlay.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    resetTimerCountdown();
  });

  btnPlay.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    if (didRestartOnHold) {
      didRestartOnHold = false;
      return;
    }
    if (timerState === 'running') {
      pauseTimerCountdown();
    } else {
      startTimerCountdown();
    }
  });

  if (btnRestart) {
    btnRestart.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      resetTimerCountdown();
    });
  }

  setupTimerPill();
}

// The Set Timer pill expands in place to show the run's duration.
function setupTimerPill() {
  if (!btnSetTimer || !timerControl) return;

  btnSetTimer.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    if (timerControl.classList.contains('disabled')) return;
    openTimerPicker();
  });

  if (btnCloseTimerPicker) {
    btnCloseTimerPicker.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      closeTimerPicker();
    });
  }

  // A field holds text while it is being edited, and becomes the setting on
  // the way out of it.
  [timerMinutesField, timerSecondsField].forEach(field => {
    if (!field) return;
    field.addEventListener("blur", () => commitTimerFields());
    field.addEventListener("keydown", (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        field.blur();
      }
    });
  });
}

function openTimerPicker() {
  if (!timerControl || !timerPicker) return;
  timerControl.classList.add('expanded');
  timerPicker.classList.remove('hidden');
  updateTimerPickerDuration();
}

function closeTimerPicker() {
  if (!timerControl || !timerPicker) return;
  if (timerControl.classList.contains('expanded')) commitTimerFields();
  timerControl.classList.remove('expanded');
  timerPicker.classList.add('hidden');
}

// Show the stored duration in the two fields, unless one is being typed in.
function updateTimerPickerDuration() {
  if (!timerMinutesField || !timerSecondsField) return;
  if (document.activeElement === timerMinutesField || document.activeElement === timerSecondsField) return;
  timerMinutesField.value = String(timerMinutes).padStart(2, '0');
  timerSecondsField.value = String(timerSeconds).padStart(2, '0');
}

// Take what was typed, holding minutes and seconds to what a clock can show.
// Anything that isn't a number leaves the setting alone.
async function commitTimerFields() {
  const typedMinutes = parseInt(timerMinutesField.value.replace(/\D/g, ''), 10);
  const typedSeconds = parseInt(timerSecondsField.value.replace(/\D/g, ''), 10);

  if (!Number.isNaN(typedMinutes)) timerMinutes = Math.min(Math.max(typedMinutes, 0), 59);
  if (!Number.isNaN(typedSeconds)) timerSeconds = Math.min(Math.max(typedSeconds, 0), 59);

  await setStoredValue(STORAGE_KEYS.SETTINGS_TIMER_MINUTES, timerMinutes);
  await setStoredValue(STORAGE_KEYS.SETTINGS_TIMER_SECONDS, timerSeconds);
  trackSettingChange('timer_duration', timerDurationSeconds());

  updateTimerPickerDuration();
  // A run already under way is re-timed against the new duration.
  updateTimerDisplay();
}

// The delays a typed start delay is held to, as on iOS.
const COUNTDOWN_MIN = 0;
const COUNTDOWN_MAX = 60;

// How long the run is, as set on the Set Timer pill. Zero counts up instead.
function timerDurationSeconds() {
  return timerMinutes * 60 + timerSeconds;
}

// Start/Resume the run. On the first play there is a delay to count down first,
// so you can get your hands off the machine before the script moves.
function startTimerCountdown() {
  console.log('[Timer] startTimerCountdown called, timerState:', timerState);
  if (timerState === 'running' || countdownInterval) return;

  // Notes arriving from Slides are driven by the deck, not by someone stepping
  // back from the keyboard, so there is nothing to wait for.
  const skipDelay = hasStarted || countdownSeconds <= 0 || currentView === 'notes';
  if (!skipDelay) {
    runStartDelay();
    return;
  }

  beginRun();
}

// Count the delay down in the header, in pink, then start.
function runStartDelay() {
  countdownValue = countdownSeconds;
  updateTimerDisplay();
  updateTransport();

  countdownInterval = setInterval(() => {
    countdownValue -= 1;
    if (countdownValue <= 0) {
      stopStartDelay();
      beginRun();
      return;
    }
    updateTimerDisplay();
  }, 1000);
}

function stopStartDelay() {
  clearInterval(countdownInterval);
  countdownInterval = null;
  countdownValue = 0;
}

function beginRun() {
  trackTimerAction('start');
  timerState = 'running';
  hasStarted = true;
  updateTransport();

  startAutoScroll();

  // The clock is read from wall time rather than counted in ticks, so pausing
  // and resuming cannot make it drift.
  const startedAt = Date.now();
  const elapsedAtStart = elapsedSeconds;

  const interval = setInterval(() => {
    if (timerState !== 'running') {
      clearInterval(interval);
      return;
    }
    elapsedSeconds = elapsedAtStart + (Date.now() - startedAt) / 1000;
    updateTimerDisplay();
  }, 200);

  timerIntervals.push(interval);
}

// The header clock, and the colour iOS gives it: green while there is room,
// yellow inside the last fifth, red once the run has gone over.
function updateTimerDisplay() {
  if (!headerTimer) return;

  const duration = timerDurationSeconds();
  headerTimer.classList.remove('time-countup', 'time-warning', 'time-overtime', 'time-delay');

  // The delay before the run, counted down in pink.
  if (countdownInterval) {
    headerTimer.textContent = formatTime(countdownValue);
    headerTimer.classList.add('time-delay');
    return;
  }

  // Nothing to count down to, so count up instead.
  if (duration <= 0) {
    headerTimer.textContent = formatTime(Math.floor(elapsedSeconds));
    headerTimer.classList.add('time-countup');
    return;
  }

  const remaining = duration - Math.floor(elapsedSeconds);
  headerTimer.textContent = formatTime(remaining);

  if (remaining < 0) {
    headerTimer.classList.add('time-overtime');
  } else if (remaining / duration <= 0.2) {
    headerTimer.classList.add('time-warning');
  }
}

// Pause the run, or call off the delay before it
function pauseTimerCountdown() {
  if (countdownInterval) {
    stopStartDelay();
    updateTimerDisplay();
    updateTransport();
    return;
  }
  if (timerState !== 'running') return;

  trackTimerAction('pause');
  timerState = 'paused';
  stopAllTimers();
  stopAutoScroll();
  updateTransport();
}

// Put the run back to its beginning
function resetTimerCountdown() {
  trackTimerAction('reset');
  stopStartDelay();
  stopAllTimers();
  stopAutoScroll();
  timerState = 'stopped';
  elapsedSeconds = 0;
  autoScrollHeldSeconds = 0;
  hasStarted = false;

  const container = getScrollContainer();
  if (container) {
    container.scrollTop = 0;
    programmaticScrollTop = 0;
  }

  updateTimerDisplay();
  updateTransport();
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

// The speeds a typed lines-a-minute figure is held to, as on iOS.
const LPM_MIN = 1;
const LPM_MAX = 300;

/**
 * Where on screen the line being read sits, as a fraction of the view height.
 * Just above centre: high enough to leave the next few lines in view, low
 * enough to read as the middle of the screen rather than the top of it.
 */
const READING_LINE_FRACTION = 0.45;

// One rendered line of the script, in pixels — what a line a minute is a minute of.
function renderedLineHeight(container) {
  const lineHeight = parseFloat(getComputedStyle(container).lineHeight);
  if (!Number.isNaN(lineHeight) && lineHeight > 0) return lineHeight;
  return parseFloat(getComputedStyle(container).fontSize) * 1.2;
}

// Start auto-scroll animation
function startAutoScroll() {
  if (linesPerMinute <= 0 || autoScrollAnimationId !== null) return;
  if (!getScrollContainer()) return;

  // The position is a function of the clock, not a running total, so pausing
  // and resuming cannot make the script drift out of step with the timer.
  function scrollStep() {
    if (timerState !== 'running' || linesPerMinute <= 0) {
      stopAutoScroll();
      return;
    }

    const container = getScrollContainer();
    if (container) {
      const maxScroll = container.scrollHeight - container.clientHeight;
      if (maxScroll > 0) {
        const held = autoScrollHeldSeconds + (autoScrollHeldSince ? (Date.now() - autoScrollHeldSince) / 1000 : 0);
        const lines = Math.max(elapsedSeconds - held, 0) * linesPerMinute / 60;
        const target = lines * renderedLineHeight(container) - readingLineOffset(container);
        container.scrollTop = Math.min(Math.max(target, 0), maxScroll);
        // Remember what we wrote, so the scroll it fires is not read as a scrub.
        programmaticScrollTop = container.scrollTop;
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
  autoScrollPausedByHover = false;
  autoScrollHeldSince = null;
}

// How far the reading line sits down the view.
function readingLineOffset(container) {
  return container.clientHeight * READING_LINE_FRACTION;
}

// Dragging the script moves the clock, not just the view, so pausing and
// dragging back re-times the run instead of desynchronising it.
function scrubToScrollTop(container) {
  if (linesPerMinute <= 0) return;

  const lineHeight = renderedLineHeight(container);
  if (!lineHeight) return;

  const lines = (container.scrollTop + readingLineOffset(container)) / lineHeight;
  elapsedSeconds = Math.max(lines * 60 / linesPerMinute, 0);
  autoScrollHeldSeconds = 0;
  autoScrollHeldSince = autoScrollPausedByHover ? Date.now() : null;
  updateTimerDisplay();
}

// Setup hover listeners to pause auto-scroll, and scrubbing by dragging
function setupAutoScrollHoverListeners() {
  const containers = [notesInputHighlight, notesContent];

  containers.forEach(container => {
    if (!container) return;

    container.addEventListener('scroll', () => {
      // Ours, not the reader's.
      if (programmaticScrollTop !== null && Math.abs(container.scrollTop - programmaticScrollTop) < 1) return;
      programmaticScrollTop = null;
      if (!hasStarted) return;
      scrubToScrollTop(container);
    });

    container.addEventListener('mouseenter', () => {
      if (autoScrollPausedByHover) return;
      autoScrollPausedByHover = true;
      autoScrollHeldSince = Date.now();
    });

    container.addEventListener('mouseleave', () => {
      if (!autoScrollPausedByHover) return;
      autoScrollPausedByHover = false;
      if (autoScrollHeldSince) {
        autoScrollHeldSeconds += (Date.now() - autoScrollHeldSince) / 1000;
        autoScrollHeldSince = null;
      }
    });
  });
}

// Update header timer visibility based on view (shown in notes views for both countdown and count-up)
function updateHeaderTimerVisibility() {
  if (!headerTimer) return;
  const isNotesView = currentView === 'add-notes' || currentView === 'notes';
  headerTimer.classList.toggle('hidden', !isNotesView);
}

// The whole transport, read off timerState and whether there is a script to run.
function updateTransport() {
  if (!editorControls || !btnPlay) return;

  const isEditorView = currentView === 'add-notes';
  const isSlidesView = currentView === 'notes';
  editorControls.classList.toggle('hidden', !(isEditorView || isSlidesView));

  // Something to run: a written script that is not being typed, or synced notes.
  let hasScript = false;
  if (isEditorView) {
    hasScript = Boolean(notesInput.value.trim()) && !isEditMode;
  } else if (isSlidesView) {
    hasScript = Boolean(currentSlideData && notesContent && notesContent.textContent.trim());
  }

  const isUnderWay = timerState === 'running' || countdownInterval !== null;
  btnPlay.disabled = !hasScript;
  btnPlay.setAttribute('aria-label', isUnderWay ? 'Pause' : 'Start');
  btnPlay.title = isUnderWay ? 'Pause' : 'Start';
  if (iconPlay) iconPlay.classList.toggle('hidden', isUnderWay);
  if (iconPause) iconPause.classList.toggle('hidden', !isUnderWay);

  // Restart only means something once a run is under way.
  if (btnRestart) {
    btnRestart.classList.toggle('hidden', !(hasScript && (isUnderWay || timerState === 'paused')));
  }

  if (timerControl) {
    timerControl.classList.toggle('disabled', !hasScript);
    if (!hasScript) closeTimerPicker();
  }
  updateTimerPickerDuration();
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
      updateHeaderTimerVisibility();
      // Update timer button visibility when content changes
      updateTransport();
      // Update edit note button visibility when content changes
      updateEditNoteButtonVisibility();
      return;
    }

    // Apply the same highlighting as in displayNotes
    const highlighted = highlightNotesForInput(text);
    notesInputHighlight.innerHTML = highlighted;

    // Update timer button visibility when content changes
    updateTransport();
    // Update edit note button visibility when content changes
    updateEditNoteButtonVisibility();
  }

  // Listen for input changes
  notesInput.addEventListener('input', updateHighlight);

  // `[` writes both brackets, and the backspace that follows takes them both
  // back away again, so a `[` meant literally costs one extra keystroke
  // instead of six.
  notesInput.addEventListener('keydown', (e) => {
    if (notesInput.readOnly) return;
    if (notesInput.selectionStart !== notesInput.selectionEnd) return;

    const caret = notesInput.selectionStart;
    const text = notesInput.value;

    if (e.key === '[') {
      e.preventDefault();
      // Cues don't nest, and in here both brackets are already written.
      if (cueTagContaining(caret, text)) return;

      const insertion = emptyCueInsertion(text, caret);
      replaceInEditor(caret, caret, insertion.text, caret + insertion.caretOffset);
      return;
    }

    if (e.key === 'Backspace' && caret > 0) {
      const emptyCue = emptyCueSurrounding(caret - 1, text);
      if (!emptyCue) return;
      e.preventDefault();
      replaceInEditor(emptyCue.index, emptyCue.index + emptyCue.length, '[', emptyCue.index + 1);
    }
  });

  // Initial update if there's already content
  updateHighlight();
}

// Edit the textarea ourselves, then run everything an ordinary keystroke would.
function replaceInEditor(start, end, replacement, caret) {
  notesInput.setRangeText(replacement, start, end, 'end');
  notesInput.selectionStart = notesInput.selectionEnd = caret;
  notesInput.dispatchEvent(new Event('input', { bubbles: true }));
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

  updateMenuItems();
}


// Wrap every cue in the span the stylesheet colours. The text has already been
// HTML-escaped, which leaves the brackets a cue is recognised by untouched.
function highlightCues(escapedText) {
  let result = '';
  let lastEnd = 0;

  for (const match of cueMatches(escapedText)) {
    result += escapedText.slice(lastEnd, match.index);
    result += `<span class="cue-tag">[${match.content}]</span>`;
    lastEnd = match.index + match.length;
  }

  return result + escapedText.slice(lastEnd);
}

// Every line-break kind there is — \r\n, \r, U+2028, U+2029, a vertical tab —
// down to the one the editor works in.
function normalizeLineBreaks(text) {
  return text
    .replace(/\\n/g, '\n')
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .replace(/\u2028/g, '\n')
    .replace(/\u2029/g, '\n')
    .replace(/\v/g, '\n');
}

// The script as the editor shows it: cues in colour, everything else as typed.
function highlightNotesForInput(text) {
  const safe = highlightCues(escapeHtml(normalizeLineBreaks(text)));
  return safe.replace(/\n/g, '<br>');
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
    updateSignOutItem();

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
    updateSignOutItem();

    // Reset welcome heading to default
    welcomeHeading.innerHTML = 'CueCard\n<span class="version-text">1.4.1</span>';

    // Reset subtext
    welcomeSubtext.innerHTML = 'Speaker notes visible only to you during screen sharing — for <span class="highlight-presentations">presentations</span>, <span class="highlight-meetings">meetings</span>, or <span class="highlight-demos">live demos</span>.';
    if (welcomeActions) {
      welcomeActions.classList.add('hidden');
    }
  }
}

// Sign out is offered in the menu only while there is an account to sign out of.
function updateSignOutItem() {
  if (btnSignOut) btnSignOut.classList.toggle('hidden', !isAuthenticated);
  if (menuSeparatorAccount) menuSeparatorAccount.classList.toggle('hidden', !isAuthenticated);
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
    dismissSheet();
    if (await shouldShowWelcome()) {
      await showView('initial');
    } else if (currentView === 'notes') {
      await showView('add-notes');
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

// Show a specific view. Settings, Shortcuts and Saved Notes are sheets now,
// so this switches only the editor, the welcome hero and the Slides notes.
async function showView(viewName) {
  // Save notes to storage if we're in add-notes view
  if (currentView === 'add-notes') {
    await saveNotesToStorage();
  }

  const wasView = currentView;
  currentView = viewName;

  const pageTitles = {
    'initial': 'CueCard Home',
    'add-notes': 'CueCard Add Notes',
    'notes': 'CueCard Notes'
  };
  trackScreenView(viewName, pageTitles[viewName] || 'CueCard');

  if (appContainer) {
    appContainer.classList.remove('stroke-add-notes', 'stroke-slides');
    if (viewName === 'add-notes') {
      appContainer.classList.add('stroke-add-notes');
    } else if (viewName === 'notes') {
      appContainer.classList.add('stroke-slides');
    }
  }

  viewInitial.classList.add('hidden');
  viewAddNotes.classList.add('hidden');
  viewNotes.classList.add('hidden');

  // The toolbar carries the same controls everywhere; only the title changes.
  updateToolbarTitle();
  updateHeaderTimerVisibility();

  if (ghostModeIndicator) {
    const shouldShowGhost = ghostMode && (viewName === 'notes' || viewName === 'add-notes');
    ghostModeIndicator.classList.toggle('hidden', !shouldShowGhost);
  }

  updateShortcutsVisibility();
  updateTransport();
  updateEditNoteButtonVisibility();

  switch (viewName) {
    case 'initial':
      viewInitial.classList.remove('hidden');
      break;
    case 'add-notes':
      viewAddNotes.classList.remove('hidden');
      // The editor's own content is already there when coming back from a sheet.
      if (wasView !== 'add-notes') {
        await loadStoredNotes();
        // A script that was already written comes back read-only and highlighted.
        if (notesInput.value.trim()) {
          isEditMode = false;
          notesInputWrapper.classList.remove('edit-mode');
          notesInput.readOnly = true;
        }
      }
      updateEditNoteButtonVisibility();
      updateTransport();
      break;
    case 'notes':
      viewNotes.classList.remove('hidden');
      const hasNotesContent = notesContent && notesContent.textContent.trim();
      if (!hasNotesContent) {
        updateHeaderTimerVisibility();
        stopAllTimers();
        timerState = 'stopped';
      }
      if (timerState === 'stopped' && currentSlideData && hasNotesContent) {
        startTimerCountdown();
      }
      break;
  }

  updateMenuItems();
}

// The toolbar title: the app, or whatever is open in front of it.
function updateToolbarTitle() {
  if (!toolbarTitle) return;

  switch (currentView) {
    case 'settings':
      toolbarTitle.textContent = 'Settings';
      break;
    case 'shortcuts':
      toolbarTitle.textContent = 'Shortcuts';
      break;
    case 'saved-notes':
      toolbarTitle.textContent = 'Saved Notes';
      break;
    case 'notes':
      toolbarTitle.textContent = currentSlideData
        ? truncateText(currentSlideData.title || 'Untitled Presentation', 28)
        : 'CueCard';
      break;
    default:
      toolbarTitle.textContent = 'CueCard';
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
  updateTransport();
}

// The same, for notes arriving from Google Slides, where the extension's name
// is worth linking.
function highlightNotes(text) {
  let safe = highlightCues(escapeHtml(normalizeLineBreaks(text)));

  safe = safe.replace(/CueCard Extension/gi, (match) =>
    `<a href="https://cuecard.dev/#download" class="slides-link" target="_blank" rel="noopener noreferrer">${match}</a>`);

  return safe.replace(/\n/g, '<br>');
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

        // Hide the item before relaunch
        btnDownloadUpdates.classList.add('hidden');
        if (menuBadge) menuBadge.classList.add('hidden');

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
      // Offer the update in the menu, and badge the menu so it is noticed
      btnDownloadUpdates.classList.remove('hidden');
      if (menuBadge) menuBadge.classList.remove('hidden');
    } else {
      console.log('No updates available');
      btnDownloadUpdates.classList.add('hidden');
      if (menuBadge) menuBadge.classList.add('hidden');
    }
  } catch (error) {
    console.error('Error checking for updates:', error);
    btnDownloadUpdates.classList.add('hidden');
    if (menuBadge) menuBadge.classList.add('hidden');
  }
}

// The ellipsis menu is open when this is true; a click anywhere else closes it.
let menuOpen = false;

function openMenu() {
  if (!appMenu) return;
  menuOpen = true;
  appMenu.classList.remove('hidden');
}

function closeMenu() {
  if (!appMenu) return;
  menuOpen = false;
  appMenu.classList.add('hidden');
}

// Menu Handlers
function setupMenu() {
  if (btnMenu) {
    btnMenu.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      if (menuOpen) {
        closeMenu();
      } else {
        openMenu();
      }
    });
  }

  // Clicking a menu item, or anything outside the menu, puts it away.
  if (appMenu) {
    appMenu.addEventListener("click", (e) => {
      if (e.target.closest('.menu-item')) closeMenu();
    });
  }
  document.addEventListener("click", (e) => {
    if (!menuOpen) return;
    if (e.target.closest('.menu-wrap')) return;
    closeMenu();
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === 'Escape' && menuOpen) closeMenu();
  });

  const newNoteItem = document.getElementById('new-note-btn');
  if (newNoteItem) {
    newNoteItem.addEventListener("click", async (e) => {
      e.preventDefault();
      startNewNote();
      await showView('add-notes');
      isEditMode = true;
      notesInputWrapper.classList.add('edit-mode');
      notesInput.readOnly = false;
      notesInput.focus();
    });
  }

  const slidesSyncLink = document.getElementById('slides-sync-link');
  if (slidesSyncLink) {
    slidesSyncLink.addEventListener("click", (e) => {
      e.preventDefault();
      syncSlideNotes();
    });
  }

  if (btnSavedNotes) {
    btnSavedNotes.addEventListener("click", (e) => {
      e.preventDefault();
      showSheet('saved-notes');
    });
  }

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
        window.open("mailto:hello@thisisnsh.com", "_blank", "noopener,noreferrer");
        return;
      }
      await openUrl("mailto:hello@thisisnsh.com");
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
    showSheet('settings');
  });

  // Shortcuts link handler
  shortcutsLink.addEventListener("click", (e) => {
    e.preventDefault();
    console.log("Shortcuts link clicked");
    showSheet('shortcuts');
  });
}

// The menu shows only the items that mean something in the current view.
function updateMenuItems() {
  const isSlidesView = currentView === 'notes';
  const isEditorView = currentView === 'add-notes';
  const slidesSyncLink = document.getElementById('slides-sync-link');
  if (slidesSyncLink) slidesSyncLink.classList.toggle('hidden', isSlidesView);

  if (refreshBtn) {
    refreshBtn.classList.toggle('hidden', !(isSlidesView && currentSlideData));
  }
  if (editNoteBtn) {
    editNoteBtn.classList.toggle('hidden', !(isEditorView && notesInput.value.trim()));
    editNoteBtn.textContent = isEditMode ? 'Done' : 'Edit Note';
  }
  if (menuSeparatorNote) menuSeparatorNote.classList.remove('hidden');
}

// =============================================================================
// SETTINGS MANAGEMENT
// =============================================================================

// Default settings values
const DEFAULT_OPACITY = 100;
const DEFAULT_GHOST_MODE = true; // true = ghost mode ON = hidden from screenshots
const DEFAULT_SHORTCUTS_ENABLED = true; // true = global shortcuts are enabled
const DEFAULT_LINES_PER_MINUTE = 50; // what iOS scrolls at out of the box

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

const TIME_TAG_PATTERN = /\[time[ \t]+(\d{1,2}):(\d{2})\][ \t]*\n?/gi;

/**
 * Timing used to be written into the script as `[time mm:ss]`. It is a duration
 * set in the app now, so the tags are taken out of every stored script — once —
 * and, if no duration has been set yet, the run is seeded from their sum.
 * Nobody opens the app to find their timings silently gone.
 */
async function migrateTimeTags(hasStoredDuration) {
  if (await getStoredValue(STORAGE_KEYS.MIGRATED_TIME_TAGS)) return;

  const sumOf = (text) => {
    let total = 0;
    for (const match of text.matchAll(new RegExp(TIME_TAG_PATTERN.source, 'gi'))) {
      total += parseInt(match[1], 10) * 60 + parseInt(match[2], 10);
    }
    return total;
  };
  const stripped = (text) => text.replace(new RegExp(TIME_TAG_PATTERN.source, 'gi'), '');

  const currentScript = (await getStoredValue(STORAGE_KEYS.ADD_NOTES_CONTENT)) || '';
  const savedNotes = await getSavedNotes();

  // Whatever the user was timing to, in the script they were last working on —
  // falling back to the most recent saved note that carried any tags at all.
  let seedSeconds = sumOf(currentScript);
  if (seedSeconds === 0) {
    const tagged = savedNotes.find(note => sumOf(note.content || '') > 0);
    if (tagged) seedSeconds = sumOf(tagged.content);
  }

  if (currentScript) {
    await setStoredValue(STORAGE_KEYS.ADD_NOTES_CONTENT, stripped(currentScript));
  }
  if (savedNotes.some(note => sumOf(note.content || '') > 0)) {
    await setStoredValue(
      STORAGE_KEYS.SAVED_NOTES,
      savedNotes.map(note => ({ ...note, content: stripped(note.content || '') }))
    );
  }

  if (seedSeconds > 0 && !hasStoredDuration) {
    timerMinutes = Math.min(Math.floor(seedSeconds / 60), 59);
    timerSeconds = seedSeconds % 60;
    await setStoredValue(STORAGE_KEYS.SETTINGS_TIMER_MINUTES, timerMinutes);
    await setStoredValue(STORAGE_KEYS.SETTINGS_TIMER_SECONDS, timerSeconds);
    console.log(`Carried ${seedSeconds}s of [time] tags over into the timer`);
  }

  await setStoredValue(STORAGE_KEYS.MIGRATED_TIME_TAGS, true);
}

// Every cue in the app is drawn from this one variable.
function applyCueColor(name) {
  document.documentElement.style.setProperty('--cue-color', cueColorVariable(name));
  updateCueColorSwatches(name);
}

function updateCueColorSwatches(name) {
  if (!cueColorSwatches) return;
  cueColorSwatches.querySelectorAll('.cue-swatch').forEach(swatch => {
    swatch.classList.toggle('selected', swatch.dataset.cueColor === name);
    swatch.setAttribute('aria-pressed', String(swatch.dataset.cueColor === name));
  });
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

  // Load the start delay, defaulting to the phone app's five seconds
  const storedCountdown = await getStoredValue(STORAGE_KEYS.SETTINGS_COUNTDOWN_SECONDS);
  if (typeof storedCountdown === 'number') {
    countdownSeconds = clampCountdown(storedCountdown);
  } else {
    countdownSeconds = 5;
    await setStoredValue(STORAGE_KEYS.SETTINGS_COUNTDOWN_SECONDS, countdownSeconds);
  }

  // Load the run's length, defaulting to the phone app's 1:00
  const storedMinutes = await getStoredValue(STORAGE_KEYS.SETTINGS_TIMER_MINUTES);
  const storedSeconds = await getStoredValue(STORAGE_KEYS.SETTINGS_TIMER_SECONDS);
  const hasStoredDuration = typeof storedMinutes === 'number' || typeof storedSeconds === 'number';
  timerMinutes = typeof storedMinutes === 'number' ? storedMinutes : 1;
  timerSeconds = typeof storedSeconds === 'number' ? storedSeconds : 0;
  if (!hasStoredDuration) {
    await setStoredValue(STORAGE_KEYS.SETTINGS_TIMER_MINUTES, timerMinutes);
    await setStoredValue(STORAGE_KEYS.SETTINGS_TIMER_SECONDS, timerSeconds);
  }

  await migrateTimeTags(hasStoredDuration);
  updateTimerDisplay();

  // Load the cue colour, which has been pink here since before it was a choice
  const storedCueColor = await getStoredValue(STORAGE_KEYS.SETTINGS_CUE_COLOR);
  if (CUE_COLORS.includes(storedCueColor)) {
    cueColor = storedCueColor;
  } else {
    cueColor = DEFAULT_CUE_COLOR;
    await setStoredValue(STORAGE_KEYS.SETTINGS_CUE_COLOR, cueColor);
  }
  applyCueColor(cueColor);

  // Load the scroll speed. It used to be a 0-2x multiplier applied per animation
  // frame; anyone who set one carries that figure and no lines-a-minute setting,
  // so convert it at the speed it actually scrolled — 1x moved a 24px line about
  // two and a half times a second.
  const storedLpm = await getStoredValue(STORAGE_KEYS.SETTINGS_LINES_PER_MINUTE);
  if (typeof storedLpm === 'number') {
    linesPerMinute = storedLpm === 0 ? 0 : clampLpm(storedLpm);
  } else {
    const storedSpeed = await getStoredValue(STORAGE_KEYS.SETTINGS_AUTO_SCROLL_SPEED);
    const legacySpeed = typeof storedSpeed === 'string'
      ? ({ off: 0, low: 0.5, medium: 1, high: 2 }[storedSpeed] ?? 0)
      : (typeof storedSpeed === 'number' ? storedSpeed : null);

    if (legacySpeed === null) {
      linesPerMinute = DEFAULT_LINES_PER_MINUTE;
    } else {
      // Zero stayed off through the change, because people rely on it.
      linesPerMinute = legacySpeed === 0 ? 0 : clampLpm(Math.round(legacySpeed * 150));
    }
    await setStoredValue(STORAGE_KEYS.SETTINGS_LINES_PER_MINUTE, linesPerMinute);
  }
}

function clampLpm(value) {
  return Math.min(Math.max(Math.round(value), LPM_MIN), LPM_MAX);
}

// Take what was typed as a speed, holding it to the range the script can scroll
// at — except zero, which is Off. Anything that isn't a number leaves it alone.
async function commitSpeedField() {
  if (!speedField) return;
  const typed = parseInt(speedField.value.replace(/\D/g, ''), 10);
  if (!Number.isNaN(typed)) {
    linesPerMinute = typed === 0 ? 0 : clampLpm(typed);
    trackSettingChange('lines_per_minute', linesPerMinute);
    await setStoredValue(STORAGE_KEYS.SETTINGS_LINES_PER_MINUTE, linesPerMinute);

    // A run already under way picks up the new speed.
    if (timerState === 'running') {
      stopAutoScroll();
      startAutoScroll();
    }
  }
  speedField.value = String(linesPerMinute);
}

// Settings Handlers
function setupSettings() {
  if (speedField) {
    speedField.addEventListener("blur", () => commitSpeedField());
    speedField.addEventListener("keydown", (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        speedField.blur();
      }
    });
  }

  if (countdownField) {
    countdownField.addEventListener("blur", () => commitCountdownField());
    countdownField.addEventListener("keydown", (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        countdownField.blur();
      }
    });
  }

  // Cue colour swatches
  if (cueColorSwatches) {
    cueColorSwatches.innerHTML = CUE_COLORS.map(name => `
      <button class="cue-swatch" data-cue-color="${name}" style="background: var(--color-${name})"
        aria-label="${name.charAt(0).toUpperCase() + name.slice(1)}" title="${name.charAt(0).toUpperCase() + name.slice(1)}">
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M2.5 6.4l2.4 2.4 4.6-5" stroke="currentColor" stroke-width="2" stroke-linecap="round"
            stroke-linejoin="round" />
        </svg>
      </button>`).join('');

    cueColorSwatches.addEventListener('click', async (e) => {
      const swatch = e.target.closest('.cue-swatch');
      if (!swatch) return;
      cueColor = swatch.dataset.cueColor;
      applyCueColor(cueColor);
      trackSettingChange('cue_color', cueColor);
      await setStoredValue(STORAGE_KEYS.SETTINGS_CUE_COLOR, cueColor);
    });
  }

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
      if (ghostModeIndicator) {
        const inScript = currentView === 'notes' || currentView === 'add-notes';
        ghostModeIndicator.classList.toggle('hidden', !(ghostMode && inScript));
      }

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

}

// The badge is only there to say the window is hidden, so it only shows then.
function updateGhostModeIndicator() {
  if (!ghostModeIndicator) return;
  ghostModeIndicator.textContent = 'Ghost';
  ghostModeIndicator.title = 'Hidden from screenshots and recordings';
  ghostModeIndicator.classList.toggle('ghost-off', !ghostMode);
}

// Update shortcuts button visibility based on shortcutsEnabled setting and current view
function updateShortcutsVisibility() {
  if (shortcutsLink) {
    shortcutsLink.classList.toggle('hidden', !shortcutsEnabled);
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

  updateCueColorSwatches(cueColor);
  if (countdownField) countdownField.value = String(countdownSeconds);

  if (speedField) speedField.value = String(linesPerMinute);
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
