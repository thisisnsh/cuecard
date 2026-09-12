/**
 * CueCard for desktop.
 *
 * The phone app has two screens — the one you write on and the one you present
 * from — and this has the same two, with the room a window gives used for the
 * things a phone has nowhere to put: your saved scripts and a live Google
 * Slides deck, side by side in a sidebar.
 */

import { icon, hydrateIcons } from './icons.js';
import * as T from './tauri.js';
import {
  COUNTDOWN_RANGE,
  LPM_RANGE,
  clamp,
  hadStoredTimer,
  loadSettings,
  onSettingsChange,
  resetSettings,
  setSetting,
  settings,
  timerDuration,
  watchSystemTheme,
} from './settings.js';
import * as notes from './notes.js';
import { createEditor } from './editor.js';
import { createPrompter } from './prompter.js';
import * as ui from './ui.js';
import * as notices from './notifications.js';
import { CUE_COLORS, normalizingTags, suggestedFileName, titleForFileName } from './parser.js';

const $ = (id) => document.getElementById(id);

const LINKS = {
  site: 'https://cuecard.dev',
  extension: 'https://cuecard.dev/#download',
  source: 'https://github.com/ThisIsNSH/CueCard',
  support: 'mailto:hello@thisisnsh.com',
};

const PLACEHOLDER =
  'Write your script here…\n\nType [ to add a cue — a note to yourself like “[cue smile and pause]” that you read but never say out loud.';

const app = {
  authenticated: false,
  user: { name: '', email: '' },
  /** Which script the detail pane is showing: your own, or the live deck. */
  source: 'script',
  slides: { connected: false, slide: null, notes: '' },
  update: null,
  sidebarOpen: true,
  overlay: false,
  sessionTracked: false,
};

let editor;
let prompter;

// =============================================================================
// START-UP
// =============================================================================

async function boot() {
  document.documentElement.classList.add(`platform-${T.platformInfo().platform}`);
  hydrateIcons();

  await T.initStore();
  await T.initAnalytics();
  await T.initFirestore();

  await loadSettings();
  watchSystemTheme();
  await notes.loadNotes({ seedTimer: seedTimerFromTimeTags });

  editor = createEditor($('editor'), { onChange: onScriptEdited });
  editor.setPlaceholder(PLACEHOLDER);
  editor.setText(notes.state.draft);

  prompter = createPrompter($('screen-prompter'), { onClose: onPrompterClosed });

  buildSwatches();
  wireHome();
  wireSettingsSheet();
  wireKeyboard();

  app.sidebarOpen = (await T.getStored('ui_sidebar_open')) ?? true;
  updateLayout();
  window.addEventListener('resize', updateLayout);

  onSettingsChange(onSettingChanged);
  notes.onNotesChange(renderAll);
  notices.onNotificationsChange(renderNotices);
  await notices.loadNotifications();

  await T.trackFirstLaunch();
  T.track('app_open');

  applyAuth(await T.authStatus());
  await initSlides();
  listenToBackend();
  void startUpdateChecks();

  // Anything the worker wants people to see. It throttles itself, so asking on
  // every launch and every few minutes costs nothing.
  void notices.refreshNotifications();
  setInterval(() => notices.refreshNotifications(), 5 * 60 * 1000);
}

/** Scripts that carried `[time]` tags set the timer, once, on the way past. */
function seedTimerFromTimeTags(seconds) {
  if (hadStoredTimer) return;
  void setSetting('timerMinutes', Math.min(Math.floor(seconds / 60), 59), { track: false, force: true });
  void setSetting('timerSeconds', seconds % 60, { track: false, force: true });
}

// =============================================================================
// AUTHENTICATION
// =============================================================================

function applyAuth({ authenticated, name = '', email = '' }) {
  app.authenticated = authenticated;
  app.user = { name, email };

  $('screen-login').hidden = authenticated;
  $('screen-home').hidden = !authenticated;
  if (!authenticated) prompter.close();

  if (authenticated) {
    T.setAnalyticsUser(email);
    if (email) void T.saveProfile(email, name);
    if (!app.sessionTracked) {
      T.track('start_session');
      app.sessionTracked = true;
    }
    T.trackScreen('home');
    renderAll();
    editor.reset();
  } else {
    T.trackScreen('login');
  }
}

async function signOut() {
  T.track('logout');
  T.clearAnalyticsUser();
  ui.closeSheet();
  await T.logout();
  applyAuth({ authenticated: false });
}

async function deleteAccount() {
  const sure = await ui.confirmAction({
    title: 'Delete Account',
    message: 'Are you sure you want to delete your account? This action cannot be undone.',
    confirmLabel: 'Delete',
    destructive: true,
  });
  if (!sure) return;

  try {
    await T.deleteAccount(app.user.email);
  } catch (error) {
    await ui.showError(String(error.message || error), 'Error');
    return;
  }

  await notes.clearAll();
  await resetSettings();
  editor.setText('');
  await signOut();
}

// =============================================================================
// THE SCRIPT BEING WRITTEN
// =============================================================================

