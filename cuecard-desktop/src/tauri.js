/**
 * Everything that crosses into the Tauri backend: commands, events, the
 * persistent store, analytics, Google Slides and the window itself.
 * Nothing in here knows what the interface looks like.
 */

const T = window.__TAURI__ || {};
if (!window.__TAURI__) {
  console.error("Tauri runtime not available — run with 'npm run tauri dev' or as a built app.");
}

export const invoke = T.core?.invoke;
export const listen = T.event?.listen;
const openUrlNative = T.opener?.openUrl;
const getCurrentWindow = T.window?.getCurrentWindow;
const checkForUpdate = T.updater?.check;
const relaunch = T.process?.relaunch;
const openDialog = T.dialog?.open;
const saveDialog = T.dialog?.save;
const readTextFile = T.fs?.readTextFile;
const writeTextFile = T.fs?.writeTextFile;

async function call(command, args) {
  if (!invoke) return null;
  return invoke(command, args);
}

// =============================================================================
// PLATFORM
// =============================================================================

export function platformInfo() {
  const source = navigator.userAgentData?.platform || navigator.platform || navigator.userAgent || '';
  if (/win/i.test(source)) return { platform: 'windows', operatingSystem: 'windows' };
  if (/mac/i.test(source)) return { platform: 'macos', operatingSystem: 'mac' };
  if (/linux/i.test(source)) return { platform: 'linux', operatingSystem: 'linux' };
  return { platform: 'unknown', operatingSystem: 'unknown' };
}

export const isMac = platformInfo().platform === 'macos';

export async function appVersion() {
  try {
    return (await T.app?.getVersion?.()) || '1.5.0';
  } catch {
    return '1.5.0';
  }
}

// =============================================================================
// STORE
// =============================================================================

let store = null;

export async function initStore() {
  try {
    const Store = T.store?.Store;
    if (Store) store = await Store.load('cuecard-store.json');
  } catch (error) {
    console.error('Error initializing store:', error);
  }
}

export async function getStored(key) {
  if (!store) return null;
  try {
    const value = await store.get(key);
    return value === undefined ? null : value;
  } catch (error) {
    console.error(`Error reading ${key}:`, error);
    return null;
  }
}

export async function setStored(key, value) {
  if (!store) return;
  try {
    await store.set(key, value);
    await store.save();
  } catch (error) {
    console.error(`Error writing ${key}:`, error);
  }
}

// =============================================================================
// ANALYTICS
// =============================================================================

export async function initAnalytics() {
  try {
    await call('init_analytics', platformInfo());
  } catch (error) {
    console.debug('Analytics init error:', error);
  }
}

export function track(eventName, params) {
  const payload = { eventName };
  if (params && Object.keys(params).length) payload.params = params;
  call('send_event', payload).catch((error) => console.debug('Analytics error:', error));
}

export const trackScreen = (name) =>
  track('screen_view', { screen_name: name, page_title: `CueCard ${name}`, screen_class: 'CueCard' });
export const trackClick = (button, screen, params) =>
  track('button_click', { button_name: button, screen_name: screen, ...params });
export const trackSetting = (setting, value) => track('setting_change', { setting_name: setting, setting_value: String(value) });

export async function trackFirstLaunch() {
  try {
    if (await call('check_and_mark_first_open')) track('app_first_launch');
  } catch (error) {
    console.debug('Analytics first launch error:', error);
  }
}

// =============================================================================
// GOOGLE SLIDES
// =============================================================================

/** Opens the browser to ask for read access to the deck. The result arrives as
 *  a `slides-authorized` event. */
export const connectSlides = () => call('connect_slides');

export const hasSlidesScope = async () => Boolean(await call('has_slides_scope').catch(() => false));

export async function currentSlide() {
  try {
    const slide = await call('get_current_slide');
    if (!slide) return null;
    const notes = await call('get_current_notes');
    return { slide, notes: notes || '' };
  } catch (error) {
    console.error('Error reading the current slide:', error);
    return null;
  }
}

export const refreshSlideNotes = () => call('refresh_notes');

// =============================================================================
// WINDOW
// =============================================================================

export const setInvisible = (enabled) =>
  call('set_screenshot_protection', { enabled }).catch((e) => console.error('Invisibility:', e));

export function currentWindow() {
  return getCurrentWindow ? getCurrentWindow() : null;
}

export async function closeWindow() {
  await currentWindow()?.close();
}

export async function openUrl(url) {
  try {
    if (openUrlNative) await openUrlNative(url);
    else window.open(url, '_blank', 'noopener,noreferrer');
  } catch (error) {
    console.error('Error opening link:', error);
  }
}

// =============================================================================
// FILES
// =============================================================================

export const filesAvailable = () => Boolean(openDialog && readTextFile && saveDialog && writeTextFile);

export async function pickTextFile() {
  const path = await openDialog({
    multiple: false,
    directory: false,
    filters: [{ name: 'Script', extensions: ['txt', 'md', 'markdown', 'text'] }],
  });
  if (!path) return null;
  return { path: String(path), text: await readTextFile(path) };
}

export async function saveTextFile(defaultName, text) {
  const path = await saveDialog({ defaultPath: defaultName, filters: [{ name: 'Script', extensions: ['txt'] }] });
  if (!path) return false;
  await writeTextFile(path, text);
  return true;
}

// =============================================================================
// NOTIFICATIONS
// =============================================================================

/**
 * The notifications worker, fetched through the backend rather than the window.
 *
 * The worker serves the phone apps, which use native HTTP and are not subject
 * to CORS. A web view is, and the worker sends no `Access-Control-Allow-Origin`
 * — so a fetch from here is blocked before it can be read. Going through Rust
 * sidesteps the browser's rules instead of asking the mobile worker to change.
 *
 * Returns the raw JSON body, or null if it could not be had.
 */
export async function fetchNotificationsPayload() {
  try {
    return (await call('fetch_notifications')) || null;
  } catch (error) {
    console.debug('Notifications fetch failed:', error);
    return null;
  }
}

// =============================================================================
// UPDATES
// =============================================================================

export async function findUpdate() {
  if (!checkForUpdate) return null;
  try {
    const update = await checkForUpdate();
    return update?.available ? update : null;
  } catch (error) {
    console.debug('Update check failed:', error);
    return null;
  }
}

/** Download and install, reporting progress as 0–1, then relaunch. */
export async function installUpdate(update, onProgress) {
  let total = 0;
  let received = 0;
  await update.downloadAndInstall((event) => {
    if (event.event === 'Started') total = event.data.contentLength || 0;
    if (event.event === 'Progress') {
      received += event.data.chunkLength;
      if (total) onProgress?.(received / total);
    }
  });
  await relaunch?.();
}
