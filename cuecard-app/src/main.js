// Check if Tauri is available
if (!window.__TAURI__) {
  console.error("Tauri runtime not available! Make sure you're running the app with 'npm run tauri dev' or as a built Tauri app.");
}

const { invoke } = window.__TAURI__?.core || {};
const { listen } = window.__TAURI__?.event || {};
const { openUrl } = window.__TAURI__?.opener || {};

// DOM Elements
let authBtn;
let viewInitial, viewAddNotes, viewNotes, viewSettings;
let linkGoBack, backSeparator;
let notesInput, notesContent, slideInfo, slideInfoBtn, slideSeparator;
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
  slideInfo = document.getElementById("slide-info");
  slideInfoBtn = document.getElementById("slide-info-btn");
  slideSeparator = document.getElementById("slide-separator");
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

  // Set up slide info button handler
  setupSlideInfoButton();

  // Set up timer control buttons
  setupTimerControls();

  // Set up syntax highlighting for notes input
  setupNotesInputHighlighting();

  // Set up settings handlers
  setupSettings();

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
    await listen("auth-status", (event) => {
      console.log("Auth status changed:", event.payload);
      updateAuthUI(event.payload.authenticated, event.payload.user_name);
    });
  }

  console.log("App initialization complete!");
});

// Navigation Handlers
function setupNavigation() {
  linkGoBack.addEventListener("click", (e) => {
    e.preventDefault();
    // Reset all states
    resetAllStates();
    showView('initial');
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
  slideInfo.textContent = '';

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

// Slide Info Button Handler
function setupSlideInfoButton() {
  if (!slideInfoBtn) return;

  slideInfoBtn.addEventListener("click", async (e) => {
    e.preventDefault();
    e.stopPropagation();

    console.log("Slide info button clicked. Current slide data:", currentSlideData);

    if (!currentSlideData) {
      console.log("No slide data available");
      return;
    }

    if (!openUrl) {
      console.error("Tauri opener API not available");
      // Fallback to window.open
      const presentationId = currentSlideData.presentationId;
      const slideId = currentSlideData.slideId;
      const url = `https://docs.google.com/presentation/d/${presentationId}/view#slide=id.${slideId}`;
      window.open(url, "_blank", "noopener,noreferrer");
      return;
    }

    try {
      // Construct the Google Slides URL
      const presentationId = currentSlideData.presentationId;
      const slideId = currentSlideData.slideId;
      const url = `https://docs.google.com/presentation/d/${presentationId}/view#slide=id.${slideId}`;

      console.log("Opening slide:", url);
      await openUrl(url);
    } catch (error) {
      console.error("Error opening slide:", error);
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
    // Try to get user info if authenticated
    let name = '';
    if (status) {
      try {
        const userInfo = await invoke("get_user_info");
        name = userInfo?.name || '';
      } catch (e) {
        console.log("Could not get user info:", e);
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

    // Show settings link
    settingsLink.classList.remove('hidden');
    settingsSeparator.classList.remove('hidden');

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
        showView('add-notes');
        notesInput.focus();
      });
    }

    // Add click handler for Google Slides link
    const slidesLink = document.getElementById('slides-link');
    if (slidesLink) {
      slidesLink.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        // Show notes view with slide data or default message
        if (currentSlideData) {
          showView('notes');
        } else {
          // Show notes view with default message when no slide is open
          displayNotes('Open a Google Slides presentation to see notes here...');
          slideInfo.textContent = 'No Slide Open';
          showView('notes');
        }
      });
    }
  } else {
    // Update button to show "Sign in"
    if (buttonText) buttonText.textContent = 'Sign in with Google';
    if (buttonIcon) buttonIcon.style.display = 'block';

    // Hide settings link
    settingsLink.classList.add('hidden');
    settingsSeparator.classList.add('hidden');

    // Reset welcome heading to default
    welcomeHeading.innerHTML = 'CueCard\n<span class="version-text">1.0.1</span>';

    // Reset subtext
    welcomeSubtext.innerHTML = 'Speaker notes visible only to you — for <span class="highlight-presentations">presentations</span>, <span class="highlight-meetings">meetings</span>, <span class="highlight-dates">dates</span> and everything...';
  }
}

// Handle login
async function handleLogin() {
  try {
    if (!invoke) {
      console.error("Tauri invoke API not available");
      alert("Please run the app in Tauri mode");
      return;
    }
    await invoke("start_login");
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
function showView(viewName) {
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

  // Show/hide privacy, website, and settings links based on view
  if (viewName === 'initial') {
    // Initial view: show Visit Site, Privacy Policy, Settings
    privacyLink.classList.remove('hidden');
    websiteLink.classList.remove('hidden');
    websiteSeparator.classList.remove('hidden');
    if (isAuthenticated) {
      settingsLink.classList.remove('hidden');
      settingsSeparator.classList.remove('hidden');
    }
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
    settingsLink.classList.add('hidden');
    settingsSeparator.classList.add('hidden');
  }

  // Show/hide slide info and refresh button based on view and slide data
  if (viewName === 'notes' && currentSlideData) {
    slideInfoBtn.classList.remove('hidden');
    slideSeparator.classList.remove('hidden');
    refreshBtn.classList.remove('hidden');
    refreshSeparator.classList.remove('hidden');
  } else {
    slideInfoBtn.classList.add('hidden');
    slideSeparator.classList.add('hidden');
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
  if (slideData && slideInfo) {
    // Use camelCase property names (as sent by backend with serde rename_all = "camelCase")
    const presentationTitle = slideData.title || 'Untitled Presentation';
    slideInfo.textContent = truncateText(presentationTitle);

    // Show slide info and refresh button in footer when there's slide data
    if (currentView === 'notes') {
      slideInfoBtn.classList.remove('hidden');
      slideSeparator.classList.remove('hidden');
      refreshBtn.classList.remove('hidden');
      refreshSeparator.classList.remove('hidden');
    }
  } else if (slideInfo) {
    slideInfo.textContent = 'No Slide Open';

    // Hide slide info and refresh button when no slide
    slideInfoBtn.classList.add('hidden');
    slideSeparator.classList.add('hidden');
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