function onScriptEdited(text) {
  notes.setDraft(text);
  renderToolbar();
  renderControls();
  renderSidebar();
}

async function saveScript() {
  if (!notes.hasScript()) return;
  if (!notes.currentNote()) return saveScriptAsNew();
  await notes.saveCurrent();
  ui.showToast('Saved');
  T.trackClick('save_script', 'home');
}

async function saveScriptAsNew() {
  if (!notes.hasScript()) return;
  const title = await ui.promptForText({
    title: 'Save Script',
    message: 'Give this script a name.',
    value: suggestedFileName(null, notes.state.draft),
    placeholder: 'Script name',
    confirmLabel: 'Save',
  });
  if (!title) return;
  await notes.saveAsNew(title);
  ui.showToast('Saved');
  T.trackClick('save_as_new', 'home');
}

/**
 * Before leaving a script with changes in it, ask — a window makes switching
 * scripts easy enough that losing one to a stray click would be too easy too.
 * Returns false if the reader decided to stay.
 */
async function confirmLeavingScript() {
  if (app.source !== 'script' || !notes.hasUnsavedChanges()) return true;

  const note = notes.currentNote();
  const result = await ui.showAlert({
    title: note ? `Save changes to “${note.title}”?` : 'Save this script?',
    message: 'Your changes are lost if you do not save them.',
    actions: [
      { id: 'discard', label: "Don't Save", style: 'destructive' },
      { id: 'cancel', label: 'Cancel', style: 'cancel' },
      { id: 'save', label: 'Save', style: 'preferred' },
    ],
  });

  if (!result) return false;
  if (result.action === 'save') {
    if (note) await notes.saveCurrent();
    else {
      await saveScriptAsNew();
      if (notes.hasUnsavedChanges()) return false;
    }
  }
  return true;
}

/** Leaving is always worth asking about, and an unsaved draft is worth asking twice. */
async function closeApp() {
  const leaving = await ui.confirmAction({
    title: 'Exit CueCard?',
    message: 'The window closes and the prompter stops.',
    confirmLabel: 'Yes',
    cancelLabel: 'No',
    destructive: true,
  });
  if (!leaving) return;
  if (!(await confirmLeavingScript())) return;
  await T.closeWindow();
}

async function newScript() {
  if (!(await confirmLeavingScript())) return;
  await notes.newScript();
  editor.setText('');
  selectSource('script');
  editor.focus();
  T.trackClick('new_script', 'home');
}

async function openScript(id) {
  if (!(await confirmLeavingScript())) return;
  await notes.openNote(id);
  editor.setText(notes.state.draft);
  editor.reset();
  selectSource('script');
}

async function renameScript(id) {
  const note = notes.state.saved.find((n) => n.id === id);
  if (!note) return;
  const title = await ui.promptForText({
    title: 'Rename Script',
    message: 'Give this script a new name.',
    value: note.title,
    placeholder: 'Script name',
    confirmLabel: 'Rename',
  });
  if (title) await notes.renameNote(id, title);
}

async function deleteScript(id) {
  const note = notes.state.saved.find((n) => n.id === id);
  if (!note) return;
  const sure = await ui.confirmAction({
    title: `Delete “${note.title}”?`,
    message: 'This cannot be undone.',
    confirmLabel: 'Delete',
    destructive: true,
  });
  if (!sure) return;
  const wasOpen = notes.state.currentId === id;
  await notes.deleteNote(id);
  if (wasOpen) editor.setText('');
}

// =============================================================================
// FILES
// =============================================================================

async function importScript() {
  if (!T.filesAvailable()) return ui.showError('File access is not available in this build.');
  if (!(await confirmLeavingScript())) return;

  try {
    const picked = await T.pickTextFile();
    if (!picked) return;
    if (!picked.text.trim()) return ui.showError('That file is empty.');

    // Whatever spelling the file was written in, it arrives as [cue ...].
    await notes.importScript(titleForFileName(picked.path), normalizingTags(picked.text));
    editor.setText(notes.state.draft);
    editor.reset();
    selectSource('script');
    ui.showToast('Imported');
    T.trackClick('import_file', 'home');
  } catch (error) {
    await ui.showError("This file couldn't be read as text.");
    console.error(error);
  }
}

async function exportScript() {
  if (!T.filesAvailable()) return ui.showError('File access is not available in this build.');
  if (!notes.hasScript()) return;

  try {
    const name = `${suggestedFileName(notes.currentNote()?.title, notes.state.draft)}.txt`;
    if (await T.saveTextFile(name, normalizingTags(notes.state.draft))) {
      ui.showToast('Exported');
      T.trackClick('export_file', 'home');
    }
  } catch (error) {
    await ui.showError(String(error));
  }
}

// =============================================================================
// GOOGLE SLIDES
// =============================================================================

async function initSlides() {
  app.slides.connected = await T.hasSlidesScope();
  const current = await T.currentSlide();
  if (current) {
    app.slides.slide = current.slide;
    app.slides.notes = current.notes;
  }
  renderSlides();
  renderSidebar();
}

