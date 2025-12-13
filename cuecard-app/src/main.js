// Check if Tauri is available
if (!window.__TAURI__) {
  console.error("Tauri runtime not available! Make sure you're running the app with 'npm run tauri dev' or as a built Tauri app.");
}

const { invoke } = window.__TAURI__?.core || {};
const { listen } = window.__TAURI__?.event || {};
const { openUrl } = window.__TAURI__?.opener || {};

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

// Get or create user profile in Firestore
async function saveUserProfile(email, name) {
  if (!email || !FIRESTORE_BASE_URL) return;

  const documentPath = `Profiles/${encodeURIComponent(email)}`;
  const url = `${FIRESTORE_BASE_URL}/${documentPath}`;

  try {
    // First, try to get the existing document
    const getResponse = await fetch(url);

    if (getResponse.ok) {
      // Document exists, just update name and email (don't touch creationDate)
      const existingDoc = await getResponse.json();
      const updateUrl = `${url}?updateMask.fieldPaths=name&updateMask.fieldPaths=email`;

      await fetch(updateUrl, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
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

// Increment usage counter in Firestore
async function incrementUsage(email, usageType) {
  console.log("Incrementing usage for email:", email, "usageType:", usageType);
  if (!email || !FIRESTORE_BASE_URL) return;

  const documentPath = `Profiles/${encodeURIComponent(email)}`;
  const url = `${FIRESTORE_BASE_URL}/${documentPath}`;

  try {
    // Get current document to read current usage values
    const getResponse = await fetch(url);

    if (getResponse.ok) {
      const doc = await getResponse.json();
      const currentUsage = doc.fields?.usage?.mapValue?.fields || {};
      const currentPaste = parseInt(currentUsage.paste?.integerValue || '0');
      const currentSlide = parseInt(currentUsage.slide?.integerValue || '0');

      // Calculate new values
      const newPaste = usageType === 'paste' ? currentPaste + 1 : currentPaste;
      const newSlide = usageType === 'slide' ? currentSlide + 1 : currentSlide;

      // Update only the usage field
      const updateUrl = `${url}?updateMask.fieldPaths=usage`;

      await fetch(updateUrl, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          fields: {
            usage: {
              mapValue: {
                fields: {
                  paste: { integerValue: String(newPaste) },
                  slide: { integerValue: String(newSlide) }
                }
              }
            }
          }
        })
      });
      console.log(`Usage ${usageType} incremented in Firestore`);
    }
  } catch (error) {
    console.error("Error incrementing usage in Firestore:", error);
  }
}

// Get user email from stored user info
async function getUserEmail() {
  if (!invoke) return null;
  try {
    const userInfo = await invoke("get_user_info");
    console.log("User info:", userInfo);
    return userInfo?.email || null;
  } catch (e) {
    console.log("Could not get user email:", e);
    return null;
  }
}

// Store for persistent storage
let appStore = null;

// Storage keys
const STORAGE_KEYS = {
  SETTINGS_OPACITY: 'settings_opacity',
  SETTINGS_SCREENSHOT_PROTECTION: 'settings_screenshot_protection',
  ADD_NOTES_CONTENT: 'add_notes_content',
  GRANTED_SCOPES: 'granted_scopes'
};

// Scope constants (must match backend)
const SCOPES = {
  PROFILE: 'openid profile email',
  SLIDES: 'https://www.googleapis.com/auth/presentations.readonly'
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

// Get granted scopes from storage
async function getGrantedScopes() {
  const scopes = await getStoredValue(STORAGE_KEYS.GRANTED_SCOPES);
  return scopes || [];
}

// Save granted scopes to storage
async function saveGrantedScopes(scopes) {
  await setStoredValue(STORAGE_KEYS.GRANTED_SCOPES, scopes);
  console.log("Saved granted scopes:", scopes);
}

// Check if a specific scope is granted
async function hasScope(scopeType) {
  const scopes = await getGrantedScopes();
  const scopeUrl = scopeType === 'profile' ? SCOPES.PROFILE : SCOPES.SLIDES;
  return scopes.includes(scopeUrl);
}

// Add a scope to the granted scopes list
async function addGrantedScope(scopeUrl) {
  const scopes = await getGrantedScopes();
  if (!scopes.includes(scopeUrl)) {
    scopes.push(scopeUrl);
    await saveGrantedScopes(scopes);
  }
}

// Clear all granted scopes (for logout)
async function clearGrantedScopes() {
  await setStoredValue(STORAGE_KEYS.GRANTED_SCOPES, []);
  console.log("Cleared granted scopes");
}

// DOM Elements
let authBtn;
let viewInitial, viewAddNotes, viewNotes, viewSettings;
let linkGoBack, backSeparator;
let notesInput, notesContent;
let welcomeHeading, welcomeSubtext;
let privacyLink, websiteLink, websiteSeparator;
let settingsLink, settingsSeparator;
let refreshBtn, refreshSeparator;
let notesInputHighlight;
let timerSeparator, timerStartSeparator, timerPauseSeparator;
let btnStart, btnPause, btnReset;
let opacitySlider, opacityValue, screenCaptureToggle;

// State
let isAuthenticated = false;
let userName = '';
let currentView = 'initial'; // 'initial', 'add-notes', 'notes', 'settings'
let previousView = null; // 'initial', 'add-notes', 'notes', 'settings'
let manualNotes = ''; // Notes pasted by the user
let currentSlideData = null; // Store current slide data
let currentOpacity = 100; // Store current opacity value (10-100)
let screenshotProtectionEnabled = true; // Default: protected (not shown in capture)

// Timer State
let timerState = 'stopped'; // 'stopped', 'running', 'paused'
let timerIntervals = []; // Store all timer interval IDs
let originalTimerValues = []; // Store original timer values for reset

// Initialize the app
window.addEventListener("DOMContentLoaded", async () => {
  console.log("App initializing...");

  // Initialize Firestore configuration from environment variables
  await initFirestoreConfig();

  // Initialize the store for persistent storage
  await initStore();

  // Get DOM elements
  authBtn = document.getElementById("auth-btn");
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
  privacyLink = document.getElementById("privacy-link");
  websiteLink = document.getElementById("website-link");
  websiteSeparator = document.getElementById("website-separator");
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

  console.log("DOM elements loaded:", {
    authBtn: !!authBtn,
    privacyLink: !!privacyLink,
    websiteLink: !!websiteLink
  });

  // Set up navigation handlers
  setupNavigation();

  // Set up auth handlers
  setupAuth();

  // Set up footer handlers
  setupFooter();

  // Set up refresh button handler
  setupRefreshButton();

  // Set up timer control buttons
  setupTimerControls();

  // Set up syntax highlighting for notes input
  setupNotesInputHighlighting();

  // Set up settings handlers
  setupSettings();

  // Load stored settings
  await loadStoredSettings();

  // Check auth status on load
  await checkAuthStatus();

  // Check for existing slide data
  await checkCurrentSlide();

  // Listen for slide updates from the backend
  if (listen) {
    await listen("slide-update", (event) => {
      console.log("Received slide update:", event.payload);
      handleSlideUpdate(event.payload);
    });
  }

  // Listen for auth status changes
  if (listen) {
    await listen("auth-status", async (event) => {
      console.log("Auth status changed:", event.payload);

      // Save granted scopes if provided
      if (event.payload.granted_scopes && Array.isArray(event.payload.granted_scopes)) {
        await saveGrantedScopes(event.payload.granted_scopes);
      }

      // Save user profile to Firestore when authenticated
      if (event.payload.authenticated) {
        const email = await getUserEmail();
        if (email && event.payload.user_name) {
          saveUserProfile(email, event.payload.user_name);
        }
      }

      updateAuthUI(event.payload.authenticated, event.payload.user_name);

      // If slides scope was just granted and we requested it, show the notes view
      if (event.payload.requested_scope === 'slides' && event.payload.authenticated) {
        const hasSlidesScope = await hasScope('slides');
        if (hasSlidesScope) {
          // Show notes view with slide data or default message
          if (currentSlideData) {
            showView('notes');
          } else {
            displayNotes('Open a Google Slides presentation to see notes here...');
            window.title = 'No Slide Open';
            showView('notes');
          }
        }
      }
    });
  }

  console.log("App initialization complete!");
});

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
  originalTimerValues = [];

  // Update timer button visibility
  updateTimerButtonVisibility();
}

// Auth Handlers
function setupAuth() {
  authBtn.addEventListener("click", async (e) => {
    console.log("Auth button clicked", { isAuthenticated });
    e.stopPropagation(); // Prevent event from bubbling to viewInitial
    if (isAuthenticated) {
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
    } catch (error) {
      console.error("Error refreshing notes:", error);
    } finally {
      // Restore original text
      refreshBtn.textContent = originalText;
      refreshBtn.disabled = false;
    }
  });
}

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

  timerState = 'paused';
  stopAllTimers();
  updateTimerButtonVisibility();
}

