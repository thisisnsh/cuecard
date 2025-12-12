// Google Slides Tracker - Background Service Worker
// Monitors connection status and manages extension state

const API_ENDPOINT = 'http://localhost:3642';
let connectionStatus = 'unknown';

// Get browser API (cross-browser compatibility)
const browserAPI = typeof browser !== 'undefined' ? browser : chrome;

// Check API connection status
async function checkConnection() {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000);

    const response = await fetch(`${API_ENDPOINT}/health`, {
      method: 'GET',
      signal: controller.signal
    });

    clearTimeout(timeoutId);
    connectionStatus = response.ok ? 'connected' : 'error';
  } catch (error) {
    if (error.name === 'AbortError') {
      connectionStatus = 'timeout';
    } else {
      connectionStatus = 'disconnected';
    }
  }
  updateBadge();
}

// Update extension badge based on connection status
function updateBadge() {
  const badgeConfig = {
    connected: { text: '', color: '#4CAF50' },
    disconnected: { text: '!', color: '#F44336' },
    error: { text: 'E', color: '#FF9800' },
    timeout: { text: '?', color: '#9E9E9E' },
    unknown: { text: '?', color: '#9E9E9E' }
  };

  const config = badgeConfig[connectionStatus] || badgeConfig.unknown;

  try {
    browserAPI.action.setBadgeText({ text: config.text });
    browserAPI.action.setBadgeBackgroundColor({ color: config.color });
  } catch (error) {
    console.warn('[SlidesTracker Background] Failed to update badge:', error);
  }
}

// Send slide info to API via POST (background script can make HTTP requests from HTTPS pages)
async function sendSlideInfoToAPI(slideInfo) {
  const url = `${API_ENDPOINT}/slides`;

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify(slideInfo)
    });

    if (response.ok) {
      console.log('[SlidesTracker Background] Successfully sent slide info:', slideInfo);
      return { success: true };
    }
    console.warn(`[SlidesTracker Background] Server returned ${response.status}`);
    return { success: false, error: `Server returned ${response.status}` };
  } catch (error) {
    console.error('[SlidesTracker Background] Failed to send slide info:', error.message);
    return { success: false, error: error.message };
  }
}

// Listen for messages from content script
browserAPI.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'SLIDE_CHANGE') {
    console.log('[SlidesTracker Background] Received slide change:', message.data);
    // Make the API call from background script to avoid mixed content issues
    sendSlideInfoToAPI(message.data).then(result => {
      sendResponse(result);
    });
    return true; // Keep message channel open for async response
  }

  if (message.type === 'GET_CONNECTION_STATUS') {
    sendResponse({ status: connectionStatus });
  }

  return true; // Keep message channel open for async response
});

// Check connection periodically
setInterval(checkConnection, 30000); // Every 30 seconds

// Initial check on startup
checkConnection();

console.log('[SlidesTracker Background] Service worker started');