function connectSlides() {
  T.trackClick('connect_slides', 'home');
  T.track('slides_sync');
  void T.startLogin('slides');
}

async function refreshSlides() {
  const button = $('btn-refresh-slides');
  button.disabled = true;
  try {
    await T.refreshSlideNotes();
  } catch (error) {
    console.error('Error refreshing notes:', error);
  } finally {
    button.disabled = false;
  }
}

function onSlideUpdate(payload) {
  const slide = payload?.slide_data;
  if (!slide) return;

  const isNew =
    !app.slides.slide ||
    app.slides.slide.slideId !== slide.slideId ||
    app.slides.slide.presentationId !== slide.presentationId;

  app.slides.slide = slide;
  app.slides.notes = payload.notes || '';
  app.slides.connected = true;
  if (isNew) T.track('slide_update');

  renderSlides();
  renderSidebar();

  // A deck that is already being presented from carries straight on: the new
  // slide starts at its first line, and the talk's clock keeps running.
  if (prompter.isOpen() && prompter.source() === 'slides') {
    prompter.setText(app.slides.notes, {
      fromSlide: isNew,
      title: slide.title || 'Google Slides',
      subtitle: slideLabel(),
    });
  }
}

const slideLabel = () => (app.slides.slide ? `Slide ${app.slides.slide.slideNumber}` : '');

// =============================================================================
// THE PROMPTER
// =============================================================================

function scriptForPrompter() {
  if (app.source === 'slides') {
    return {
      source: 'slides',
      text: app.slides.notes,
      title: app.slides.slide?.title || 'Google Slides',
      subtitle: slideLabel(),
    };
  }
  return {
    source: 'script',
    text: notes.state.draft,
    title: notes.currentNote()?.title || 'Untitled Script',
    subtitle: '',
  };
}

function startPrompter({ play = false } = {}) {
  const script = scriptForPrompter();
  if (!script.text.trim()) return;

  $('screen-home').hidden = true;
  prompter.open(script);
  T.trackScreen('prompter');
  T.track('timer_action', { action: 'open' });
  if (play) prompter.togglePlay();
}

function onPrompterClosed() {
  $('screen-home').hidden = !app.authenticated;
  T.trackScreen('home');
  renderAll();
}

// =============================================================================
// RENDERING
// =============================================================================

/**
 * A notice from the worker, drawn where it asked to be drawn: a card over the
 * script, or a quiet row at the top of Settings.
 */
function renderNotices() {
  renderNotice('homeBanner', $('home-notice'), { row: false });
  const group = $('settings-notice');
  renderNotice('settingsRow', $('settings-notice-cell'), { row: true, group });
}

function renderNotice(surface, host, { row, group }) {
  if (!host) return;
  const notice = notices.notificationFor(surface);

  if (!notice) {
    host.innerHTML = '';
    (group || host).hidden = true;
    return;
  }

  // A settings row has space for one thing to do, and dismissal has its own
  // control, so the X is the action skipped there.
  const actions = row ? notice.actions.filter((a) => a.kind !== 'dismiss').slice(0, 1) : notice.actions;

  host.innerHTML = `
    <div class="notice is-${notice.severity}${row ? ' is-row' : ''}">
      <span class="notice-text">
        <span class="notice-title">${ui.escapeHtml(notice.title)}</span>
        ${notice.body ? `<span class="notice-body">${ui.escapeHtml(notice.body)}</span>` : ''}
        ${actions.length ? `<span class="notice-actions">${actions
          .map((action, index) => `<button class="notice-action" data-action="${index}">${ui.escapeHtml(action.label)}</button>`)
          .join('')}</span>` : ''}
      </span>
      ${notice.dismissible ? `<button class="icon-btn is-small" data-dismiss aria-label="Dismiss">${icon('xmark', 13)}</button>` : ''}
    </div>`;
  (group || host).hidden = false;

  host.querySelector('[data-dismiss]')?.addEventListener('click', () => notices.dismissNotification(notice));
  host.querySelectorAll('.notice-action').forEach((button) => {
    button.addEventListener('click', () => {
      const action = actions[Number(button.dataset.action)];
      notices.logAction(action, notice);
      if (action.kind === 'dismiss') void notices.dismissNotification(notice);
      // Desktop has no store listing, so the download page is the nearest thing.
      else if (action.kind === 'appStore') void T.openUrl(LINKS.site);
      else void T.openUrl(action.url);
    });
  });

  notices.logImpression(notice);
}

function renderAll() {
  renderNotices();
  renderToolbar();
  renderSidebar();
  renderSlides();
  renderControls();
}

function renderToolbar() {
  const title = $('title-main');
  const sub = $('title-sub');

  if (app.source === 'slides') {
    title.textContent = 'Google Slides';
    sub.textContent = app.slides.slide?.title || (app.slides.connected ? 'Waiting for a deck' : 'Not connected');
    sub.hidden = false;
    return;
  }

  const note = notes.currentNote();
  title.textContent = note ? note.title : notes.hasScript() ? 'Untitled Script' : 'CueCard';

  if (note && notes.hasUnsavedChanges()) sub.textContent = 'Edited';
  else if (!note && notes.hasScript()) sub.textContent = 'Not saved';
  else sub.textContent = '';
  sub.hidden = !sub.textContent;
}

