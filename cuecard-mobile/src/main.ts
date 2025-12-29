import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

// =============================================================================
// TYPE DEFINITIONS
// =============================================================================

interface Settings {
  fontSize: number;
  scrollSpeed: number;
  opacity: number;
}

interface UserInfo {
  name: string;
  email: string;
}

type ViewName = "signin" | "notes" | "settings";
type TimerState = "stopped" | "running" | "paused";

// =============================================================================
// STATE
// =============================================================================

let _currentView: ViewName = "signin";
let isEditMode = true;
let timerState: TimerState = "stopped";
let timerIntervals: number[] = [];
let isAndroid = false;
let isIOS = false;

// Settings
let settings: Settings = {
  fontSize: 16,
  scrollSpeed: 1.0,
  opacity: 100,
};

// =============================================================================
// DOM ELEMENTS
// =============================================================================

// Views
let viewSignin: HTMLElement | null;
let viewNotes: HTMLElement | null;
let viewSettings: HTMLElement | null;

// Sign in
let btnSignin: HTMLButtonElement | null;

// Notes view
let userGreeting: HTMLElement | null;
let btnSettings: HTMLButtonElement | null;
let notesInput: HTMLTextAreaElement | null;
let notesInputHighlight: HTMLElement | null;
let notesInputWrapper: HTMLElement | null;
let btnEdit: HTMLButtonElement | null;
let btnStartFloating: HTMLButtonElement | null;
let timerControls: HTMLElement | null;
let btnTimerStart: HTMLButtonElement | null;
let btnTimerPause: HTMLButtonElement | null;
let btnTimerReset: HTMLButtonElement | null;

// Settings view
let btnBack: HTMLButtonElement | null;
let btnSignout: HTMLButtonElement | null;
let fontSizeSlider: HTMLInputElement | null;
let fontSizeValue: HTMLElement | null;
let scrollSpeedSlider: HTMLInputElement | null;
let scrollSpeedValue: HTMLElement | null;
let scrollSpeedGroup: HTMLElement | null;
let opacitySlider: HTMLInputElement | null;
let opacityValue: HTMLElement | null;

// =============================================================================
// INITIALIZATION
// =============================================================================

window.addEventListener("DOMContentLoaded", async () => {
  initializeElements();
  detectPlatform();
  setupEventListeners();
  setupNotesInputHighlighting();
  await loadSettings();
  await loadSavedNotes();
  await checkAuthStatus();
  setupDeepLinkListener();
});

function initializeElements() {
  // Views
  viewSignin = document.getElementById("view-signin");
  viewNotes = document.getElementById("view-notes");
  viewSettings = document.getElementById("view-settings");

  // Sign in
  btnSignin = document.getElementById("btn-signin") as HTMLButtonElement;

  // Notes view
  userGreeting = document.getElementById("user-greeting");
  btnSettings = document.getElementById("btn-settings") as HTMLButtonElement;
  notesInput = document.getElementById("notes-input") as HTMLTextAreaElement;
  notesInputHighlight = document.getElementById("notes-input-highlight");
  notesInputWrapper = document.getElementById("notes-input-wrapper");
  btnEdit = document.getElementById("btn-edit") as HTMLButtonElement;
  btnStartFloating = document.getElementById("btn-start-floating") as HTMLButtonElement;
  timerControls = document.getElementById("timer-controls");
  btnTimerStart = document.getElementById("btn-timer-start") as HTMLButtonElement;
  btnTimerPause = document.getElementById("btn-timer-pause") as HTMLButtonElement;
  btnTimerReset = document.getElementById("btn-timer-reset") as HTMLButtonElement;

  // Settings view
  btnBack = document.getElementById("btn-back") as HTMLButtonElement;
  btnSignout = document.getElementById("btn-signout") as HTMLButtonElement;
  fontSizeSlider = document.getElementById("font-size-slider") as HTMLInputElement;
  fontSizeValue = document.getElementById("font-size-value");
  scrollSpeedSlider = document.getElementById("scroll-speed-slider") as HTMLInputElement;
  scrollSpeedValue = document.getElementById("scroll-speed-value");
  scrollSpeedGroup = document.getElementById("scroll-speed-group");
  opacitySlider = document.getElementById("opacity-slider") as HTMLInputElement;
  opacityValue = document.getElementById("opacity-value");
}

function detectPlatform() {
  // Detect platform from Tauri
  const platform = (window as any).__TAURI_INTERNALS__?.metadata?.currentPlatform;
  isAndroid = platform === "android";
  isIOS = platform === "ios";

  // Fallback detection via user agent
  if (!isAndroid && !isIOS) {
    const ua = navigator.userAgent.toLowerCase();
    isAndroid = ua.includes("android");
    isIOS = /iphone|ipad|ipod/.test(ua);
  }

  // Hide scroll speed on Android (only for iOS teleprompter)
  if (isAndroid && scrollSpeedGroup) {
    scrollSpeedGroup.classList.add("hidden");
  }
}

