// Check if Tauri is available
if (!window.__TAURI__) {
  console.error("Tauri runtime not available! Make sure you're running the app with 'npm run tauri dev' or as a built Tauri app.");
}

const { invoke } = window.__TAURI__?.core || {};
const { listen } = window.__TAURI__?.event || {};
const { open } = window.__TAURI__?.shell || {};

// DOM Elements
let authBtn;
let viewInitial, viewAddNotes, viewNotes;
let linkGoBack, backSeparator;
let notesInput, notesContent, slideInfo;
let welcomeHeading, welcomeSubtext;
let privacyLink, websiteLink;
let refreshBtn;
let notesInputHighlight;
let timerControls, timerSeparator;
let btnStart, btnPause, btnReset;

// State
let isAuthenticated = false;
let userName = '';
let currentView = 'initial'; // 'initial', 'add-notes', 'notes'
let manualNotes = ''; // Notes pasted by the user
let currentSlideData = null; // Store current slide data

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
  linkGoBack = document.getElementById("link-go-back");
  backSeparator = document.getElementById("back-separator");
  notesInput = document.getElementById("notes-input");
  notesContent = document.getElementById("notes-content");
  slideInfo = document.getElementById("slide-info");
  welcomeHeading = document.getElementById("welcome-heading");
  welcomeSubtext = document.getElementById("welcome-subtext");
  privacyLink = document.getElementById("privacy-link");
  websiteLink = document.getElementById("website-link");
  refreshBtn = document.getElementById("refresh-btn");
  notesInputHighlight = document.getElementById("notes-input-highlight");
  timerControls = document.getElementById("timer-controls");
  timerSeparator = document.getElementById("timer-separator");
  btnStart = document.getElementById("btn-start");
  btnPause = document.getElementById("btn-pause");
  btnReset = document.getElementById("btn-reset");
  
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
    
    // Add loading state
    refreshBtn.classList.add('loading');
    refreshBtn.disabled = true;
    
    try {
      console.log("Refreshing notes...");
      await invoke("refresh_notes");
      console.log("Notes refreshed successfully");
    } catch (error) {
      console.error("Error refreshing notes:", error);
    } finally {
      // Remove loading state
      refreshBtn.classList.remove('loading');
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
  
  const timestamps = document.querySelectorAll('.timestamp[data-time]');
  
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
  
  const timestamps = document.querySelectorAll('.timestamp[data-time]');
  
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

// Update timer button visibility based on state
function updateTimerButtonVisibility() {
  if (!timerControls || !btnStart || !btnPause || !btnReset) return;
  
  // Show timer controls only in add-notes or notes view
  if (currentView === 'add-notes' || currentView === 'notes') {
    timerControls.classList.remove('hidden');
    timerSeparator.classList.remove('hidden');
  } else {
    timerControls.classList.add('hidden');
    timerSeparator.classList.add('hidden');
    return;
  }
  
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
}

// Setup syntax highlighting for notes input
function setupNotesInputHighlighting() {
  if (!notesInput || !notesInputHighlight) return;
  
  // Function to update the highlighted preview
  function updateHighlight() {
    const text = notesInput.value;
    if (!text) {
      notesInputHighlight.innerHTML = '';
      return;
    }
    
    // Apply the same highlighting as in displayNotes, but without timers
    const highlighted = highlightNotesForInput(text);
    notesInputHighlight.innerHTML = highlighted;
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
    
    return `<span class="timestamp">[${displayTime}]</span>`;
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
    
    // Update welcome heading with greeting and first name
    const firstName = getFirstName(name);
    const greeting = getGreeting();
    const versionSpan = welcomeHeading.querySelector('.version-text');
    const versionHTML = versionSpan ? versionSpan.outerHTML : '';
    welcomeHeading.innerHTML = `${greeting}, ${firstName}!${versionHTML ? '\n' + versionHTML : ''}`;
    
    // Update subtext to show paste notes link
    welcomeSubtext.innerHTML = 'Speak using <a href="#" class="paste-notes-link" id="paste-notes-link">Your Notes</a>, or sync them from <a href="#" class="slides-link" id="slides-link">Google Slides</a> seamlessly...';
    
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
          displayNotes('Open a Google Slides presentation to see your speaker notes here...');
          slideInfo.textContent = 'No Slide Open';
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
    welcomeSubtext.innerHTML = 'Speaker notes for <span class="highlight-presentations">presentations</span>, <span class="highlight-meetings">meetings</span>, and even <span class="highlight-dates">dates</span> — visible only to you...';
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

  // Show/hide the back button in footer based on view
  if (viewName === 'add-notes' || viewName === 'notes') {
    linkGoBack.classList.remove('hidden');
    backSeparator.classList.remove('hidden');
  } else {
    linkGoBack.classList.add('hidden');
    backSeparator.classList.add('hidden');
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
      // In notes view, timer starts automatically
      if (timerState === 'stopped') {
        startTimerCountdown();
      }
      break;
  }
}

// Display notes with syntax highlighting
function displayNotes(text, slideData = null) {
  const highlighted = highlightNotes(text);
  notesContent.innerHTML = highlighted;
  
  // Update slide info if available
  if (slideData && slideInfo) {
    // Use camelCase property names (as sent by backend with serde rename_all = "camelCase")
    const presentationTitle = slideData.title || 'Untitled Presentation';
    slideInfo.textContent = `${presentationTitle}`;
  } else if (slideInfo) {
    slideInfo.textContent = 'No Slide Open';
  }
  
  // Initialize timer data attributes but don't start
  // Timer start is controlled by buttons or view logic
  initializeTimerDataAttributes();
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
      if (!open) {
        console.error("Tauri shell API not available");
        window.open("https://cuecard.dev/privacy", "_blank", "noopener,noreferrer");
        return;
      }
      await open("https://cuecard.dev/privacy");
    } catch (error) {
      console.error("Error opening privacy policy:", error);
    }
  });

  websiteLink.addEventListener("click", async (e) => {
    e.preventDefault();
    console.log("Website link clicked");
    try {
      if (!open) {
        console.error("Tauri shell API not available");
        window.open("https://cuecard.dev", "_blank", "noopener,noreferrer");
        return;
      }
      await open("https://cuecard.dev");
    } catch (error) {
      console.error("Error opening website:", error);
    }
  });
}