function renderSidebar() {
  // Slides
  const slidesRow = $('row-slides');
  slidesRow.classList.toggle('is-selected', app.source === 'slides');
  slidesRow.classList.toggle('is-live', Boolean(app.slides.slide));
  $('slides-dot').hidden = !app.slides.slide;
  $('slides-status').textContent = !app.slides.connected
    ? 'Not connected'
    : app.slides.slide
      ? `${app.slides.slide.title || 'Presentation'} · ${slideLabel()}`
      : 'Waiting for a deck';

  // Scripts
  const list = $('sidebar-notes');
  const rows = [];

  // A script that has been written but not yet named belongs at the top, so it
  // is somewhere rather than nowhere.
  if (!notes.state.currentId && notes.hasScript()) {
    rows.push(row({ id: '', title: 'Untitled Script', meta: 'Not saved', selected: app.source === 'script', draft: true }));
  }

  for (const note of notes.state.saved) {
    const selected = app.source === 'script' && notes.state.currentId === note.id;
    const edited = selected && notes.hasUnsavedChanges();
    rows.push(
      row({
        id: note.id,
        title: note.title,
        meta: `${notes.noteDate(note.updatedAt)}${notes.preview(note.content) ? ` · ${notes.preview(note.content)}` : ''}`,
        selected,
        edited,
      })
    );
  }

  list.innerHTML = rows.join('');
  $('sidebar-empty').hidden = rows.length > 0;

  list.querySelectorAll('.note-row').forEach((el) => {
    const { id } = el.dataset;
    el.addEventListener('click', (event) => {
      if (event.target.closest('[data-act]')) return;
      if (id) void openScript(id);
    });
    el.querySelector('[data-act="rename"]')?.addEventListener('click', () => renameScript(id));
    el.querySelector('[data-act="delete"]')?.addEventListener('click', () => deleteScript(id));
  });

  function row({ id, title, meta, selected, edited = false, draft = false }) {
    return `
      <div class="note-row${selected ? ' is-selected' : ''}" data-id="${ui.escapeAttribute(id)}" role="button" tabindex="0">
        <span class="note-text">
          <span class="note-title">${ui.escapeHtml(title)}</span>
          <span class="note-meta">${ui.escapeHtml(meta)}</span>
        </span>
        ${edited ? '<span class="note-dot" title="Unsaved changes"></span>' : ''}
        ${draft ? '' : `
          <span class="note-actions">
            <button class="icon-btn is-small" data-act="rename" aria-label="Rename" title="Rename">${icon('pencil', 13)}</button>
            <button class="icon-btn is-small" data-act="delete" aria-label="Delete" title="Delete">${icon('trash', 13)}</button>
          </span>`}
      </div>`;
  }
}

function renderSlides() {
  const isSlides = app.source === 'slides';
  $('pane-script').hidden = isSlides;
  $('pane-slides').hidden = !isSlides;
  if (!isSlides) return;

  const { connected, slide, notes: slideNotes } = app.slides;
  const empty = $('slides-empty');

  if (!connected || !slide) {
    $('slides-head').hidden = true;
    $('slides-notes').innerHTML = '';
    empty.hidden = false;
    $('slides-empty-title').textContent = connected ? 'Waiting for your deck' : 'Connect Google Slides';
    $('slides-empty-text').textContent = connected
      ? 'Open a presentation in Google Slides with the CueCard extension installed. The notes for the slide you are on show up here.'
      : 'See the speaker notes for the slide you are on, as you present.';
    $('btn-connect-slides').hidden = connected;
    return;
  }

  empty.hidden = true;
  $('slides-head').hidden = false;
  $('slides-chip').textContent = slideLabel();
  $('slides-title').textContent = slide.title || 'Presentation';
  $('slides-notes').innerHTML = slideNotes.trim()
    ? ui.scriptHtml(slideNotes)
    : '<p class="empty-text">This slide has no speaker notes.</p>';
}

function renderControls() {
  const hasContent = app.source === 'slides' ? Boolean(app.slides.notes.trim()) : notes.hasScript();
  $('btn-play').disabled = !hasContent;

  // Nothing written yet means nothing to time, so the pill offers the one thing
  // that helps: something to read.
  const offerSample = app.source === 'script' && !notes.hasScript();
  $('btn-sample').hidden = !offerSample;
  $('btn-set-timer').hidden = offerSample || timerPickerOpen;
  if (offerSample) closeTimerPicker();

  $('btn-invisible').setAttribute('aria-pressed', String(settings.invisible));
  $('btn-invisible').querySelector('.invisible-label').textContent = settings.invisible ? 'Invisible' : 'Visible';
  const iconSlot = $('btn-invisible').querySelector('.invisible-icon');
  iconSlot.innerHTML = icon(settings.invisible ? 'eyeOff' : 'eye', 16);
  $('btn-invisible').title = settings.invisible
    ? 'Hidden from screen sharing, screenshots and recordings'
    : 'Visible to screen sharing';
}