// =============================================================================
// EVENT LISTENERS
// =============================================================================

function setupEventListeners() {
  // Sign in button
  btnSignin?.addEventListener("click", handleSignIn);

  // Settings button
  btnSettings?.addEventListener("click", () => showView("settings"));

  // Back button
  btnBack?.addEventListener("click", () => showView("notes"));

  // Sign out button
  btnSignout?.addEventListener("click", handleSignOut);

  // Edit button
  btnEdit?.addEventListener("click", toggleEditMode);

  // Start PiP teleprompter button
  btnStartFloating?.addEventListener("click", startPiPTeleprompter);

  // Timer buttons
  btnTimerStart?.addEventListener("click", startTimer);
  btnTimerPause?.addEventListener("click", pauseTimer);
  btnTimerReset?.addEventListener("click", resetTimer);

  // Settings sliders
  fontSizeSlider?.addEventListener("input", handleFontSizeChange);
  scrollSpeedSlider?.addEventListener("input", handleScrollSpeedChange);
  opacitySlider?.addEventListener("input", handleOpacityChange);
}

// =============================================================================
// VIEW MANAGEMENT
// =============================================================================

function showView(view: ViewName) {
  _currentView = view;

  // Hide all views
  viewSignin?.classList.remove("active");
  viewNotes?.classList.remove("active");
  viewSettings?.classList.remove("active");

  // Show selected view
  switch (view) {
    case "signin":
      viewSignin?.classList.add("active");
      break;
    case "notes":
      viewNotes?.classList.add("active");
      break;
    case "settings":
      viewSettings?.classList.add("active");
      break;
  }
}

// =============================================================================
// AUTHENTICATION
// =============================================================================

async function checkAuthStatus() {
  try {
    const isAuthenticated = await invoke<boolean>("get_auth_status");
    if (isAuthenticated) {
      const userInfo = await invoke<UserInfo>("get_user_info");
      updateGreeting(userInfo?.name || "");
      showView("notes");
    } else {
      showView("signin");
    }
  } catch (error) {
    console.error("Error checking auth status:", error);
    showView("signin");
  }
}

async function handleSignIn() {
  try {
    await invoke("start_login");
  } catch (error) {
    console.error("Error starting login:", error);
  }
}

async function handleSignOut() {
  try {
    await invoke("logout");
    showView("signin");
  } catch (error) {
    console.error("Error signing out:", error);
  }
}

function updateGreeting(name: string) {
  if (!userGreeting) return;
  const hour = new Date().getHours();
  let greeting = "Good evening";
  if (hour >= 5 && hour < 12) greeting = "Good morning";
  else if (hour >= 12 && hour < 17) greeting = "Good afternoon";

  const firstName = name.split(" ")[0] || "";
  userGreeting.textContent = firstName ? `${greeting}, ${firstName}` : greeting;
}

function setupDeepLinkListener() {
  listen("auth-status", (event: any) => {
    const { authenticated, user_name } = event.payload;
    if (authenticated) {
      updateGreeting(user_name || "");
      showView("notes");
    }
  });
}

// =============================================================================
// NOTES INPUT AND SYNTAX HIGHLIGHTING
// =============================================================================

function setupNotesInputHighlighting() {
  if (!notesInput || !notesInputHighlight) return;

  notesInput.addEventListener("input", () => {
    updateHighlight();
    saveNotes();
    updateButtonVisibility();
  });

  notesInput.addEventListener("scroll", () => {
    if (notesInputHighlight) {
      notesInputHighlight.scrollTop = notesInput!.scrollTop;
    }
  });

  // Initial update
  updateHighlight();
}

function updateHighlight() {
  if (!notesInput || !notesInputHighlight) return;

  const text = notesInput.value;
  if (!text) {
    notesInputHighlight.innerHTML = "";
    return;
  }

  const highlighted = highlightNotes(text);
  notesInputHighlight.innerHTML = highlighted;
}

