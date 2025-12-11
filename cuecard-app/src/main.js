const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

// DOM Elements
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

// Initialize the app
window.addEventListener("DOMContentLoaded", async () => {
  // Get DOM elements
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

  // Set up auth button handlers
  loginBtn.addEventListener("click", handleLogin);
  logoutBtn.addEventListener("click", handleLogout);
  authPromptBtn.addEventListener("click", handleLogin);

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

// Check authentication status
async function checkAuthStatus() {
  try {
    const isAuthenticated = await invoke("get_auth_status");
    updateAuthUI(isAuthenticated);
  } catch (error) {
    console.error("Error checking auth status:", error);
    updateAuthUI(false);
  }
}

// Update UI based on auth status
function updateAuthUI(isAuthenticated) {
  if (isAuthenticated) {
    loginBtn.style.display = "none";
    logoutBtn.style.display = "block";
    authPrompt.style.display = "none";
    slideInfo.style.display = "block";
  } else {
    loginBtn.style.display = "block";
    logoutBtn.style.display = "none";
    authPrompt.style.display = "flex";
    slideInfo.style.display = "none";
    notesSection.style.display = "none";
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
    showWaitingState();
    return;
  }

  // Hide waiting message, show slide details
  waitingMessage.style.display = "none";
  slideDetails.style.display = "block";
  notesSection.style.display = "block";

  // Update slide info
  presentationTitle.textContent = slide_data.title || "Untitled Presentation";
  slideNumber.textContent = slide_data.slideNumber || slide_data.slide_number || "-";

  // Update notes
  if (notes && notes.trim()) {
    notesContent.innerHTML = `<div class="notes-text">${escapeHtml(notes)}</div>`;
  } else {
    notesContent.innerHTML = `<p class="no-notes">No notes available for this slide.</p>`;
  }
}

// Show waiting state
function showWaitingState() {
  waitingMessage.style.display = "flex";
  slideDetails.style.display = "none";
  notesSection.style.display = "none";
}

// Escape HTML to prevent XSS
function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML.replace(/\n/g, "<br>");
}