function selectSource(source) {
  app.source = source;
  if (source === 'slides') T.trackScreen('slides');
  renderAll();
  if (source === 'script') editor.focus();
}

// =============================================================================
// LAYOUT
// =============================================================================

function updateLayout() {
  const home = $('screen-home');
  app.overlay = window.innerWidth < 680;
  home.classList.toggle('is-overlay', app.overlay);

  const open = app.overlay ? app.sidebarOpen && app.overlaySidebar : app.sidebarOpen;
  home.classList.toggle('is-sidebar-collapsed', !open);
  $('sidebar-scrim').hidden = !(app.overlay && open);
}

function toggleSidebar() {
  if (app.overlay) app.overlaySidebar = !app.overlaySidebar;
  else {
    app.sidebarOpen = !app.sidebarOpen;
    void T.setStored('ui_sidebar_open', app.sidebarOpen);
  }
  if (app.overlay) app.sidebarOpen = true;
  updateLayout();
}

// =============================================================================
// THE TIMER PILL
// =============================================================================

let timerPickerOpen = false;

/**
 * Swap the pill for the picker, or back, and let the box travel between the two
 * sizes rather than jumping. The end state is applied first and measured, so the
 * animation always runs between the real sizes.
 */
function flipTimerControl(open) {
  const control = $('timer-control');
  const picker = $('timer-picker');
  const from = control.getBoundingClientRect();

  timerPickerOpen = open;
  control.classList.toggle('is-open', open);
  picker.hidden = !open;
  renderControls();

  const to = control.getBoundingClientRect();
  control.animate(
    [
      { width: `${from.width}px`, height: `${from.height}px` },
      { width: `${to.width}px`, height: `${to.height}px` },
    ],
    { duration: 320, easing: 'cubic-bezier(0.32, 0.9, 0.36, 1)' }
  );

  // The contents arrive once the box has somewhere to put them.
  if (open) {
    picker.animate(
      [{ opacity: 0 }, { opacity: 1 }],
      { duration: 200, delay: 90, easing: 'ease-out', fill: 'backwards' }
    );
  }
}

function openTimerPicker() {
  if (timerPickerOpen) return;
  flipTimerControl(true);
  document.addEventListener('mousedown', onClickAwayFromPicker, true);
  T.trackClick('set_timer', 'home');
}

function closeTimerPicker() {
  if (!timerPickerOpen) return;
  document.removeEventListener('mousedown', onClickAwayFromPicker, true);

  // The contents leave before the box closes over them.
  const fade = $('timer-picker').animate([{ opacity: 1 }, { opacity: 0 }], {
    duration: 120,
    easing: 'ease-in',
  });
  fade.finished.catch(() => {}).then(() => flipTimerControl(false));
}

function onClickAwayFromPicker(event) {
  if (!$('timer-control').contains(event.target)) closeTimerPicker();
}

/** A wheel picker, as near as a window gets to one: scroll it, click it, or type. */
function createWheel(el, { max, get, set }) {
  let typed = '';
  let typedAt = 0;
  let wheelDelta = 0;

  function render() {
    const value = get();
    const at = (n) => String((n + max + 1) % (max + 1)).padStart(2, '0');
    el.innerHTML = `
      <div class="wheel-row">${at(value - 1)}</div>
      <div class="wheel-row is-current">${at(value)}</div>
      <div class="wheel-row">${at(value + 1)}</div>
      <div class="wheel-band"></div>`;
    el.setAttribute('aria-valuenow', String(value));
    el.setAttribute('aria-valuemin', '0');
    el.setAttribute('aria-valuemax', String(max));
  }

  // Wraps, because the faded rows above and below say it will: 59 sits above 0.
  const step = (by) => {
    const span = max + 1;
    set((((get() + by) % span) + span) % span);
    render();
  };

  // One number per notch of a mouse wheel, rather than five.
  el.addEventListener('wheel', (event) => {
    event.preventDefault();
    wheelDelta += event.deltaY;
    if (Math.abs(wheelDelta) < 50) return;
    step(wheelDelta > 0 ? 1 : -1);
    wheelDelta = 0;
  }, { passive: false });

  el.addEventListener('click', (event) => {
    const rows = [...el.querySelectorAll('.wheel-row')];
    const index = rows.indexOf(event.target.closest('.wheel-row'));
    if (index === 0) step(-1);
    if (index === 2) step(1);
    el.focus();
  });

  el.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowUp') {
      event.preventDefault();
      step(-1);
    } else if (event.key === 'ArrowDown') {
      event.preventDefault();
      step(1);
    } else if (/^\d$/.test(event.key)) {
      // Two digits typed together are one number, as on a keypad.
      const now = Date.now();
      typed = now - typedAt < 900 ? (typed + event.key).slice(-2) : event.key;
      typedAt = now;
      set(Math.min(Number(typed), max));
      render();
    }
  });

  render();
  return { render };
}

// =============================================================================
// MENU
// =============================================================================