function highlightNotes(text: string): string {
  // Normalize line breaks
  let safe = text
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/\u2028/g, "\n")
    .replace(/\u2029/g, "\n");

  // Escape HTML
  safe = escapeHtml(safe);

  let cumulativeTime = 0;

  // Pattern for [time mm:ss] syntax
  const timePattern = /\[time\s+(\d{1,2}):(\d{2})\]/gi;

  // Pattern for [note ...] syntax
  const notePattern = /\[note\s+([^\]]+)\]/gi;

  // Replace [time mm:ss]
  safe = safe.replace(timePattern, (_match, minutes, seconds) => {
    const timeInSeconds = parseInt(minutes) * 60 + parseInt(seconds);
    cumulativeTime += timeInSeconds;

    const displayMinutes = Math.floor(cumulativeTime / 60);
    const displaySeconds = cumulativeTime % 60;
    const displayTime = `${String(displayMinutes).padStart(2, "0")}:${String(displaySeconds).padStart(2, "0")}`;

    return `<span class="timestamp" data-time="${cumulativeTime}">[${displayTime}]</span>`;
  });

  // Replace [note ...]
  safe = safe.replace(notePattern, (_match, note) => {
    return `<span class="action-tag">[${note}]</span>`;
  });

  // Convert line breaks
  safe = safe.replace(/\n/g, "<br>");

  return safe;
}

