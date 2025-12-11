const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

// DOM Elements
let header;
let waitingMessage;
let slideDetails;
let notesSection;
let presentationTitle;
let slideNumber;
let notesContent;
let loginBtn;
let logoutBtn;
let authPrompt;
let authPromptBtn;
let slideInfo;
let opacitySlider;
let welcomeSection;
let welcomeCta;
let addNotesSection;
let notesInput;
let backLink;
let slideIndicator;
let slideLabel;
let slideTitleHeader;

// App state
let currentView = 'welcome'; // 'welcome', 'add-notes', 'waiting', 'notes'
let isAuthenticated = false;
let manualNotes = ''; // Notes pasted by user

// Initialize the app
window.addEventListener("DOMContentLoaded", async () => {
  // Get DOM elements
  header = document.querySelector("#header");
  waitingMessage = document.querySelector("#waiting-message");
  slideDetails = document.querySelector("#slide-details");
  notesSection = document.querySelector("#notes-section");
  presentationTitle = document.querySelector("#presentation-title");
  slideNumber = document.querySelector("#slide-number");
  notesContent = document.querySelector("#notes-content");
  loginBtn = document.querySelector("#login-btn");
  logoutBtn = document.querySelector("#logout-btn");
  authPrompt = document.querySelector("#auth-prompt");
  authPromptBtn = document.querySelector("#auth-prompt-btn");
  slideInfo = document.querySelector("#slide-info");
  opacitySlider = document.querySelector("#opacity-slider");
  welcomeSection = document.querySelector("#welcome-section");
  welcomeCta = document.querySelector("#welcome-cta");
  addNotesSection = document.querySelector("#add-notes-section");
  notesInput = document.querySelector("#notes-input");
  backLink = document.querySelector("#back-link");
  slideIndicator = document.querySelector("#slide-indicator");
  slideLabel = document.querySelector("#slide-label");
  slideTitleHeader = document.querySelector("#slide-title-header");

  // Set up auth button handlers
  loginBtn.addEventListener("click", handleLogin);
  logoutBtn.addEventListener("click", handleLogout);
  authPromptBtn.addEventListener("click", handleLogin);

  // Set up welcome CTA handler
  welcomeCta.addEventListener("click", handleWelcomeCta);

  // Set up back link handler
  backLink.addEventListener("click", handleBackLink);

  // Set up notes input handler
  notesInput.addEventListener("input", handleNotesInput);

  // Set up scroll listener for header effect
  notesContent.addEventListener("scroll", handleScroll);

  // Check auth status on load
  await checkAuthStatus();

  // Check for existing slide data on load
  await checkCurrentSlide();

  // Listen for slide updates from the backend
  await listen("slide-update", (event) => {
    console.log("Received slide update:", event.payload);
    updateUI(event.payload);
  });

  // Listen for auth status changes
  await listen("auth-status", (event) => {
    console.log("Auth status changed:", event.payload);
    updateAuthUI(event.payload.authenticated);
  });
});

// Handle scroll for header gradient effect
function handleScroll() {
  if (notesContent.scrollTop > 10) {
    header.classList.add('scrolled');
  } else {
    header.classList.remove('scrolled');
  }
}

// Check authentication status
async function checkAuthStatus() {
  try {
    isAuthenticated = await invoke("get_auth_status");
    updateAuthUI(isAuthenticated);
  } catch (error) {
    console.error("Error checking auth status:", error);
    updateAuthUI(false);
  }
}

// Update UI based on auth status
function updateAuthUI(authenticated) {
  isAuthenticated = authenticated;

  if (authenticated) {
    loginBtn.style.display = "none";
    logoutBtn.style.display = "block";
    authPrompt.style.display = "none";

    // Show waiting state or notes depending on current state
    if (currentView === 'welcome') {
      showWaitingState();
    }
  } else {
    loginBtn.style.display = "block";
    logoutBtn.style.display = "none";

    // Show welcome view
    showWelcomeView();
  }
}

// Handle welcome CTA click
function handleWelcomeCta() {
  showAddNotesView();
}

// Handle back link click
function handleBackLink() {
  // Save any notes that were entered
  if (notesInput.value.trim()) {
    manualNotes = notesInput.value;
    showManualNotesView();
  } else {
    showWelcomeView();
  }
}