function openMenu() {
  const note = notes.currentNote();
  const items = [];

  if (app.source === 'script') {
    items.push(
      { label: 'Save', icon: 'save', shortcut: 'mod+s', disabled: !(note && notes.hasUnsavedChanges()), onSelect: saveScript },
      { label: 'Save as New…', icon: 'docPlus', shortcut: 'mod+shift+s', disabled: !notes.hasScript(), onSelect: saveScriptAsNew },
      { divider: true },
      { label: 'New Script', icon: 'compose', shortcut: 'mod+n', onSelect: newScript },
      { label: 'Insert Cue', icon: 'cue', onSelect: () => editor.insertCue() },
      { divider: true },
      { label: 'Import from File…', icon: 'docDown', onSelect: importScript },
      { label: 'Export to File…', icon: 'docUp', disabled: !notes.hasScript(), onSelect: exportScript }
    );
  } else {
    items.push(
      { label: 'Refresh Notes', icon: 'refresh', disabled: !app.slides.slide, onSelect: refreshSlides },
      { label: 'Get the Extension', icon: 'puzzle', onSelect: () => T.openUrl(LINKS.extension) }
    );
  }

  items.push({ divider: true });
  if (app.update) {
    items.push({ label: `Update to ${app.update.version}`, icon: 'update', onSelect: runUpdate });
  }
  items.push(
    { label: 'Keyboard Shortcuts', icon: 'keyboard', onSelect: () => openSettings('shortcuts') },
    { divider: true },
    { label: 'Visit Website', icon: 'globe', onSelect: () => T.openUrl(LINKS.site) },
    { label: 'Contact Support', icon: 'mail', onSelect: () => T.openUrl(LINKS.support) }
  );

  ui.showMenu($('btn-menu'), items);
}

// =============================================================================
// SETTINGS
// =============================================================================

let closeSettingsSheet = null;

function openSettings(page = 'settings') {
  syncSettings();
  renderNotices();
  showSettingsPage(page);
  closeSettingsSheet = ui.openSheet($('sheet-settings'), { onClose: () => { closeSettingsSheet = null; } });
  T.trackScreen('settings');
}

function showSettingsPage(page) {
  const isShortcuts = page === 'shortcuts';
  $('page-settings').hidden = isShortcuts;
  $('page-shortcuts').hidden = !isShortcuts;
  $('sheet-title').textContent = isShortcuts ? 'Keyboard Shortcuts' : 'Settings';
  $('btn-sheet-back').hidden = !isShortcuts;
  document.querySelector('.sheet-body')?.scrollTo(0, 0);
}

function buildSwatches() {
  $('cue-swatches').innerHTML = CUE_COLORS.map(
    (name) => `
      <button class="swatch" data-color="${name}" style="background: var(--color-${name})"
        aria-label="${name[0].toUpperCase()}${name.slice(1)}" title="${name[0].toUpperCase()}${name.slice(1)}">
        ${icon('check', 13, 2.4)}
      </button>`
  ).join('');
}

function syncSettings() {
  $('set-account-section').hidden = !app.authenticated;
  $('set-account-name').textContent = app.user.name || 'Signed in';
  $('set-account-email').textContent = app.user.email;

  $('field-delay').value = String(settings.countdownSeconds);
  $('field-speed').value = String(settings.linesPerMinute);
  $('slider-opacity').value = String(settings.opacity);
  $('opacity-value').textContent = `${settings.opacity}%`;
  $('toggle-invisible').checked = settings.invisible;

  $('cue-swatches').querySelectorAll('.swatch').forEach((el) => {
    el.classList.toggle('is-selected', el.dataset.color === settings.cueColor);
  });
  selectSegment('seg-textsize', settings.fontSizePreset);
  selectSegment('seg-theme', settings.theme);

  $('slides-settings-status').textContent = app.slides.connected ? 'Connected' : 'Not connected';
  $('btn-slides-connect').hidden = app.slides.connected;

  void T.appVersion().then((version) => {
    $('settings-version').textContent = `CueCard ${version}`;
  });
  syncUpdateRow();
}

function selectSegment(id, value) {
  $(id).querySelectorAll('.segment').forEach((el) => {
    el.classList.toggle('is-selected', el.dataset.value === value);
  });
}

function onSettingChanged(key) {
  if (key === 'cueColor' || key === 'fontSizePreset') prompter.restyle();
  if (key === 'invisible') renderControls();
  if (!$('sheet-settings').hidden) syncSettings();
}

function toggleInvisible() {
  void setSetting('invisible', !settings.invisible);
  ui.showToast(settings.invisible ? 'Hidden from screen sharing' : 'Visible to screen sharing');
}

/** Take what was typed, holding it to what the setting allows. */
function commitNumberField(input, key, range) {
  const typed = parseInt(input.value.replace(/\D/g, ''), 10);
  if (!Number.isNaN(typed)) void setSetting(key, clamp(typed, range));
  input.value = String(settings[key]);
}

const SHORTCUTS_LOCAL = [
  ['Save', 'mod+s'],
  ['Save as new', 'mod+shift+s'],
  ['New script', 'mod+n'],
  ['Settings', 'mod+comma'],
];