function escapeHtml(text: string): string {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

// =============================================================================
// EDIT MODE
// =============================================================================

function toggleEditMode() {
  isEditMode = !isEditMode;

  if (isEditMode) {
    notesInputWrapper?.classList.add("edit-mode");
    if (notesInput) notesInput.readOnly = false;
    if (btnEdit) btnEdit.textContent = "Save Note";
    notesInput?.focus();
  } else {
    notesInputWrapper?.classList.remove("edit-mode");
    if (notesInput) notesInput.readOnly = true;
    if (btnEdit) btnEdit.textContent = "Edit Note";
  }

  resetTimer();
  updateButtonVisibility();
}

function updateButtonVisibility() {
  if (!notesInput) return;

  const hasContent = notesInput.value.trim().length > 0;
  const hasTimePattern = /\[time\s+\d{1,2}:\d{2}\]/i.test(notesInput.value);

  // Edit button
  if (hasContent) {
    btnEdit?.classList.remove("hidden");
  } else {
    btnEdit?.classList.add("hidden");
  }

  // Start floating button
  if (hasContent && !isEditMode) {
    btnStartFloating?.classList.remove("hidden");
  } else {
    btnStartFloating?.classList.add("hidden");
  }

  // Timer controls (Android only)
  if (isAndroid && hasTimePattern && !isEditMode) {
    timerControls?.classList.remove("hidden");
    updateTimerButtonVisibility();
  } else {
    timerControls?.classList.add("hidden");
  }
}

// =============================================================================
// TIMER
// =============================================================================

function startTimer() {
  if (timerState === "running") return;

  timerState = "running";
  updateTimerButtonVisibility();

  const timestamps = notesInputHighlight?.querySelectorAll(".timestamp[data-time]");
  if (!timestamps) return;

  timestamps.forEach((timestamp) => {
    let remainingSeconds = parseInt(
      timestamp.getAttribute("data-remaining") || timestamp.getAttribute("data-time") || "0"
    );

    const interval = window.setInterval(() => {
      if (timerState !== "running") {
        clearInterval(interval);
        return;
      }

      remainingSeconds--;
      timestamp.setAttribute("data-remaining", String(remainingSeconds));

      const minutes = Math.floor(Math.abs(remainingSeconds) / 60);
      const seconds = Math.abs(remainingSeconds) % 60;
      const displayTime = `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;

      if (remainingSeconds < 0) {
        timestamp.textContent = `[-${displayTime}]`;
        timestamp.classList.add("time-overtime");
        timestamp.classList.remove("time-warning");
      } else if (remainingSeconds < 10) {
        timestamp.textContent = `[${displayTime}]`;
        timestamp.classList.add("time-warning");
        timestamp.classList.remove("time-overtime");
      } else {
        timestamp.textContent = `[${displayTime}]`;
        timestamp.classList.remove("time-warning", "time-overtime");
      }
    }, 1000);

    timerIntervals.push(interval);
  });
}

function pauseTimer() {
  if (timerState !== "running") return;

  timerState = "paused";
  stopAllTimers();
  updateTimerButtonVisibility();
}

function resetTimer() {
  stopAllTimers();
  timerState = "stopped";

  const timestamps = notesInputHighlight?.querySelectorAll(".timestamp[data-time]");
  if (!timestamps) return;

  timestamps.forEach((timestamp) => {
    const originalTime = parseInt(timestamp.getAttribute("data-time") || "0");
    timestamp.setAttribute("data-remaining", String(originalTime));

    const minutes = Math.floor(originalTime / 60);
    const seconds = originalTime % 60;
    const displayTime = `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;

    timestamp.textContent = `[${displayTime}]`;
    timestamp.classList.remove("time-warning", "time-overtime");
  });

  updateTimerButtonVisibility();
}

function stopAllTimers() {
  timerIntervals.forEach((interval) => clearInterval(interval));
  timerIntervals = [];
}

function updateTimerButtonVisibility() {
  switch (timerState) {
    case "stopped":
      btnTimerStart?.classList.remove("hidden");
      btnTimerPause?.classList.add("hidden");
      btnTimerReset?.classList.add("hidden");
      break;
    case "running":
      btnTimerStart?.classList.add("hidden");
      btnTimerPause?.classList.remove("hidden");
      btnTimerReset?.classList.remove("hidden");
      break;
    case "paused":
      btnTimerStart?.classList.remove("hidden");
      btnTimerPause?.classList.add("hidden");
      btnTimerReset?.classList.remove("hidden");
      break;
  }
}

// =============================================================================
// PIP TELEPROMPTER
// =============================================================================

async function startPiPTeleprompter() {
  if (!notesInput) return;

  const content = notesInput.value;
  if (!content.trim()) return;

  try {
    await invoke("start_pip_teleprompter", {
      content,
      fontSize: settings.fontSize,
      defaultScrollSpeed: settings.scrollSpeed,
      opacity: settings.opacity / 100,
    });
  } catch (error) {
    console.error("Error starting PiP teleprompter:", error);
  }
}

async function pausePiPTeleprompter() {
  try {
    await invoke("pause_pip_teleprompter");
  } catch (error) {
    console.error("Error pausing PiP:", error);
  }
}

async function resumePiPTeleprompter() {
  try {
    await invoke("resume_pip_teleprompter");
  } catch (error) {
    console.error("Error resuming PiP:", error);
  }
}

async function stopPiPTeleprompter() {
  try {
    await invoke("stop_pip_teleprompter");
  } catch (error) {
    console.error("Error stopping PiP:", error);
  }
}

// =============================================================================
// SETTINGS
// =============================================================================

function handleFontSizeChange() {
  if (!fontSizeSlider || !fontSizeValue) return;

  const value = parseInt(fontSizeSlider.value);
  settings.fontSize = value;
  fontSizeValue.textContent = `${value}px`;

  // Update notes preview font size
  if (notesInput) notesInput.style.fontSize = `${value}px`;
  if (notesInputHighlight) notesInputHighlight.style.fontSize = `${value}px`;

  saveSettings();
}

function handleScrollSpeedChange() {
  if (!scrollSpeedSlider || !scrollSpeedValue) return;

  const value = parseInt(scrollSpeedSlider.value) / 10;
  settings.scrollSpeed = value;
  scrollSpeedValue.textContent = `${value.toFixed(1)}x`;

  saveSettings();
}

function handleOpacityChange() {
  if (!opacitySlider || !opacityValue) return;

  const value = parseInt(opacitySlider.value);
  settings.opacity = value;
  opacityValue.textContent = `${value}%`;

  saveSettings();
}

async function loadSettings() {
  try {
    const savedSettings = await invoke<Settings | null>("get_settings");
    if (savedSettings) {
      settings = savedSettings;

      // Update UI
      if (fontSizeSlider) fontSizeSlider.value = String(settings.fontSize);
      if (fontSizeValue) fontSizeValue.textContent = `${settings.fontSize}px`;
      if (scrollSpeedSlider) scrollSpeedSlider.value = String(settings.scrollSpeed * 10);
      if (scrollSpeedValue) scrollSpeedValue.textContent = `${settings.scrollSpeed.toFixed(1)}x`;
      if (opacitySlider) opacitySlider.value = String(settings.opacity);
      if (opacityValue) opacityValue.textContent = `${settings.opacity}%`;

      // Apply font size
      if (notesInput) notesInput.style.fontSize = `${settings.fontSize}px`;
      if (notesInputHighlight) notesInputHighlight.style.fontSize = `${settings.fontSize}px`;
    }
  } catch (error) {
    console.log("No saved settings found, using defaults");
  }
}

async function saveSettings() {
  try {
    await invoke("save_settings", { settings });
  } catch (error) {
    console.error("Error saving settings:", error);
  }
}

// =============================================================================
// NOTES PERSISTENCE
// =============================================================================

async function loadSavedNotes() {
  try {
    const savedNotes = await invoke<string | null>("get_notes");
    if (savedNotes && notesInput) {
      notesInput.value = savedNotes;
      updateHighlight();
      updateButtonVisibility();
    }
  } catch (error) {
    console.log("No saved notes found");
  }
}

async function saveNotes() {
  if (!notesInput) return;

  try {
    await invoke("save_notes", { content: notesInput.value });
  } catch (error) {
    console.error("Error saving notes:", error);
  }
}