// Handle notes input
function handleNotesInput() {
  // Could add auto-save or other features here
}

// Show welcome view
function showWelcomeView() {
  currentView = 'welcome';
  welcomeSection.style.display = "flex";
  addNotesSection.style.display = "none";
  slideInfo.style.display = "none";
  notesSection.style.display = "none";
  slideIndicator.style.display = "none";
}

// Show add notes view
function showAddNotesView() {
  currentView = 'add-notes';
  welcomeSection.style.display = "none";
  addNotesSection.style.display = "flex";
  slideInfo.style.display = "none";
  notesSection.style.display = "none";
  slideIndicator.style.display = "none";
  notesInput.focus();
}

// Show manual notes view (after user pastes notes)
function showManualNotesView() {
  currentView = 'notes';
  welcomeSection.style.display = "none";
  addNotesSection.style.display = "none";
  slideInfo.style.display = "none";
  notesSection.style.display = "flex";
  slideIndicator.style.display = "none";

  // Display the manual notes with syntax highlighting
  notesContent.innerHTML = `<div class="notes-text">${formatNotesWithSyntax(manualNotes)}</div>`;
}

// Show waiting state (authenticated but no slide data)
function showWaitingState() {
  currentView = 'waiting';
  welcomeSection.style.display = "none";
  addNotesSection.style.display = "none";
  slideInfo.style.display = "block";
  waitingMessage.style.display = "flex";
  slideDetails.style.display = "none";
  notesSection.style.display = "none";
  slideIndicator.style.display = "none";
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
    updateAuthUI(false);
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
      updateUI({ slide_data: slide, notes });
    }
  } catch (error) {
    console.error("Error checking current slide:", error);
  }
}

// Update the UI with slide data
function updateUI(data) {
  const { slide_data, notes } = data;

  if (!slide_data) {
    if (isAuthenticated) {
      showWaitingState();
    } else {
      showWelcomeView();
    }
    return;
  }

  currentView = 'notes';

  // Hide other sections
  welcomeSection.style.display = "none";
  addNotesSection.style.display = "none";
  waitingMessage.style.display = "none";
  slideInfo.style.display = "none";

  // Show notes section
  notesSection.style.display = "flex";

  // Update slide indicator in header
  slideIndicator.style.display = "flex";
  const slideNum = slide_data.slideNumber || slide_data.slide_number || "1";
  const title = slide_data.title || "Untitled";
  slideLabel.textContent = `[Slide ${slideNum}]`;

  // Truncate title if too long
  const maxTitleLength = 20;
  if (title.length > maxTitleLength) {
    slideTitleHeader.textContent = title.substring(0, maxTitleLength) + "...";
  } else {
    slideTitleHeader.textContent = title;
  }

  // Update notes with syntax highlighting
  if (notes && notes.trim()) {
    notesContent.innerHTML = `<div class="notes-text">${formatNotesWithSyntax(notes)}</div>`;
  } else {
    notesContent.innerHTML = `<p class="no-notes">No notes available for this slide.</p>`;
  }
}

// Format notes with syntax highlighting for timestamps and cues
function formatNotesWithSyntax(text) {
  // First escape HTML
  let escaped = escapeHtml(text);

  // Highlight timestamps like [00:23], [01:23], etc.
  escaped = escaped.replace(/\[(\d{1,2}:\d{2})\]/g, '<span class="timestamp">[$1]</span>');

  // Highlight cues like [laugh], [pause], [sign], etc.
  escaped = escaped.replace(/\[(laugh|pause|sign|smile|wave|point|gesture|nod|breathe|slow|fast|emphasis|louder|softer|wait)\]/gi, '<span class="cue">[$1]</span>');

  // Convert newlines to <br>
  escaped = escaped.replace(/\n/g, "<br>");

  return escaped;
}

// Escape HTML to prevent XSS
function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

// Handle opacity slider change (kept for compatibility but hidden)
async function handleOpacityChange(event) {
  const opacityPercent = parseInt(event.target.value);
  const opacity = opacityPercent / 100;

  try {
    await invoke("set_window_opacity", { opacity });
  } catch (error) {
    console.error("Error setting window opacity:", error);
  }
}
