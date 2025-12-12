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
let notesInput, notesContent;
let welcomeSubtext;
let privacyLink, websiteLink;

// State
let isAuthenticated = false;
let userName = '';
let currentView = 'initial'; // 'initial', 'add-notes', 'notes'
let manualNotes = ''; // Notes pasted by the user

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
  welcomeSubtext = document.getElementById("welcome-subtext");
  privacyLink = document.getElementById("privacy-link");
  websiteLink = document.getElementById("website-link");
  
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
    showView('initial');
  });

  // Handle Enter in notes input to submit
  notesInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && e.ctrlKey) {
      const notes = notesInput.value.trim();
      if (notes) {
        manualNotes = notes;
        displayNotes(notes);
        showView('notes');
      }
    }
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
    welcomeSubtext.innerHTML = 'Click anywhere to paste your notes or use with <a href="https://slides.google.com" target="_blank" rel="noopener noreferrer" class="slides-link">Google Slides</a> directly...';
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
      handleSlideUpdate({ slide_data: slide, notes });
    }
  } catch (error) {
    console.error("Error checking current slide:", error);
  }
}

// Handle slide update from Google Slides
function handleSlideUpdate(data) {
  const { slide_data, notes } = data;

  if (!slide_data) {
    return;
  }

  // Display the notes
  if (notes && notes.trim()) {
    displayNotes(notes);
    showView('notes');
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
  if (viewName === 'add-notes') {
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
function displayNotes(text) {
  const highlighted = highlightNotes(text);
  notesContent.innerHTML = highlighted;
  
  // Start countdown timers if there are any
  startTimers();
}

// Highlight timestamps and action tags in notes
function highlightNotes(text) {
  // Escape HTML first
  let safe = escapeHtml(text);

  let cumulativeTime = 0; // Track cumulative time in seconds

  // Pattern for [time mm:ss] syntax
  const timePattern = /\[time\s+(\d{1,2}):(\d{2})\]/gi;
  
  // Pattern for [emotion emotion-name] syntax
  const emotionPattern = /\[emotion\s+([a-zA-Z]+)\]/gi;
  
  // Pattern for old-style timestamps like [00:23], [01:23] (keep for backward compatibility)
  const timestampPattern = /\[(\d{1,2}:\d{2}(?::\d{2})?)\]/g;
  
  // Pattern for old-style action tags like [laugh], [pause], [sign] (keep for backward compatibility)
  const actionPattern = /\[(laugh|pause|sign|applause|music|silence|cough|sigh|gasp)\]/gi;

  // Replace [time mm:ss] with cumulative time display
  safe = safe.replace(timePattern, (match, minutes, seconds) => {
    const timeInSeconds = parseInt(minutes) * 60 + parseInt(seconds);
    cumulativeTime += timeInSeconds;
    
    const displayMinutes = Math.floor(cumulativeTime / 60);
    const displaySeconds = cumulativeTime % 60;
    const displayTime = `${String(displayMinutes).padStart(2, '0')}:${String(displaySeconds).padStart(2, '0')}`;
    
    // Add a newline before the timestamp and after
    return `\n<span class="timestamp" data-time="${cumulativeTime}">[${displayTime}]</span>\n`;
  });
  
  // Replace [emotion name] with [name] inline
  safe = safe.replace(emotionPattern, (match, emotion) => {
    return `<span class="action-tag">[${emotion}]</span>`;
  });

  // Replace old-style timestamps - they appear on their own line
  safe = safe.replace(timestampPattern, '<span class="timestamp">[$1]</span>');
  
  // Replace old-style action tags - they appear inline
  safe = safe.replace(actionPattern, '<span class="action-tag">[$1]</span>');

  // Convert line breaks
  safe = safe.replace(/\n\n/g, '</p><p class="paragraph">');
  safe = safe.replace(/\n/g, '<br>');

  return `<p class="paragraph">${safe}</p>`;
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
