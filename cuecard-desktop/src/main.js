/**
 * CueCard for desktop.
 *
 * The phone app opens on a library, writes scripts and decks in two modes, and
 * presents them as a scrolling teleprompter or one card at a time. This has
 * the same, with the room a window gives used for what a phone has nowhere to
 * put: the library and a live Google Slides deck side by side in a sidebar,
 * next to the script being written.
 */

import { icon, hydrateIcons } from './icons.js';
import * as T from './tauri.js';
import {
  EDITOR_SIZE_PRESETS,
  EDITOR_SIZE_RANGE,
  LPM_RANGE,
  VIEWER_SIZE_PRESETS,
  VIEWER_SIZE_RANGE,
  canResetSettings,
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
import { createCardEditor } from './card-editor.js';
import { createPrompter } from './prompter.js';
import { createCardsViewer } from './cards.js';
import { createLibrary } from './library.js';
import { openHelpSheet, openTimerSheet, openVersionsSheet } from './sheets.js';
import * as ui from './ui.js';
import * as notices from './notifications.js';
import { addImage, removeUnusedImages } from './images.js';
import {
  CUE_COLORS,
  cards as cardsOf,
  colorName,
  formatDuration,
  imageNames,
  limitedTitle,
  normalizingTags,
  plainText,
  suggestedFileName,
  titleForFileName,
} from './parser.js';

const $ = (id) => document.getElementById(id);

const LINKS = {
  site: 'https://cuecard.dev',
  extension: 'https://cuecard.dev/#download',
  source: 'https://github.com/ThisIsNSH/CueCard',
  support: 'support@cuecard.dev',
};

const PLACEHOLDERS = {
  teleprompter:
    'Write your script here…\n\nType [ to add a cue — a note to yourself like “[smile and pause]” that you read but never say out loud. Write *bold* or _italic_ for emphasis.',
  cards: 'Write your first card…\n\nType [ to add a cue like “[pause]”.',
};

const app = {
  /** Which script the detail pane is showing: your own, or the live deck. */
  source: 'script',
  slides: { connected: false, slide: null, notes: '' },
  update: null,
  sidebarOpen: true,
  overlay: false,
  overlaySidebar: false,
  /** "Saved", for a moment after saving. */
  justSaved: false,
};

let editor;
let cardEditor;
let prompter;
let cardsViewer;
let library;

const mode = () => notes.state.mode;
const kindName = (m = mode()) => (m === 'cards' ? 'deck' : 'script');

// =============================================================================
// START-UP
// =============================================================================

async function boot() {
  document.documentElement.classList.add(`platform-${T.platformInfo().platform}`);
  hydrateIcons();

  await T.initStore();
  await T.initAnalytics();

  await loadSettings();
  watchSystemTheme();
  await notes.loadNotes({ seedTimer: seedTimerFromTimeTags });

  editor = createEditor($('editor'), {
    onChange: (text) => notes.setDraft(text, { mode: 'teleprompter' }),
    onImages: insertImages,
  });
  editor.setPlaceholder(PLACEHOLDERS.teleprompter);

  cardEditor = createCardEditor($('card-editor'), {
    onChange: (script) => notes.setDraft(script, { mode: 'cards' }),
    onImages: insertImages,
  });
  cardEditor.setPlaceholder(PLACEHOLDERS.cards);

  syncEditors();

  prompter = createPrompter($('screen-prompter'), { onClose: onViewerClosed });
  cardsViewer = createCardsViewer($('screen-cards'), { onClose: onViewerClosed });

  library = createLibrary(
    {
      modeSwitch: $('mode-switch'),
      search: $('library-search'),
      sectionTitle: $('library-title'),
      chips: $('library-chips'),
      list: $('library-list'),
      empty: $('library-empty'),
      footer: $('library-footer'),
      more: $('btn-library-menu'),
      add: $('btn-new-script'),
    },
    libraryHandlers()
  );
  await library.load();

  wireHome();
  wireSettingsSheet();
  wireKeyboard();

  app.sidebarOpen = (await T.getStored('ui_sidebar_open')) ?? true;
  updateLayout();
  window.addEventListener('resize', updateLayout);

  onSettingsChange(onSettingChanged);
  notes.onNotesChange(scheduleRender);
  notices.onNotificationsChange(renderNotices);
  await notices.loadNotifications();

  await T.trackFirstLaunch();
  T.track('app_open');
  T.track('start_session');
  T.trackScreen('home');

  renderAll();
  editor.reset();

  await initSlides();
  listenToBackend();
  void startUpdateChecks();

  // Pictures no script places any more go, once everything's had a chance to load.
  setTimeout(() => void removeUnusedImages(placedImages()), 30 * 1000);

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

/** Put each mode's draft in its editor, after it changed from outside them. */
function syncEditors() {
  editor.setText(notes.draft('teleprompter').text);
  cardEditor.setText(notes.draft('cards').text);
}

/** The editor the format buttons work in: the script's, or the card being written. */
const activeEditor = () => (mode() === 'cards' ? cardEditor.activeEditor() : editor);

// =============================================================================
// THE SCRIPT BEING WRITTEN
// =============================================================================

let savedTimer = null;
function flashSaved() {
  app.justSaved = true;
  clearTimeout(savedTimer);
  savedTimer = setTimeout(() => {
    app.justSaved = false;
    renderToolbar();
  }, 1400);
}

async function saveScript(from = 'save_note') {
  if (!notes.hasScript()) return;
  if (!notes.currentNote()) return saveScriptAsNew();
  if (!notes.hasUnsavedChanges()) return;
  await notes.saveCurrent();
  flashSaved();
  renderAll();
  T.trackClick(from, 'home');
}

async function saveScriptAsNew() {
  if (!notes.hasScript()) return;
  const note = notes.currentNote();
  const title = await ui.promptForText({
    title: note ? 'Save as New' : mode() === 'cards' ? 'Save Deck' : 'Save Script',
    message: note
      ? `Your changes go in a new ${kindName()}. “${note.title}” stays as it was last saved.`
      : `Give this ${kindName()} a name.`,
    value: note ? limitedTitle(`${note.title} Copy`) : limitedTitle(suggestedFileName(null, plainText(notes.draft().text))),
    placeholder: 'Title',
    confirmLabel: 'Save',
  });
  if (!title) return;
  await notes.saveAsNew(title);
  flashSaved();
  renderAll();
  T.trackClick(note ? 'save_as_new' : 'save_note', 'home');
}

/**
 * Before dropping a script with changes in it, ask — a window makes switching
 * scripts easy enough that losing one to a stray click would be too easy too.
 * Closing the window is not one of these: the draft is kept on the way out.
 * Returns false if the reader decided to stay.
 */
async function confirmLeavingScript(m = mode()) {
  if (!notes.hasUnsavedChanges(m)) return true;

  const note = notes.currentNote(m);
  const result = await ui.showAlert({
    title: note ? `Save changes to “${note.title}”?` : `Save this ${kindName(m)}?`,
    message: note
      ? 'Your changes are lost if you do not save them.'
      : `It was never saved, so it can't be brought back if you don't save it.`,
    actions: [
      { id: 'discard', label: "Don't Save", style: 'destructive' },
      { id: 'cancel', label: 'Cancel', style: 'cancel' },
      { id: 'save', label: 'Save', style: 'preferred' },
    ],
  });

  if (!result) {
    T.trackClick('unsaved_cancel', 'home');
    return false;
  }
  T.trackClick(result.action === 'save' ? 'unsaved_save_continue' : 'unsaved_discard', 'home');
  if (result.action === 'save') {
    if (m !== mode()) await notes.setMode(m);
    if (note) await notes.saveCurrent(m);
    else {
      await saveScriptAsNew();
      if (notes.hasUnsavedChanges(m)) return false;
    }
  }
  return true;
}

/** Leaving is worth asking about. What you were writing is not: it is waiting
 *  here, exactly as you left it, the next time the window opens. */
async function closeApp() {
  const leaving = await ui.confirmAction({
    title: 'Exit CueCard?',
    message: 'The window closes and the prompter stops.',
    confirmLabel: 'Yes',
    cancelLabel: 'No',
    destructive: true,
  });
  if (!leaving) return;
  await notes.flushDraft();
  await T.closeWindow();
}

async function newScript() {
  T.trackClick(mode() === 'cards' ? 'new_deck' : 'new_script', 'library');
  if (!(await confirmLeavingScript())) return;
  await notes.newScript(mode(), library.collection());
  syncEditors();
  selectSource('script');
  focusEditor();
}

async function openScript(id) {
  const note = notes.noteById(id);
  if (!note) return;
  T.trackClick('load_note', 'library', { note_id: id });

  // Already open in its mode: just show it.
  if (notes.draft(note.mode).noteId === id) {
    await notes.setMode(note.mode);
    selectSource('script');
    return;
  }
  if (!(await confirmLeavingScript(note.mode))) return;
  await notes.openNote(id);
  syncEditors();
  editor.reset();
  cardEditor.scrollToTop();
  selectSource('script');
}

async function openDraft() {
  T.trackClick('open_draft', 'library');
  selectSource('script');
  focusEditor();
}

async function discardDraft() {
  const sure = await ui.confirmAction({
    title: `Discard This ${mode() === 'cards' ? 'Deck' : 'Script'}?`,
    message: "It was never saved, so it can't be brought back.",
    confirmLabel: 'Discard',
    destructive: true,
  });
  T.trackClick(sure ? 'discard_draft' : 'discard_draft_cancel', 'library');
  if (!sure) return;
  await notes.discardDraft();
  syncEditors();
}

/** Throw away what changed since the open script was last saved. */
async function revertScript() {
  const note = notes.currentNote();
  if (!note || !notes.hasUnsavedChanges()) return;
  const sure = await ui.confirmAction({
    title: 'Discard Changes?',
    message: `“${note.title}” goes back to how it was last saved.`,
    confirmLabel: 'Discard Changes',
    destructive: true,
  });
  if (!sure) return;
  T.trackClick('discard_changes', 'home');
  await notes.discardDraft();
  syncEditors();
}

async function renameScript(id) {
  const note = notes.noteById(id);
  if (!note) return;
  T.trackClick('rename_note', 'library', { note_id: id });
  const title = await ui.promptForText({
    title: 'Rename',
    message: `Give this ${kindName(note.mode)} a new name.`,
    value: note.title,
    placeholder: 'Title',
    confirmLabel: 'Rename',
  });
  if (title) await notes.renameNote(id, title);
}

/** The title in the bar: rename what's saved, or name what isn't. */
function onTitleClick() {
  const note = notes.currentNote();
  if (note) return renameScript(note.id);
  if (notes.hasScript()) return saveScriptAsNew();
  return undefined;
}

async function duplicateScript(id) {
  T.trackClick('duplicate_note', 'library');
  const copy = await notes.duplicateNote(id);
  if (copy) ui.showToast('Duplicated');
}

async function deleteScript(id) {
  const note = notes.noteById(id);
  if (!note) return;
  T.trackClick('delete_note_menu', 'library', { note_id: id });
  const sure = await ui.confirmAction({
    title: `Delete “${note.title}”?`,
    message: "Its versions are deleted too. This can't be undone.",
    confirmLabel: 'Delete',
    destructive: true,
  });
  if (!sure) return;
  T.trackClick('delete_note', 'library');
  await notes.deleteNote(id);
  syncEditors();
}

async function deleteAllScripts() {
  T.trackClick('delete_all_notes', 'library');
  const sure = await ui.confirmAction({
    title: 'Delete All Scripts?',
    message: "Every saved script and deck will be deleted, with their versions. This can't be undone.",
    confirmLabel: 'Delete All',
    destructive: true,
  });
  if (!sure) return;
  T.trackClick('delete_all_notes_confirm', 'library');
  await notes.deleteAll();
  syncEditors();
}

async function switchMode(m) {
  await notes.setMode(m);
  selectSource('script');
}

function openVersions(id = notes.currentNote()?.id) {
  if (!id) return;
  T.trackClick('version_history', 'home');
  openVersionsSheet(id, { onRestored: syncEditors });
}

// =============================================================================
// IMAGES
// =============================================================================

/** Every picture something still places: a draft, a saved script, or any of
 *  their versions. */
function placedImages() {
  const names = new Set();
  const take = (text) => imageNames(text).forEach((name) => names.add(name));
  notes.MODES.forEach((m) => take(notes.draft(m).text));
  notes.state.saved.forEach((note) => take(note.content));
  Object.values(notes.state.versions).forEach((list) => list.forEach((version) => take(version.content)));
  return names;
}

/** Keep the pictures given and put them in where the caret is. */
async function insertImages(files) {
  if (app.source !== 'script' || !files.length) return;
  const target = activeEditor();
  T.trackClick('insert_image', 'home', { count: files.length });
  if (files.length > 1 || files[0].size > 2_000_000) ui.showToast('Adding…');
  const names = [];
  for (const file of files) {
    const name = await addImage(file);
    if (name) names.push(name);
  }
  if (names.length) target?.insertImages(names);
  if (names.length < files.length) {
    await ui.showError(
      names.length ? "Some of the pictures couldn't be added." : "That picture couldn't be added.",
      "Couldn't Add Image"
    );
  }
}

async function pickImages() {
  if (app.source !== 'script') return;
  try {
    const files = await T.pickImageFiles();
    await insertImages(files);
  } catch (error) {
    console.error(error);
    await ui.showError("That picture couldn't be read.", "Couldn't Add Image");
  }
}

// =============================================================================
// COLLECTIONS
// =============================================================================

const promptCollectionName = (value = '', { title = 'New Collection', confirmLabel = 'Create' } = {}) =>
  ui.promptForText({
    title,
    message: 'Scripts and decks can be kept together in it.',
    value,
    placeholder: 'Name',
    confirmLabel,
  });

async function newCollection() {
  T.trackClick('new_collection', 'library');
  const name = await promptCollectionName();
  if (!name) return;
  const made = await notes.createCollection(name);
  if (!made) return;
  library.showCollection(made);
  renderAll();
}

async function renameCollection(name) {
  T.trackClick('rename_collection', 'library');
  const next = await promptCollectionName(name, { title: 'Rename Collection', confirmLabel: 'Rename' });
  if (!next || next === name) return;
  const renamed = await notes.renameCollection(name, next);
  if (!renamed) return ui.showError(`There's already a collection called “${next}”.`, "Couldn't Rename");
  if (library.collection() === null) library.showCollection(renamed);
  renderAll();
  return undefined;
}

async function deleteCollection(name) {
  T.trackClick('delete_collection', 'library');
  const sure = await ui.confirmAction({
    title: `Delete “${name}”?`,
    message: "The scripts in it aren't deleted. They stay in All.",
    confirmLabel: 'Delete Collection',
    destructive: true,
  });
  if (!sure) return;
  await notes.deleteCollection(name);
}

// =============================================================================
// FILES AND SHARING
// =============================================================================

async function importScript() {
  T.trackClick('import_file', 'library');
  if (!T.filesAvailable()) return ui.showError('File access is not available in this build.');

  try {
    const picked = await T.pickTextFile();
    if (!picked) return;
    if (!picked.text.trim()) return ui.showError('That file is empty.');
    if (picked.text.length > 10 * 1024 * 1024) return ui.showError('That file is too large to be a script.');

    // Whatever spelling the file was written in, it arrives as [...].
    const content = normalizingTags(picked.text.replace(/\r\n?/g, '\n'));
    const target = content.match(/\[separator\]/i) ? 'cards' : 'teleprompter';
    if (!(await confirmLeavingScript(target))) return;
    await notes.importScript(titleForFileName(picked.path), content, library.collection());
    syncEditors();
    editor.reset();
    selectSource('script');
    ui.showToast('Imported');
  } catch (error) {
    await ui.showError("This file couldn't be read as text.");
    console.error(error);
  }
  return undefined;
}

async function exportText(title, content) {
  if (!T.filesAvailable()) return ui.showError('File access is not available in this build.');
  if (!plainText(content).trim()) return undefined;

  try {
    const name = `${suggestedFileName(title, plainText(content))}.txt`;
    if (await T.saveTextFile(name, normalizingTags(content))) {
      ui.showToast('Exported');
      T.trackClick('export_file', 'home');
    }
  } catch (error) {
    await ui.showError(String(error));
  }
  return undefined;
}

const exportScript = () => exportText(notes.currentNote()?.title, notes.draft().text);

function exportNote(id) {
  const note = notes.noteById(id);
  if (note) void exportText(note.title, note.content);
}

/** The script as text, cues included, on the clipboard. */
async function copyText(content) {
  const text = normalizingTags(content);
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const area = document.createElement('textarea');
    area.value = text;
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    document.execCommand('copy');
    area.remove();
  }
  ui.showToast('Copied');
  T.trackClick('copy_text', 'home');
}

function libraryHandlers() {
  return {
    onChange: renderAll,
    onMode: switchMode,
    onOpen: openScript,
    onOpenDraft: openDraft,
    onDiscardDraft: discardDraft,
    onNew: newScript,
    onRename: renameScript,
    onDuplicate: duplicateScript,
    onDelete: deleteScript,
    onDeleteAll: deleteAllScripts,
    onExport: exportNote,
    onCopy: (id) => copyText(notes.noteById(id)?.content || ''),
    onVersions: openVersions,
    onImport: importScript,
    onNewCollection: newCollection,
    onRenameCollection: renameCollection,
    onDeleteCollection: deleteCollection,
    promptCollectionName: () => promptCollectionName(),
  };
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
  renderAll();
}

function connectSlides() {
  T.trackClick('connect_slides', 'home');
  T.track('slides_sync');
  void T.connectSlides();
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

  // Everything the deck touches, not just the notes: the title bar, the sidebar
  // row, and the play button, which has something to play the moment a slide
  // with notes on it arrives.
  renderAll();

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

/** Which slide of the deck this is, empty until something knows. */
const slideLabel = () => {
  const number = app.slides.slide?.slideNumber ?? 0;
  return number > 0 ? `Slide ${number}` : '';
};

/** The deck and the place in it, as one line: "Introducing CueCard · Slide 1". */
const deckLabel = () =>
  [app.slides.slide?.title || 'Presentation', slideLabel()].filter(Boolean).join(' · ');

// =============================================================================
// PRESENTING
// =============================================================================

const draftTitle = (m = mode()) => notes.currentNote(m)?.title || (m === 'cards' ? 'New Deck' : 'New Script');

function hasSomethingToPlay() {
  if (app.source === 'slides') return Boolean(plainText(app.slides.notes).trim());
  if (mode() === 'cards') return cardsOf(notes.draft('cards').text).length > 0;
  return notes.hasScript('teleprompter');
}

/** Present what's showing: the deck's notes, the script, or the cards. */
function start({ play = false } = {}) {
  if (!hasSomethingToPlay()) return;
  ui.closeMenu();

  if (app.source === 'slides') {
    return openPrompter({
      source: 'slides',
      text: app.slides.notes,
      title: app.slides.slide?.title || 'Google Slides',
      subtitle: slideLabel(),
    }, play);
  }

  if (mode() === 'cards') {
    T.trackClick('start_cards', 'home');
    if (!cardsViewer.open({ text: notes.draft('cards').text, title: draftTitle('cards') })) return undefined;
    $('screen-home').hidden = true;
    T.trackScreen('cards');
    return undefined;
  }

  return openPrompter({ source: 'script', text: notes.draft('teleprompter').text, title: draftTitle('teleprompter') }, play);
}

function openPrompter(script, play) {
  $('screen-home').hidden = true;
  prompter.open(script);
  T.trackScreen('teleprompter');
  T.track('timer_action', { action: 'open' });
  if (play) prompter.togglePlay();
}

function onViewerClosed() {
  $('screen-home').hidden = false;
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

let renderFrame = null;
/** Typing changes the draft on every key, so drawing waits for the next frame. */
function scheduleRender() {
  if (renderFrame !== null) return;
  renderFrame = requestAnimationFrame(() => {
    renderFrame = null;
    renderAll();
  });
}

function renderAll() {
  renderNotices();
  renderPanes();
  renderToolbar();
  renderSidebar();
  renderSlides();
  renderControls();
}

function renderPanes() {
  const isSlides = app.source === 'slides';
  $('pane-script').hidden = isSlides || mode() !== 'teleprompter';
  $('pane-cards').hidden = isSlides || mode() !== 'cards';
  $('pane-slides').hidden = !isSlides;
}

function renderToolbar() {
  const title = $('title-main');
  const sub = $('title-sub');
  const save = $('btn-save');

  if (app.source === 'slides') {
    title.textContent = 'Google Slides';
    title.disabled = true;
    title.removeAttribute('title');
    sub.textContent = app.slides.slide?.title || (app.slides.connected ? 'Waiting for a deck' : 'Not connected');
    sub.hidden = false;
    sub.disabled = true;
    save.hidden = true;
    return;
  }

  const note = notes.currentNote();
  const unsaved = notes.hasUnsavedChanges();
  title.textContent = note ? note.title : notes.hasScript() ? draftTitle() : 'CueCard';
  title.disabled = !note && !notes.hasScript();
  title.title = note ? 'Rename' : notes.hasScript() ? `Save this ${kindName()}` : '';

  const details = [
    unsaved ? 'Unsaved' : app.justSaved ? 'Saved' : null,
    note ? `Version ${notes.versionCount(note.id)}` : null,
  ].filter(Boolean);
  sub.textContent = details.join(' · ');
  sub.hidden = !details.length;
  sub.disabled = !note;
  sub.title = note ? 'Version History' : '';
  sub.classList.toggle('is-unsaved', unsaved);

  save.hidden = !unsaved;
}

function renderSidebar() {
  const slidesRow = $('row-slides');
  slidesRow.classList.toggle('is-selected', app.source === 'slides');
  slidesRow.classList.toggle('is-live', Boolean(app.slides.slide));
  $('slides-dot').hidden = !app.slides.slide;
  $('slides-status').textContent = !app.slides.connected
    ? 'Not connected'
    : app.slides.slide
      ? deckLabel()
      : 'Waiting for a deck';

  library.render({ source: app.source, selectedId: notes.draft().noteId });
}

function renderSlides() {
  if (app.source !== 'slides') return;

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
  $('slides-title').textContent = deckLabel();
  // Notes that are nothing but tags this version doesn't show leave an empty
  // script, which is the same as having none.
  $('slides-notes').innerHTML =
    ui.scriptHtml(slideNotes, { anchors: false }) || '<p class="empty-text">This slide has no speaker notes.</p>';
}

function renderControls() {
  const isScript = app.source === 'script';
  const isCards = mode() === 'cards';

  $('btn-play').disabled = !hasSomethingToPlay();
  const playLabel = app.source === 'slides' ? 'Start Teleprompter' : isCards ? 'Open Cards' : 'Start Teleprompter';
  $('btn-play').setAttribute('aria-label', playLabel);
  $('btn-play').title = `${playLabel} (${ui.formatShortcut('mod+enter')})`;

  // The format buttons are for writing.
  $('format-bar').hidden = !isScript;
  $('format-bar').querySelector('[data-format="anchor"]').hidden = isCards;

  // Nothing written yet means nothing to time, so the pill offers the one thing
  // that helps: something to read.
  const offerSample = isScript && !notes.hasScript();
  $('btn-sample').hidden = !offerSample;
  $('btn-set-timer').hidden = offerSample;
  const timerMode = app.source === 'slides' ? 'teleprompter' : mode();
  const duration = timerDuration(timerMode);
  $('timer-label').textContent = duration > 0 ? formatDuration(duration) : 'Set Timer';
  $('btn-set-timer').setAttribute('aria-label', duration > 0 ? `Timer, ${formatDuration(duration)}` : 'Timer, not set');

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
  if (app.overlay && app.overlaySidebar) {
    app.overlaySidebar = false;
    updateLayout();
  }
  renderAll();
  if (source === 'script') focusEditor();
}

function focusEditor() {
  requestAnimationFrame(() => (mode() === 'cards' ? cardEditor.focus() : editor.focus()));
}

// =============================================================================
// LAYOUT
// =============================================================================

function updateLayout() {
  const home = $('screen-home');
  app.overlay = window.innerWidth < 720;
  home.classList.toggle('is-overlay', app.overlay);

  const open = app.overlay ? app.overlaySidebar : app.sidebarOpen;
  home.classList.toggle('is-sidebar-collapsed', !open);
  $('sidebar-scrim').hidden = !(app.overlay && open);
}

function toggleSidebar(force) {
  const isOpen = app.overlay ? app.overlaySidebar : app.sidebarOpen;
  const opening = typeof force === 'boolean' ? force : !isOpen;
  if (opening === isOpen) return;
  if (opening) T.trackClick('saved_notes', 'home');
  if (app.overlay) app.overlaySidebar = opening;
  else {
    app.sidebarOpen = opening;
    void T.setStored('ui_sidebar_open', app.sidebarOpen);
  }
  updateLayout();
}

// =============================================================================
// MENU
// =============================================================================

function supportMail(subject) {
  void T.appVersion().then((version) => {
    const body = `\n\n—\nCueCard ${version} for ${T.isMac ? 'macOS' : 'Windows'}`;
    void T.openUrl(`mailto:${LINKS.support}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`);
  });
}

function openHelp(page = 'home') {
  T.trackClick('help', page);
  openHelpSheet({
    isMac: T.isMac,
    page,
    onSupport: () => supportMail('CueCard Desktop: a problem'),
    onFeature: () => supportMail('CueCard Desktop: a feature request'),
  });
}

function openMenu() {
  T.trackClick('editor_menu', 'home');
  const note = notes.currentNote();
  const items = [];

  if (app.source === 'script') {
    const isCards = mode() === 'cards';
    items.push(
      { label: 'Save', icon: 'save', shortcut: 'mod+s', disabled: !notes.hasUnsavedChanges(), onSelect: () => saveScript('save_note_menu') },
      { label: 'Save as New…', icon: 'docPlus', shortcut: 'mod+shift+s', disabled: !notes.hasScript(), onSelect: saveScriptAsNew },
      { label: 'Version History', icon: 'history', disabled: !note || notes.versionCount(note.id) < 2, onSelect: () => openVersions() },
      { divider: true },
      { label: isCards ? 'New Deck' : 'New Script', icon: 'compose', shortcut: 'mod+n', onSelect: newScript },
      { label: 'Rename…', icon: 'pencil', disabled: !note, onSelect: () => note && renameScript(note.id) },
      { label: isCards ? 'Create New Card' : 'Add Anchor', icon: isCards ? 'plus' : 'anchor', onSelect: () => (isCards ? cardEditor.addCard() : insertFormat('anchor')) },
      { label: 'Add Image…', icon: 'photo', onSelect: pickImages },
      { divider: true },
      { label: 'Import File…', icon: 'docDown', onSelect: importScript },
      { label: 'Export to File…', icon: 'docUp', disabled: !notes.hasScript(), onSelect: exportScript },
      { label: 'Copy Text', icon: 'copy', disabled: !notes.hasScript(), onSelect: () => copyText(notes.draft().text) }
    );
    if (note && notes.hasUnsavedChanges()) {
      items.push({ divider: true }, { label: 'Discard Changes', icon: 'restart', destructive: true, onSelect: revertScript });
    }
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
    { label: 'Help', icon: 'help', onSelect: () => openHelp('home') },
    { label: 'Keyboard Shortcuts', icon: 'keyboard', onSelect: () => openSettings('shortcuts') },
    { divider: true },
    { label: 'Visit Website', icon: 'globe', onSelect: () => T.openUrl(LINKS.site) },
    { label: 'Contact Support', icon: 'mail', onSelect: () => supportMail('CueCard Desktop') }
  );

  ui.showMenu($('btn-menu'), items);
}

/** What the format buttons and their shortcuts do, in whichever editor is in use. */
function insertFormat(kind) {
  if (app.source !== 'script') return;
  const target = activeEditor();
  if (!target) return;
  if (kind !== 'image') T.trackClick(kind === 'cue' ? 'insert_cue' : kind === 'anchor' ? 'insert_anchor' : `format_${kind}`, 'home');
  if (kind === 'image') {
    void pickImages();
    return;
  }
  if (kind === 'cue') target.insertCue();
  else if (kind === 'anchor') {
    if (mode() === 'cards') return;
    target.insertAnchor();
  } else target.toggleEmphasis(kind);
}

// =============================================================================
// SETTINGS
// =============================================================================

let closeSettingsSheet = null;

function openSettings(page = 'settings') {
  syncSettings();
  renderNotices();
  showSettingsPage(page);
  if (!closeSettingsSheet) {
    closeSettingsSheet = ui.openSheet($('sheet-settings'), { onClose: () => { closeSettingsSheet = null; } });
  }
  T.trackScreen('settings');
}

function showSettingsPage(page) {
  const isShortcuts = page === 'shortcuts';
  $('page-settings').hidden = isShortcuts;
  $('page-shortcuts').hidden = !isShortcuts;
  $('sheet-title').textContent = isShortcuts ? 'Keyboard Shortcuts' : 'Settings';
  $('btn-sheet-back').hidden = !isShortcuts;
  $('sheet-settings').querySelector('.sheet-body')?.scrollTo(0, 0);
}

function buildSettingsControls() {
  document.querySelectorAll('[data-swatches]').forEach((host) => {
    const key = host.dataset.swatches;
    host.innerHTML = CUE_COLORS.map(
      (name) => `
        <button class="swatch" data-color="${name}" style="background: var(--color-${name})"
          aria-label="Cue color: ${colorName(name)}" title="${colorName(name)}">
          ${icon('check', 11, 2.6)}
        </button>`
    ).join('');
    host.addEventListener('click', (event) => {
      const swatch = event.target.closest('.swatch');
      if (swatch) void setSetting(key, swatch.dataset.color);
    });
  });

  document.querySelectorAll('[data-size]').forEach((host) => {
    const key = host.dataset.size;
    const presets = key.toLowerCase().includes('editor') ? EDITOR_SIZE_PRESETS : VIEWER_SIZE_PRESETS;
    host.innerHTML = presets
      .map((preset) => `<button class="segment" data-value="${preset.value}" title="${preset.value} pt">${preset.label}</button>`)
      .join('');
    host.addEventListener('click', (event) => {
      const segment = event.target.closest('.segment');
      if (segment) void setSetting(key, Number(segment.dataset.value));
    });
  });

  document.querySelectorAll('[data-toggle]').forEach((input) => {
    input.addEventListener('change', () => setSetting(input.dataset.toggle, input.checked));
  });

  document.querySelectorAll('[data-number]').forEach((input) => {
    const key = input.dataset.number;
    const range = key.toLowerCase().includes('editor') ? EDITOR_SIZE_RANGE : VIEWER_SIZE_RANGE;
    input.addEventListener('blur', () => commitNumberField(input, key, range));
    input.addEventListener('keydown', (e) => e.key === 'Enter' && input.blur());
  });
}

let showsAdvanced = false;

function syncSettings() {
  $('field-speed').value = String(settings.linesPerMinute);
  $('slider-opacity').value = String(settings.opacity);
  $('opacity-value').textContent = `${settings.opacity}%`;
  $('toggle-invisible').checked = settings.invisible;

  document.querySelectorAll('[data-swatches]').forEach((host) => {
    host.querySelectorAll('.swatch').forEach((el) => {
      el.classList.toggle('is-selected', el.dataset.color === settings[host.dataset.swatches]);
    });
  });
  document.querySelectorAll('[data-size]').forEach((host) => {
    host.querySelectorAll('.segment').forEach((el) => {
      el.classList.toggle('is-selected', Number(el.dataset.value) === settings[host.dataset.size]);
    });
    host.title = host.querySelector('.is-selected') ? '' : `Custom (${settings[host.dataset.size]})`;
  });
  document.querySelectorAll('[data-toggle]').forEach((input) => {
    input.checked = Boolean(settings[input.dataset.toggle]);
  });
  document.querySelectorAll('[data-number]').forEach((input) => {
    if (document.activeElement !== input) input.value = String(settings[input.dataset.number]);
  });
  selectSegment('seg-theme', settings.theme);

  $('advanced-fields').hidden = !showsAdvanced;
  $('advanced-label').textContent = showsAdvanced ? 'Hide Advanced Settings' : 'Show Advanced Settings';
  $('btn-reset').disabled = !canResetSettings();

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

const PROMPTER_KEYS = new Set([
  'fontSize', 'cueColor', 'mirrorsText', 'flipsTextVertically', 'showsReadingGuide',
  'timerStyle', 'timerMinutes', 'timerSeconds', '*',
]);
const CARDS_KEYS = new Set(['cardsFontSize', 'cardsCueColor', 'cardsTimerStyle', 'cardsTimerMinutes', 'cardsTimerSeconds', '*']);

function onSettingChanged(key) {
  if (PROMPTER_KEYS.has(key)) prompter.restyle();
  if (CARDS_KEYS.has(key)) cardsViewer.restyle();
  renderControls();
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
  ['New script or deck', 'mod+n'],
  ['Bold', 'mod+b'],
  ['Italic', 'mod+i'],
  ['New card', 'mod+enter', 'in a card'],
  ['Teleprompter or Cards', ['mod+1', 'mod+2']],
  ['Search the library', 'mod+f'],
  ['Start', 'mod+enter'],
  ['Settings', 'mod+comma'],
];

const SHORTCUTS_READING = [
  ['Play or pause', ['Space'], 'teleprompter'],
  ['Restart', ['R'], 'teleprompter'],
  ['Move a line', ['↑', '↓'], 'teleprompter'],
  ['Anchor before or after', ['←', '→'], 'teleprompter'],
  ['Next card', ['→', 'Space'], 'cards'],
  ['Previous card', ['←'], 'cards'],
  ['Close', ['Esc']],
];

const SHORTCUTS_GLOBAL = [
  ['Show or hide CueCard', ['C']],
  ['Play or pause, or next card', ['Space']],
  ['Restart', ['0']],
  ['Less or more opacity', ['-', '=']],
  ['Move the window', ['←', '→', '↑', '↓']],
];

function buildShortcutLists() {
  const keys = (list) => `<span class="shortcut-keys">${list.map((k) => `<kbd>${ui.escapeHtml(k)}</kbd>`).join('')}</span>`;
  const cell = (label, inner, sub = '') =>
    `<div class="cell"><span class="cell-label"><span class="cell-title">${label}</span>${sub ? `<span class="cell-sub">${sub}</span>` : ''}</span>${inner}</div>`;
  const base = T.isMac ? ['⌃', '⌥'] : ['Ctrl', 'Alt'];

  $('shortcut-list-local').innerHTML = SHORTCUTS_LOCAL.map(([label, spec, sub]) =>
    cell(label, keys((Array.isArray(spec) ? spec : [spec]).map(ui.formatShortcut)), sub)
  ).join('');

  $('shortcut-list-reading').innerHTML = SHORTCUTS_READING.map(([label, list, where]) =>
    cell(label, keys(list), where ? `In ${where === 'cards' ? 'cards' : 'the teleprompter'}` : '')
  ).join('');

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
  $('btn-sidebar').addEventListener('click', () => toggleSidebar());
  $('sidebar-scrim').addEventListener('click', () => toggleSidebar(false));
  $('row-slides').addEventListener('click', () => selectSource('slides'));
  $('btn-connect-slides').addEventListener('click', connectSlides);
  $('btn-slides-connect').addEventListener('click', connectSlides);
  $('btn-refresh-slides').addEventListener('click', refreshSlides);
  $('link-extension').addEventListener('click', (e) => {
    e.preventDefault();
    void T.openUrl(LINKS.extension);
  });
  $('link-extension-2').addEventListener('click', () => T.openUrl(LINKS.extension));

  $('title-main').addEventListener('click', () => {
    T.trackClick('rename_note', 'home');
    void onTitleClick();
  });
  $('title-sub').addEventListener('click', () => {
    T.trackClick('version_history_footer', 'home');
    openVersions();
  });
  $('btn-save').addEventListener('click', () => saveScript('save_note_top'));

  $('btn-invisible').addEventListener('click', toggleInvisible);
  $('btn-menu').addEventListener('click', openMenu);
  $('btn-settings').addEventListener('click', () => {
    T.trackClick('settings', 'home');
    openSettings('settings');
  });
  $('btn-close').addEventListener('click', closeApp);

  $('btn-play').addEventListener('click', () => start());
  $('btn-sample').addEventListener('click', () => {
    notes.addSampleText();
    syncEditors();
    editor.reset();
    T.trackClick('add_sample_text', 'home');
  });

  $('btn-set-timer').addEventListener('click', () => {
    T.trackClick('set_timer', 'home');
    openTimerSheet(app.source === 'slides' ? 'teleprompter' : mode());
  });

  // The format buttons keep the editor's selection: a mousedown would take
  // focus from it first.
  $('format-bar').addEventListener('mousedown', (event) => event.preventDefault());
  $('format-bar').addEventListener('click', (event) => {
    const button = event.target.closest('[data-format]');
    if (button) insertFormat(button.dataset.format);
  });
  $('format-bar').querySelector('[data-format="bold"]').title = `Bold (${ui.formatShortcut('mod+b')})`;
  $('format-bar').querySelector('[data-format="italic"]').title = `Italic (${ui.formatShortcut('mod+i')})`;
}

function wireSettingsSheet() {
  buildShortcutLists();
  buildSettingsControls();

  $('btn-sheet-done').addEventListener('click', () => {
    T.trackClick('done', 'settings');
    closeSettingsSheet?.();
  });
  $('btn-sheet-back').addEventListener('click', () => showSettingsPage('settings'));
  $('row-shortcuts').addEventListener('click', () => showSettingsPage('shortcuts'));

  const speed = $('field-speed');
  speed.addEventListener('blur', () => commitNumberField(speed, 'linesPerMinute', LPM_RANGE));
  speed.addEventListener('keydown', (e) => e.key === 'Enter' && speed.blur());

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
  $('btn-help').addEventListener('click', () => openHelp('settings'));
  $('btn-rate').addEventListener('click', () => {
    T.trackClick('rate_app', 'settings');
    void T.openUrl(LINKS.source);
  });
  $('btn-advanced').addEventListener('click', () => {
    T.trackClick(showsAdvanced ? 'hide_advanced' : 'show_advanced', 'settings');
    // Leave the field being typed in first, so its figure is committed.
    document.activeElement?.blur?.();
    showsAdvanced = !showsAdvanced;
    void T.setStored('settings_show_advanced', showsAdvanced);
    syncSettings();
  });
  void T.getStored('settings_show_advanced').then((value) => {
    showsAdvanced = Boolean(value);
  });
  $('btn-reset').addEventListener('click', async () => {
    T.trackClick('reset_to_defaults', 'settings');
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
  });
}

/** Whether a key press belongs to a field other than the script, like search. */
const isTypingElsewhere = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) return false;
  if (target.closest('.editor')) return false;
  return target.matches('input, textarea, [contenteditable="true"]');
};

function wireKeyboard() {
  window.addEventListener('keydown', (event) => {
    if (event.defaultPrevented) return;
    if (prompter.isOpen() || cardsViewer.isOpen()) return;
    if (document.querySelector('.alert-layer, .menu-layer')) return;

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
    } else if (on('mod+f')) {
      event.preventDefault();
      toggleSidebar(true);
      library.focusSearch();
    } else if (on('mod+1') || on('mod+2')) {
      event.preventDefault();
      void switchMode(on('mod+1') ? 'teleprompter' : 'cards');
    } else if (on('mod+enter')) {
      event.preventDefault();
      start();
    } else if ((on('mod+b') || on('mod+i')) && !isTypingElsewhere(event)) {
      event.preventDefault();
      insertFormat(on('mod+b') ? 'bold' : 'italic');
    }
  });
}

function listenToBackend() {
  if (!T.listen) return;

  void T.listen('slide-update', (event) => onSlideUpdate(event.payload));

  // The one sign-in the app has: read access to the deck.
  void T.listen('slides-authorized', () => {
    app.slides.connected = true;
    selectSource('slides');
    if (!$('sheet-settings').hidden) syncSettings();
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
      else if (cardsViewer.isOpen()) cardsViewer.next();
      else start({ play: true });
      break;
    case 'timer-reset':
      if (prompter.isOpen()) prompter.restart();
      else if (cardsViewer.isOpen()) cardsViewer.restart();
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