const SHORTCUTS_PROMPTER = [
  ['Move a line', ['↑', '↓']],
  ['Close the prompter', ['Esc']],
];

const SHORTCUTS_GLOBAL = [
  ['Show or hide CueCard', ['C']],
  ['Play or pause', ['Space']],
  ['Restart', ['0']],
  ['Less or more opacity', ['-', '=']],
  ['Move the window', ['←', '→', '↑', '↓']],
];

function buildShortcutLists() {
  const keys = (list) => `<span class="shortcut-keys">${list.map((k) => `<kbd>${ui.escapeHtml(k)}</kbd>`).join('')}</span>`;
  const cell = (label, inner) => `<div class="cell"><span class="cell-title">${label}</span>${inner}</div>`;
  const base = T.isMac ? ['⌃', '⌥'] : ['Ctrl', 'Alt'];

  $('shortcut-list-local').innerHTML = [
    ...SHORTCUTS_LOCAL.map(([label, spec]) => cell(label, keys([ui.formatShortcut(spec)]))),
    ...SHORTCUTS_PROMPTER.map(([label, list]) => cell(`${label} <span class="cell-sub">in the prompter</span>`, keys(list))),
  ].join('');

  $('shortcut-list-global').innerHTML = SHORTCUTS_GLOBAL.map(([label, list]) =>
    cell(label, keys([...base, ...list]))
  ).join('');
}

// =============================================================================
// UPDATES
// =============================================================================

async function startUpdateChecks() {
  await checkForUpdate();
  setInterval(checkForUpdate, 30 * 60 * 1000);
}

async function checkForUpdate() {
  app.update = await T.findUpdate();
  $('menu-badge').hidden = !app.update;
  syncUpdateRow();
}

function syncUpdateRow() {
  $('row-update').hidden = !app.update;
  if (app.update) $('update-version').textContent = `Version ${app.update.version}`;
}

async function runUpdate() {
  if (!app.update) return;
  const button = $('btn-update');
  button.disabled = true;
  button.textContent = 'Downloading…';
  ui.showToast('Downloading update…');
  try {
    await T.installUpdate(app.update, (progress) => {
      button.textContent = `${Math.round(progress * 100)}%`;
    });
  } catch (error) {
    button.disabled = false;
    button.textContent = 'Update';
    await ui.showError('The update could not be installed.');
    console.error(error);
  }
}

// =============================================================================
// WIRING
// =============================================================================

function wireHome() {
  $('btn-sidebar').addEventListener('click', toggleSidebar);
  $('sidebar-scrim').addEventListener('click', toggleSidebar);
  $('btn-new-script').addEventListener('click', newScript);
  $('row-slides').addEventListener('click', () => selectSource('slides'));
  $('btn-connect-slides').addEventListener('click', connectSlides);
  $('btn-slides-connect').addEventListener('click', connectSlides);
  $('btn-refresh-slides').addEventListener('click', refreshSlides);
  $('link-extension').addEventListener('click', (e) => {
    e.preventDefault();
    void T.openUrl(LINKS.extension);
  });
  $('link-extension-2').addEventListener('click', () => T.openUrl(LINKS.extension));

  $('btn-invisible').addEventListener('click', toggleInvisible);
  $('btn-menu').addEventListener('click', openMenu);
  $('btn-settings').addEventListener('click', () => openSettings('settings'));
  $('btn-close').addEventListener('click', closeApp);

  $('btn-play').addEventListener('click', () => startPrompter());
  $('btn-sample').addEventListener('click', () => {
    notes.addSampleText();
    editor.setText(notes.state.draft);
    editor.reset();
    T.trackClick('add_sample_text', 'home');
  });

  $('btn-set-timer').addEventListener('click', openTimerPicker);
  $('btn-close-timer').addEventListener('click', closeTimerPicker);

  const wheels = {
    minutes: createWheel($('wheel-minutes'), {
      max: 59,
      get: () => settings.timerMinutes,
      set: (v) => setSetting('timerMinutes', v),
    }),
    seconds: createWheel($('wheel-seconds'), {
      max: 59,
      get: () => settings.timerSeconds,
      set: (v) => setSetting('timerSeconds', v),
    }),
  };
  onSettingsChange((key) => {
    if (key === 'timerMinutes' || key === '*') wheels.minutes.render();
    if (key === 'timerSeconds' || key === '*') wheels.seconds.render();
  });

  // Sign in
  $('btn-google').addEventListener('click', async () => {
    const button = $('btn-google');
    button.disabled = true;
    button.querySelector('.google-label').textContent = 'Waiting for your browser…';
    T.trackClick('sign_in_with_google', 'login');
    await T.startLogin('profile');
    setTimeout(() => {
      button.disabled = false;
      button.querySelector('.google-label').textContent = 'Continue with Google';
    }, 30000);
  });
  $('login-close').addEventListener('click', () => T.closeWindow());
  $('link-source').addEventListener('click', (e) => {
    e.preventDefault();
    void T.openUrl(LINKS.source);
  });
}

