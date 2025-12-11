const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

// DOM Elements
let authBtn;
let welcomeHeading;
let viewInitial, viewAddNotes, viewNotes;
let linkPasteNotes, linkGoBack;
let notesInput, notesContent;

// State
let isAuthenticated = false;
let userName = '';
let currentView = 'initial'; // 'initial', 'add-notes', 'notes'
let manualNotes = ''; // Notes pasted by the user

// Initialize the app
window.addEventListener("DOMContentLoaded", async () => {
  // Get DOM elements
  authBtn = document.getElementById("auth-btn");
  welcomeHeading = document.getElementById("welcome-heading");
  viewInitial = document.getElementById("view-initial");
  viewAddNotes = document.getElementById("view-add-notes");
  viewNotes = document.getElementById("view-notes");
  linkPasteNotes = document.getElementById("link-paste-notes");
  linkGoBack = document.getElementById("link-go-back");
  notesInput = document.getElementById("notes-input");
  notesContent = document.getElementById("notes-content");

  // Set up navigation handlers
  setupNavigation();

  // Set up auth handlers
  setupAuth();

  // Check auth status on load
  await checkAuthStatus();

  // Check for existing slide data
  await checkCurrentSlide();

  // Listen for slide updates from the backend
  await listen("slide-update", (event) => {
    console.log("Received slide update:", event.payload);
    handleSlideUpdate(event.payload);
  });

  // Listen for auth status changes
  await listen("auth-status", (event) => {
    console.log("Auth status changed:", event.payload);
    updateAuthUI(event.payload.authenticated, event.payload.user_name);
  });
});

// Navigation Handlers
function setupNavigation() {
  linkPasteNotes.addEventListener("click", (e) => {
    e.preventDefault();
    showView('add-notes');
    notesInput.focus();
  });

  linkGoBack.addEventListener("click", (e) => {
    e.preventDefault();
    // If user has entered notes, show them
    const notes = notesInput.value.trim();
    if (notes) {
      manualNotes = notes;
      displayNotes(notes);
      showView('notes');
    } else {
      showView('initial');
    }
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
  authBtn.addEventListener("click", async () => {
    if (isAuthenticated) {
      await handleLogout();
    } else {
      await handleLogin();
    }
  });
}

// Check authentication status
async function checkAuthStatus() {
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
  
  // Update welcome heading
  if (authenticated && name) {
    welcomeHeading.textContent = `Welcome ${name}!`;
  } else {
    welcomeHeading.textContent = 'Welcome Human!';
  }
  
  // Update button text and icon visibility
  const buttonText = authBtn.querySelector('.gsi-material-button-contents');
  const buttonIcon = authBtn.querySelector('.gsi-material-button-icon');
  if (buttonText) {
    buttonText.textContent = authenticated ? "Sign Out" : "Sign in with Google";
  }
  if (buttonIcon) {
    buttonIcon.style.display = authenticated ? 'none' : 'block';
  }
}

// Handle login
async function handleLogin() {
  try {
    await invoke("start_login");
  } catch (error) {
    console.error("Error starting login:", error);
  }
}

// Handle logout
async function handleLogout() {
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
}

// Highlight timestamps and action tags in notes
function highlightNotes(text) {
  // Escape HTML first
  let safe = escapeHtml(text);

  // Pattern for timestamps like [00:23], [01:23], [1:30:45]
  const timestampPattern = /\[(\d{1,2}:\d{2}(?::\d{2})?)\]/g;
  
  // Pattern for action tags like [laugh], [pause], [sign], etc.
  const actionPattern = /\[(laugh|pause|sign|applause|music|silence|cough|sigh|gasp)\]/gi;

  // Replace timestamps - they appear on their own line
  safe = safe.replace(timestampPattern, '<span class="timestamp">[$1]</span>');
  
  // Replace action tags - they appear inline
  safe = safe.replace(actionPattern, '<span class="action-tag">[$1]</span>');

  // Convert line breaks
  safe = safe.replace(/\n\n/g, '</p><p class="paragraph">');
  safe = safe.replace(/\n/g, '<br>');

  return `<p class="paragraph">${safe}</p>`;
}

// Escape HTML to prevent XSS
function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}
