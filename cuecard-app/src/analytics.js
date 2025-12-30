/**
 * Firebase Analytics Module for CueCard
 *
 * Uses a separate Firebase project dedicated to analytics.
 * This keeps analytics isolated from the main backend Firebase project.
 *
 * Tracks:
 * - DAU/MAU (automatic with Firebase Analytics)
 * - User sessions and engagement (automatic)
 * - Custom events for user behavior
 */

import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.7.0/firebase-app.js';
import {
  getAnalytics,
  logEvent,
  setUserId
} from 'https://www.gstatic.com/firebasejs/12.7.0/firebase-analytics.js';

const { invoke } = window.__TAURI__.core;

let analytics = null;
let isInitialized = false;

/**
 * Initialize Firebase Analytics
 * Call this once when the app starts
 */
export async function initAnalytics() {
  if (isInitialized) return;

  try {
    console.log('[Analytics] Starting initialization...');
    console.log('[Analytics] Window location:', window.location.href);

    // Fetch config from backend via Tauri command
    const config = await invoke('get_analytics_config');
    console.log('[Analytics] Config received:', config ? 'yes' : 'no');

    if (!config) {
      console.warn('[Analytics] Config not found. Analytics disabled.');
      return;
    }

    // Check if config is properly set up (config uses snake_case from Rust)
    if (!config.measurement_id || config.measurement_id.startsWith('G-XXXX')) {
      console.warn('[Analytics] measurement_id not configured. Update firebase-config.json');
      return;
    }

    console.log('[Analytics] Measurement ID:', config.measurement_id);

    // Initialize Firebase (map snake_case from Rust to camelCase for Firebase SDK)
    const firebaseConfig = {
      apiKey: config.api_key,
      authDomain: config.auth_domain,
      projectId: config.project_id,
      appId: config.app_id,
      measurementId: config.measurement_id
    };

    console.log('[Analytics] Initializing Firebase app...');
    const app = initializeApp(firebaseConfig, 'analytics');

    console.log('[Analytics] Getting analytics instance...');
    analytics = getAnalytics(app);
    isInitialized = true;

    console.log('[Analytics] Firebase Analytics initialized successfully');
  } catch (error) {
    console.error('[Analytics] Initialization failed:', error);
    console.error('[Analytics] Error stack:', error.stack);
  }
}

/**
 * Check if analytics is ready
 */
function isReady() {
  return isInitialized && analytics !== null;
}

// =============================================================================
// USER IDENTIFICATION (for DAU/MAU tracking)
// =============================================================================

/**
 * Set user ID for analytics (hashed for privacy)
 * Call after successful login
 * @param {string} email - User's email
 */
export function setAnalyticsUserId(email) {
  if (!isReady() || !email) return;

  try {
    const hashedId = hashString(email);
    setUserId(analytics, hashedId);
    console.log('Analytics: User ID set');
  } catch (e) {
    console.debug('Analytics setUserId error:', e);
  }
}

/**
 * Clear user ID on logout (internal use)
 */
function clearAnalyticsUserId() {
  if (!isReady()) return;

  try {
    setUserId(analytics, null);
  } catch (e) {
    console.debug('Analytics clearUserId error:', e);
  }
}

// =============================================================================
// APP LIFECYCLE EVENTS
// =============================================================================

/**
 * Track app open
 */
export function trackAppOpen() {
  if (!isReady()) return;

  try {
    logEvent(analytics, 'app_open', {
      platform: getPlatform()
    });
  } catch (e) {
    console.debug('Analytics error:', e);
  }
}

/**
 * Track app session start (called after successful auth check)
 */
export function trackSessionStart() {
  if (!isReady()) return;

  try {
    logEvent(analytics, 'session_start', {
      platform: getPlatform()
    });
  } catch (e) {
    console.debug('Analytics error:', e);
  }
}

// =============================================================================
// AUTHENTICATION EVENTS
// =============================================================================

/**
 * Track login
 * @param {string} method - Login method (e.g., 'google')
 */
export function trackLogin(method = 'google') {
  if (!isReady()) return;

  try {
    logEvent(analytics, 'login', { method });
  } catch (e) {
    console.debug('Analytics error:', e);
  }
}

/**
 * Track logout
 */
export function trackLogout() {
  if (!isReady()) return;

  try {
    logEvent(analytics, 'logout');
    clearAnalyticsUserId();
  } catch (e) {
    console.debug('Analytics error:', e);
  }
}

// =============================================================================
// NAVIGATION EVENTS
// =============================================================================

/**
 * Track screen/view navigation
 * @param {string} screenName - Name of the screen
 */
export function trackScreenView(screenName) {
  if (!isReady()) return;

  try {
    logEvent(analytics, 'screen_view', {
      screen_name: screenName
    });
  } catch (e) {
    console.debug('Analytics error:', e);
  }
}

// =============================================================================
// FEATURE USAGE EVENTS
// =============================================================================

/**
 * Track notes paste (user chose to paste their own notes)
 */
export function trackNotesPaste() {
  if (!isReady()) return;

  try {
    logEvent(analytics, 'notes_paste');
  } catch (e) {
    console.debug('Analytics error:', e);
  }
}

/**
 * Track slides sync (user chose to sync from Google Slides)
 */
export function trackSlidesSync() {
  if (!isReady()) return;

  try {
    logEvent(analytics, 'slides_sync');
  } catch (e) {
    console.debug('Analytics error:', e);
  }
}

/**
 * Track timer usage
 * @param {string} action - 'start', 'pause', 'reset'
 */
export function trackTimerAction(action) {
  if (!isReady()) return;

  try {
    logEvent(analytics, 'timer_action', { action });
  } catch (e) {
    console.debug('Analytics error:', e);
  }
}

/**
 * Track settings change
 * @param {string} setting - Setting name
 * @param {any} value - New value
 */
export function trackSettingChange(setting, value) {
  if (!isReady()) return;

  try {
    logEvent(analytics, 'setting_change', {
      setting_name: setting,
      setting_value: String(value)
    });
  } catch (e) {
    console.debug('Analytics error:', e);
  }
}

/**
 * Track slide update received from extension
 */
export function trackSlideUpdate() {
  if (!isReady()) return;

  try {
    logEvent(analytics, 'slide_update');
  } catch (e) {
    console.debug('Analytics error:', e);
  }
}

/**
 * Track edit/save note action
 * @param {string} action - 'edit' or 'save'
 */
export function trackEditAction(action) {
  if (!isReady()) return;

  try {
    logEvent(analytics, 'edit_action', { action });
  } catch (e) {
    console.debug('Analytics error:', e);
  }
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/**
 * Get current platform
 */
function getPlatform() {
  const platform = navigator.userAgentData?.platform || navigator.platform || '';
  if (/win/i.test(platform)) return 'windows';
  if (/mac/i.test(platform)) return 'macos';
  if (/linux/i.test(platform)) return 'linux';
  return 'unknown';
}

/**
 * Simple hash function for privacy
 * @param {string} str - String to hash
 */
function hashString(str) {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  return 'user_' + Math.abs(hash).toString(16);
}