function wireSettingsSheet() {
  buildShortcutLists();

  $('btn-sheet-done').addEventListener('click', () => closeSettingsSheet?.());
  $('btn-sheet-back').addEventListener('click', () => showSettingsPage('settings'));
  $('row-shortcuts').addEventListener('click', () => showSettingsPage('shortcuts'));

  const delay = $('field-delay');
  delay.addEventListener('blur', () => commitNumberField(delay, 'countdownSeconds', COUNTDOWN_RANGE));
  delay.addEventListener('keydown', (e) => e.key === 'Enter' && delay.blur());

  const speed = $('field-speed');
  speed.addEventListener('blur', () => commitNumberField(speed, 'linesPerMinute', LPM_RANGE));
  speed.addEventListener('keydown', (e) => e.key === 'Enter' && speed.blur());

  $('cue-swatches').addEventListener('click', (event) => {
    const swatch = event.target.closest('.swatch');
    if (swatch) void setSetting('cueColor', swatch.dataset.color);
  });
  $('seg-textsize').addEventListener('click', (event) => {
    const segment = event.target.closest('.segment');
    if (segment) void setSetting('fontSizePreset', segment.dataset.value);
  });
  $('seg-theme').addEventListener('click', (event) => {
    const segment = event.target.closest('.segment');
    if (segment) void setSetting('theme', segment.dataset.value);
  });

  $('toggle-invisible').addEventListener('change', (e) => setSetting('invisible', e.target.checked));

  const opacity = $('slider-opacity');
  opacity.addEventListener('input', () => {
    $('opacity-value').textContent = `${opacity.value}%`;
    void setSetting('opacity', Number(opacity.value), { track: false });
  });
  opacity.addEventListener('change', () => T.trackSetting('opacity', opacity.value));

  $('btn-update').addEventListener('click', runUpdate);
  $('btn-rate').addEventListener('click', () => T.openUrl(LINKS.source));
  $('btn-reset').addEventListener('click', async () => {
    const sure = await ui.confirmAction({
      title: 'Reset to Defaults',
      message: 'Every setting goes back to what it ships as. Your scripts are left alone.',
      confirmLabel: 'Reset',
      destructive: true,
    });
    if (!sure) return;
    await resetSettings();
    syncSettings();
    renderControls();
    prompter.restyle();
  });
  $('btn-signout').addEventListener('click', signOut);
  $('btn-delete-account').addEventListener('click', deleteAccount);
}

function wireKeyboard() {
  window.addEventListener('keydown', (event) => {
    if (prompter.isOpen()) return;
    if (document.querySelector('.alert-layer')) return;

    const on = (spec) => ui.matchesShortcut(event, spec);
    const sheetOpen = ui.isSheetOpen();

    if (on('mod+comma')) {
      event.preventDefault();
      if (!sheetOpen) openSettings('settings');
      return;
    }
    if (sheetOpen) return;

    if (on('mod+shift+s')) {
      event.preventDefault();
      void saveScriptAsNew();
    } else if (on('mod+s')) {
      event.preventDefault();
      void saveScript();
    } else if (on('mod+n')) {
      event.preventDefault();
      void newScript();
    }
  });
}

function listenToBackend() {
  if (!T.listen) return;

  void T.listen('slide-update', (event) => onSlideUpdate(event.payload));

  void T.listen('auth-status', (event) => {
    const payload = event.payload || {};
    if (payload.slides_authorized) {
      app.slides.connected = true;
      selectSource('slides');
      if (!$('sheet-settings').hidden) syncSettings();
      return;
    }
    applyAuth({
      authenticated: Boolean(payload.authenticated),
      name: payload.user_name || '',
      email: payload.user_email || '',
    });
    if (payload.authenticated) T.track('login', { method: 'google' });
  });

  void T.listen('shortcut-triggered', (event) => onGlobalShortcut(event.payload));
}

async function onGlobalShortcut(action) {
  const win = T.currentWindow();
  if (!win) return;

  switch (action) {
    case 'toggle-visibility':
      (await win.isVisible()) ? await win.hide() : await win.show();
      break;
    case 'opacity-down':
      void setSetting('opacity', clamp(settings.opacity - 10, [10, 100]));
      break;
    case 'opacity-up':
      void setSetting('opacity', clamp(settings.opacity + 10, [10, 100]));
      break;
    case 'timer-toggle':
      if (prompter.isOpen()) prompter.togglePlay();
      else startPrompter({ play: true });
      break;
    case 'timer-reset':
      if (prompter.isOpen()) prompter.restart();
      break;
    case 'move-left':
    case 'move-right':
    case 'move-up':
    case 'move-down': {
      const position = await win.outerPosition();
      const dx = action === 'move-left' ? -50 : action === 'move-right' ? 50 : 0;
      const dy = action === 'move-up' ? -50 : action === 'move-down' ? 50 : 0;
      await win.setPosition({ x: position.x + dx, y: position.y + dy, type: 'Physical' });
      break;
    }
    default:
      break;
  }
}

window.addEventListener('DOMContentLoaded', boot);