// Reset timer countdown to original values
function resetTimerCountdown() {
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
    // Check if input text has time pattern
    shouldShowTimers = notesInput.value.trim() && hasTimePattern(notesInput.value);
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
      return;
    }

    // Apply the same highlighting as in displayNotes
    const highlighted = highlightNotesForInput(text);
    notesInputHighlight.innerHTML = highlighted;

    // Initialize timer data attributes for the preview
    initializeTimerDataAttributesForInput();

    // Update timer button visibility when content changes
    updateTimerButtonVisibility();
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

  // Pattern for [emotion ...] syntax
  const emotionPattern = /\[emotion\s+([^\]]+)\]/gi;

  // Replace [time mm:ss]
  safe = safe.replace(timePattern, (match, minutes, seconds) => {
    const timeInSeconds = parseInt(minutes) * 60 + parseInt(seconds);
    cumulativeTime += timeInSeconds;

    const displayMinutes = Math.floor(cumulativeTime / 60);
    const displaySeconds = cumulativeTime % 60;
    const displayTime = `${String(displayMinutes).padStart(2, '0')}:${String(displaySeconds).padStart(2, '0')}`;

    return `<span class="timestamp" data-time="${cumulativeTime}">[${displayTime}]</span>`;
  });

  // Replace [emotion ...]
  safe = safe.replace(emotionPattern, (match, emotion) => {
    return `<span class="action-tag">[${emotion}]</span>`;
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
    // Try to get user info and granted scopes if authenticated
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

      // Sync granted scopes from backend
      try {
        const scopes = await invoke("get_granted_scopes");
        if (scopes && Array.isArray(scopes)) {
          await saveGrantedScopes(scopes);
          console.log("Synced granted scopes from backend:", scopes);
        }
      } catch (e) {
        console.log("Could not get granted scopes:", e);
      }

      // Save user profile to Firestore
      if (email && name) {
        saveUserProfile(email, name);
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
      pasteNotesLink.addEventListener('click', async (e) => {
        e.preventDefault();
        e.stopPropagation();
        // Track paste usage in Firestore
        const email = await getUserEmail();
        if (email) {
          incrementUsage(email, 'paste');
        }
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

        // Track slide usage in Firestore
        const email = await getUserEmail();
        if (email) {
          incrementUsage(email, 'slide');
        }

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
          displayNotes('Open a Google Slides presentation to see notes here...');
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
    welcomeHeading.innerHTML = 'CueCard\n<span class="version-text">1.0.1</span>';

    // Reset subtext
    welcomeSubtext.innerHTML = 'Speaker notes visible only to you — for <span class="highlight-presentations">presentations</span>, <span class="highlight-meetings">meetings</span>, <span class="highlight-dates">dates</span> and everything...';
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
    console.log(`Starting login with scope: ${scope}`);
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
    // Clear granted scopes from local storage
    await clearGrantedScopes();
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

// Show a specific view
async function showView(viewName) {
  // Save notes to storage if we're in add-notes view
  if (currentView === 'add-notes') {
    await saveNotesToStorage();
  }
      
  previousView = currentView;
  currentView = viewName;

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

  // Show/hide privacy, website, and settings links based on view
  if (viewName === 'initial') {
    // Initial view: show Visit Site, Privacy Policy, Settings
    privacyLink.classList.remove('hidden');
    websiteLink.classList.remove('hidden');
    websiteSeparator.classList.remove('hidden');
  } else if (viewName === 'settings') {
    // Settings view: show Visit Site, Privacy Policy (no Settings button)
    privacyLink.classList.remove('hidden');
    websiteLink.classList.remove('hidden');
    websiteSeparator.classList.remove('hidden');
    settingsLink.classList.add('hidden');
    settingsSeparator.classList.add('hidden');
  } else {
    // Notes and Add-Notes views: hide all footer links except go back
    privacyLink.classList.add('hidden');
    websiteLink.classList.add('hidden');
    websiteSeparator.classList.add('hidden');
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

  // Show the requested view
  switch (viewName) {
    case 'initial':
      viewInitial.classList.remove('hidden');
      break;
    case 'add-notes':
      viewAddNotes.classList.remove('hidden');
      // Load stored notes when entering add-notes view
      loadStoredNotes();
      // In add-notes view, timer waits for Start button
      // Don't auto-start
      break;
    case 'notes':
      viewNotes.classList.remove('hidden');
      // In notes view, timer starts automatically if slide is present
      if (timerState === 'stopped' && currentSlideData) {
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
  // Debug: log character codes to identify line break characters
  console.log('Input chars:', [...text].map(c => c.charCodeAt(0)));

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

  // Pattern for [emotion ...] syntax - matches anything between [emotion and ]
  const emotionPattern = /\[emotion\s+([^\]]+)\]/gi;

  // Pattern for "Google Slides" - replace with link
  const slidesPattern = /Google Slides/gi;

  // Replace [time mm:ss] - add line break BEFORE it, time starts a new line
  safe = safe.replace(timePattern, (match, minutes, seconds) => {
    const timeInSeconds = parseInt(minutes) * 60 + parseInt(seconds);
    cumulativeTime += timeInSeconds;

    const displayMinutes = Math.floor(cumulativeTime / 60);
    const displaySeconds = cumulativeTime % 60;
    const displayTime = `${String(displayMinutes).padStart(2, '0')}:${String(displaySeconds).padStart(2, '0')}`;

    return `<span class="timestamp" data-time="${cumulativeTime}">[${displayTime}]</span>`;
  });

  // Replace [emotion ...] with [...] inline (pink)
  safe = safe.replace(emotionPattern, (match, emotion) => {
    return `<span class="action-tag">[${emotion}]</span>`;
  });

  // Replace "Google Slides" with link
  safe = safe.replace(slidesPattern, (match) => {
    return `<a href="https://slides.google.com" class="slides-link" id="slides-link" target="_blank" rel="noopener noreferrer">${match}</a>`;
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

// Footer Handlers
function setupFooter() {
  privacyLink.addEventListener("click", async (e) => {
    e.preventDefault();
    console.log("Privacy link clicked");
    try {
      if (!openUrl) {
        console.error("Tauri opener API not available");
        window.open("https://cuecard.dev/privacy", "_blank", "noopener,noreferrer");
        return;
      }
      await openUrl("https://cuecard.dev/privacy");
    } catch (error) {
      console.error("Error opening privacy policy:", error);
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
    showView('settings');
  });
}

// Load stored settings from persistent storage
async function loadStoredSettings() {
  // Load stored opacity
  const storedOpacity = await getStoredValue(STORAGE_KEYS.SETTINGS_OPACITY);
  if (storedOpacity !== null && storedOpacity !== undefined) {
    currentOpacity = storedOpacity;
    // Apply the stored opacity
    if (invoke) {
      try {
        await invoke("set_window_opacity", { opacity: storedOpacity / 100 });
      } catch (error) {
        console.error("Error applying stored opacity:", error);
      }
    }
  }

  // Load stored screenshot protection setting
  const storedProtection = await getStoredValue(STORAGE_KEYS.SETTINGS_SCREENSHOT_PROTECTION);
  if (storedProtection !== null && storedProtection !== undefined) {
    screenshotProtectionEnabled = storedProtection;
    // Apply the stored screenshot protection
    if (invoke) {
      try {
        await invoke("set_screenshot_protection", { enabled: storedProtection });
      } catch (error) {
        console.error("Error applying stored screenshot protection:", error);
      }
    }
  }

  console.log("Loaded stored settings:", { opacity: currentOpacity, screenshotProtection: screenshotProtectionEnabled });
}

// Settings Handlers
function setupSettings() {
  if (!opacitySlider || !screenCaptureToggle) return;

  // Opacity slider handler
  opacitySlider.addEventListener("input", async (e) => {
    const value = parseInt(e.target.value);
    currentOpacity = value;
    opacityValue.textContent = `${value}%`;

    // Update window opacity via Tauri
    if (invoke) {
      try {
        await invoke("set_window_opacity", { opacity: value / 100 });
      } catch (error) {
        console.error("Error setting window opacity:", error);
      }
    }

    // Save to persistent storage
    await setStoredValue(STORAGE_KEYS.SETTINGS_OPACITY, value);
  });

  // Screen capture toggle handler
  screenCaptureToggle.addEventListener("change", async (e) => {
    const showInCapture = e.target.checked;
    screenshotProtectionEnabled = !showInCapture;

    // Update screenshot protection via Tauri
    // When "show in capture" is ON, protection should be OFF (enabled = false)
    if (invoke) {
      try {
        await invoke("set_screenshot_protection", { enabled: !showInCapture });
      } catch (error) {
        console.error("Error setting screenshot protection:", error);
      }
    }

    // Save to persistent storage
    await setStoredValue(STORAGE_KEYS.SETTINGS_SCREENSHOT_PROTECTION, screenshotProtectionEnabled);
  });
}

// Load current settings values
async function loadCurrentSettings() {
  if (!invoke) return;

  try {
    // Load current opacity
    const opacity = await invoke("get_window_opacity");
    const opacityPercent = Math.round(opacity * 100);
    currentOpacity = opacityPercent;
    if (opacitySlider) {
      opacitySlider.value = opacityPercent;
    }
    if (opacityValue) {
      opacityValue.textContent = `${opacityPercent}%`;
    }
  } catch (error) {
    console.error("Error loading window opacity:", error);
  }

  // Screen capture toggle: default is OFF (protected), so checkbox unchecked
  // The screenshotProtectionEnabled state tracks if protection is on
  if (screenCaptureToggle) {
    screenCaptureToggle.checked = !screenshotProtectionEnabled;
  }
}
