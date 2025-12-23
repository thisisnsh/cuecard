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

function getPresentationIdFromUrl(url) {
  const match = url.match(/\/presentation\/d\/([a-zA-Z0-9_-]+)/);
  return match ? match[1] : null;
}

function getSlideIdFromUrl(url) {
  const hashMatch = url.match(/#slide=id\.([a-zA-Z0-9_-]+)/);
  if (hashMatch) {
    return hashMatch[1];
  }

  const queryMatch = url.match(/[?&]slide=id\.([a-zA-Z0-9_-]+)/);
  if (queryMatch) {
    return queryMatch[1];
  }

  return null;
}

function detectModeFromUrl(url) {
  if (url.includes('/present')) {
    return 'slideshow';
  }
  if (url.includes('/edit') || url.includes('/view')) {
    return 'edit';
  }
  if (url.includes('/pub')) {
    return 'published';
  }
  return 'unknown';
}

function buildSlideInfoFromTab(tab) {
  if (!tab?.url) return null;

  const presentationId = getPresentationIdFromUrl(tab.url);
  const slideId = getSlideIdFromUrl(tab.url);

  if (!presentationId || !slideId) {
    return null;
  }

  let title = tab.title || 'Unknown';
  title = title.replace(' - Google Slides', '').replace(' - Google Präsentationen', '');

  return {
    presentationId,
    slideId,
    slideNumber: 0,
    title,
    mode: detectModeFromUrl(tab.url),
    timestamp: Date.now(),
    url: tab.url,
    forceRefresh: true
  };
}

async function sendForceRefreshForActiveTab() {
  try {
    const [tab] = await browserAPI.tabs.query({ active: true, currentWindow: true });
    const slideInfo = buildSlideInfoFromTab(tab);
    if (!slideInfo) {
      return;
    }

    await browserAPI.runtime.sendMessage({
      type: 'FORCE_REFRESH',
      data: slideInfo
    });
  } catch (error) {
    console.error('Error sending force refresh:', error);
  }
}

// Event listeners
document.getElementById('refresh-btn').addEventListener('click', async () => {
  updateStatus();
  getCurrentTabInfo();
  await sendForceRefreshForActiveTab();
});

// Initialize on popup open
updateStatus();
getCurrentTabInfo();
