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
let welcomeSubtext;
let privacyLink, websiteLink;
let refreshBtn;

// State
let isAuthenticated = false;
let userName = '';
let currentView = 'initial'; // 'initial', 'add-notes', 'notes'
let manualNotes = ''; // Notes pasted by the user
let currentSlideData = null; // Store current slide data

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
  welcomeSubtext = document.getElementById("welcome-subtext");
  privacyLink = document.getElementById("privacy-link");
  websiteLink = document.getElementById("website-link");
  refreshBtn = document.getElementById("refresh-btn");
  
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
  // Click anywhere on initial view to paste notes (only when authenticated)
  viewInitial.addEventListener("click", (e) => {
    // Don't trigger if clicking the auth button or not authenticated
    if (e.target.closest('#auth-btn') || !isAuthenticated) {
      return;
    }
    e.preventDefault();
    showView('add-notes');
    notesInput.focus();
  });

  linkGoBack.addEventListener("click", (e) => {
    e.preventDefault();
    // Clear the input and go back to initial view
    notesInput.value = '';
    // Clear slide info when going back
    slideInfo.textContent = '';
    currentSlideData = null;
    showView('initial');
  });
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
    // Update subtext to show click instruction
    welcomeSubtext.innerHTML = 'Click anywhere to paste your notes or use with <a href="#" class="slides-link" id="slides-link">Google Slides</a> directly...';
    
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
    
    // Enable clickable view
    viewInitial.classList.add('clickable-view');
  } else {
    // Update button to show "Sign in"
    if (buttonText) buttonText.textContent = 'Sign in with Google';
    if (buttonIcon) buttonIcon.style.display = 'block';
    // Reset subtext
    welcomeSubtext.innerHTML = 'Speaker notes for <span class="highlight-presentations">presentations</span>, <span class="highlight-meetings">meetings</span>, and even <span class="highlight-dates">dates</span> — visible only to you...';
    // Disable clickable view
    viewInitial.classList.remove('clickable-view');
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

  // Store current slide data
  currentSlideData = slide_data;

  // Display the notes
  if (notes && notes.trim()) {
    displayNotes(notes, slide_data);
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

  // Show the requested view
  switch (viewName) {
    case 'initial':
      viewInitial.classList.remove('hidden');
      break;
    case 'add-notes':
      viewAddNotes.classList.remove('hidden');
      break;
    case 'notes':
      viewNotes.classList.remove('hidden');
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
    const slideNumber = slideData.slideNumber || '?';
    slideInfo.textContent = `${presentationTitle} • Slide ${slideNumber}`;
  } else if (slideInfo) {
    slideInfo.textContent = '';
  }
  
  // Start countdown timers if there are any
  startTimers();
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

// Start countdown timers for all timestamps
function startTimers() {
  const timestamps = document.querySelectorAll('.timestamp[data-time]');
  
  timestamps.forEach(timestamp => {
    const totalSeconds = parseInt(timestamp.getAttribute('data-time'));
    let remainingSeconds = totalSeconds;
    
    // Update the timer every second
    const interval = setInterval(() => {
      remainingSeconds--;
      
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
      
      // Optional: stop at some point if needed
      // if (remainingSeconds < -600) clearInterval(interval); // Stop after 10 minutes overtime
    }, 1000);
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
