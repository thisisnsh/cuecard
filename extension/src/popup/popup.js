// Google Slides Tracker - Popup Script

const browserAPI = typeof browser !== 'undefined' ? browser : chrome;

async function updateStatus() {
  const statusEl = document.getElementById('server-status');

  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 3000);

    const response = await fetch('http://localhost:3000/health', {
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

// Event listeners
document.getElementById('refresh-btn').addEventListener('click', () => {
  updateStatus();
  getCurrentTabInfo();
});

// Initialize on popup open
updateStatus();
getCurrentTabInfo();
