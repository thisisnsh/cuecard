// CueCard Extension - Popup Script

const browserAPI = typeof browser !== 'undefined' ? browser : chrome;

async function updateStatus() {
  const statusEl = document.getElementById('server-status');

  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 3642);

    const response = await fetch('http://localhost:3642/health', {
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    if (response.ok) {
      statusEl.textContent = 'Connected';
      statusEl.className = 'status connected';
    } else {
      statusEl.textContent = 'Error';
      statusEl.className = 'status error';
    }
  } catch (error) {
    statusEl.textContent = 'Disconnected';
    statusEl.className = 'status disconnected';
  }
}

async function getCurrentTabInfo() {
  try {
    const [tab] = await browserAPI.tabs.query({ active: true, currentWindow: true });

    const titleEl = document.getElementById('presentation-title');
    const slideEl = document.getElementById('current-slide');

    if (tab && tab.url && tab.url.includes('docs.google.com/presentation')) {
      // Extract presentation title from tab title
      let title = tab.title || 'Unknown';
      title = title.replace(' - Google Slides', '').replace(' - Google Präsentationen', '');
      titleEl.textContent = title;

      // Extract slide info from URL
      let slideInfo = 'Unknown';

      // Check hash (edit mode)
      const hashMatch = tab.url.match(/#slide=id\.([a-zA-Z0-9_-]+)/);
      if (hashMatch) {
        slideInfo = `Slide ID: ${hashMatch[1]}`;
      }

      // Check query param (slideshow mode)
      const queryMatch = tab.url.match(/[?&]slide=id\.([a-zA-Z0-9_-]+)/);
      if (queryMatch) {
        slideInfo = `Slide ID: ${queryMatch[1]}`;
      }

      slideEl.textContent = slideInfo;
    } else {
      titleEl.textContent = 'Not on Google Slides';
      slideEl.textContent = '-';
    }
  } catch (error) {
    console.error('Error getting tab info:', error);
  }
}

// Load and handle block navigation setting
async function loadBlockNavigationSetting() {
  const blockNavCheckbox = document.getElementById('block-navigation');
  try {
    const result = await browserAPI.storage.local.get('blockNavigation');
    blockNavCheckbox.checked = result.blockNavigation || false;
  } catch (error) {
    console.error('Error loading setting:', error);
  }
}

async function saveBlockNavigationSetting(enabled) {
  try {
    await browserAPI.storage.local.set({ blockNavigation: enabled });
    // Notify content script of the change
    const [tab] = await browserAPI.tabs.query({ active: true, currentWindow: true });
    if (tab && tab.url && tab.url.includes('docs.google.com/presentation')) {
      browserAPI.tabs.sendMessage(tab.id, {
        type: 'BLOCK_NAVIGATION_CHANGED',
        enabled: enabled
      });
    }
  } catch (error) {
    console.error('Error saving setting:', error);
  }
}

// Event listeners
document.getElementById('refresh-btn').addEventListener('click', () => {
  updateStatus();
  getCurrentTabInfo();
});

document.getElementById('block-navigation').addEventListener('change', (e) => {
  saveBlockNavigationSetting(e.target.checked);
});

// Initialize on popup open
updateStatus();
getCurrentTabInfo();
loadBlockNavigationSetting();
