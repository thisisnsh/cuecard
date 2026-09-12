/**
 * The scripts: the one being written, and the ones that were saved.
 *
 * Saving is something you do, as it is on the phone — the draft is kept for you
 * between launches, but it only joins the list when you name it.
 */

import { getStored, setStored } from './tauri.js';
import { withoutCues } from './parser.js';

const KEY_DRAFT = 'add_notes_content';
const KEY_SAVED = 'saved_notes';
const KEY_CURRENT = 'current_note_id';
const KEY_MIGRATED_TIME = 'migrated_time_tags';

/** What Add Sample Text writes, word for word as the phone app writes it. */
export const DEFAULT_NOTE_TEXT = `Welcome everyone.

I'm excited to be here today to talk about CueCard.

[cue smile and pause]

It keeps your speaker notes visible above all apps, so you can use your existing camera apps and still read your notes.

[cue pause]

It has a timer so you know if you're being brief… or too passionate.

[cue light chuckle]

And the colored highlights?

[cue emphasize]

Those are your secret cues — reminders to smile, pause, or not panic.

[cue pause]

Try it out. I think you'll love it.`;

export const state = {
  draft: '',
  saved: [],
  currentId: null,
};

const listeners = new Set();
export function onNotesChange(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}
const changed = () => listeners.forEach((fn) => fn());

export const currentNote = () => state.saved.find((note) => note.id === state.currentId) || null;
export const hasScript = () => Boolean(state.draft.trim());

/** Whether there is anything to save: an edited note, or writing with no note yet. */
export function hasUnsavedChanges() {
  const note = currentNote();
  if (!note) return hasScript();
  return note.content !== state.draft;
}

/** What a script says, cues and line breaks flattened, for a list row. */
export const preview = (content) => withoutCues(content || '').replace(/\s+/g, ' ').trim();

export function noteDate(isoString) {
  const date = new Date(isoString);
  const minutes = Math.floor((Date.now() - date) / 60000);
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes}m ago`;
  if (minutes < 1440) return `${Math.floor(minutes / 60)}h ago`;
  if (minutes < 10080) return `${Math.floor(minutes / 1440)}d ago`;
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

// =============================================================================
// LOADING, AND WHAT HAD TO BE CARRIED OVER
// =============================================================================

const TIME_TAG = /\[time[ \t]+(\d{1,2}):(\d{2})\][ \t]*\n?/gi;
const timeTagTotal = (text) => {
  let total = 0;
  for (const match of text.matchAll(new RegExp(TIME_TAG.source, 'gi'))) {
    total += Number(match[1]) * 60 + Number(match[2]);
  }
  return total;
};
const stripTimeTags = (text) => text.replace(new RegExp(TIME_TAG.source, 'gi'), '');

/**
 * @param seedTimer Called with a number of seconds if scripts carried `[time]`
 *   tags and no timer duration has been set yet.
 */
export async function loadNotes({ seedTimer } = {}) {
  state.draft = (await getStored(KEY_DRAFT)) || '';
  state.saved = (await getStored(KEY_SAVED)) || [];
  state.currentId = (await getStored(KEY_CURRENT)) || null;

  await migrateNoteTitles();
  await migrateTimeTags(seedTimer);

  if (state.currentId && !currentNote()) state.currentId = null;
  changed();
}

/**
 * Notes used to be titled by their first line. They carry a title you chose
 * now, so the ones stored before that get one taken from their first line.
 */
async function migrateNoteTitles() {
  if (!state.saved.some((note) => !note.title)) return;

  state.saved = state.saved.map((note) => ({
    ...note,
    title: note.title || firstLine(note.content) || 'Untitled Script',
    createdAt: note.createdAt || note.updatedAt,
  }));
  await setStored(KEY_SAVED, state.saved);
}

/**
 * Timing used to be written into the script as `[time mm:ss]`. It is a duration
 * set in the app now, so the tags come out of every stored script — once — and
 * the run is seeded from their sum, so nobody's timings quietly vanish.
 */
async function migrateTimeTags(seedTimer) {
  if (await getStored(KEY_MIGRATED_TIME)) return;

  let seconds = timeTagTotal(state.draft);
  if (!seconds) {
    const tagged = state.saved.find((note) => timeTagTotal(note.content || '') > 0);
    if (tagged) seconds = timeTagTotal(tagged.content);
  }

  if (state.draft) {
    state.draft = stripTimeTags(state.draft);
    await setStored(KEY_DRAFT, state.draft);
  }
  if (state.saved.some((note) => timeTagTotal(note.content || '') > 0)) {
    state.saved = state.saved.map((note) => ({ ...note, content: stripTimeTags(note.content || '') }));
    await setStored(KEY_SAVED, state.saved);
  }

  if (seconds > 0) seedTimer?.(seconds);
  await setStored(KEY_MIGRATED_TIME, true);
}

function firstLine(content) {
  for (const line of (content || '').split(/\r?\n/)) {
    const cleaned = withoutCues(line).trim();
    if (cleaned) return cleaned.slice(0, 60);
  }
  return '';
}

// =============================================================================
// EDITING
// =============================================================================

let saveTimer = null;

/** Hold the draft. Persisting it can wait for a pause in the typing. */
export function setDraft(text, { immediate = false } = {}) {
  state.draft = text;
  clearTimeout(saveTimer);
  if (immediate) {
    void setStored(KEY_DRAFT, text);
  } else {
    saveTimer = setTimeout(() => setStored(KEY_DRAFT, state.draft), 400);
  }
  changed();
}

/** Write the draft out now, without waiting for the pause in the typing. */
export async function flushDraft() {
  clearTimeout(saveTimer);
  await setStored(KEY_DRAFT, state.draft);
}

async function persistSaved() {
  await setStored(KEY_SAVED, state.saved);
  await setStored(KEY_CURRENT, state.currentId);
  changed();
}

/** Save the draft as a new script under a title of its own. */
export async function saveAsNew(title) {
  if (!hasScript()) return null;
  const now = new Date().toISOString();
  const note = { id: `${Date.now()}`, title, content: state.draft, createdAt: now, updatedAt: now };
  state.saved.unshift(note);
  state.currentId = note.id;
  await persistSaved();
  return note;
}

/** Save over the script that is open. */
export async function saveCurrent() {
  const note = currentNote();
  if (!note) return;
  note.content = state.draft;
  note.updatedAt = new Date().toISOString();
  state.saved = [note, ...state.saved.filter((n) => n.id !== note.id)];
  await persistSaved();
}

export async function renameNote(id, title) {
  const note = state.saved.find((n) => n.id === id);
  if (!note) return;
  note.title = title;
  note.updatedAt = new Date().toISOString();
  await persistSaved();
}

export async function deleteNote(id) {
  state.saved = state.saved.filter((note) => note.id !== id);
  if (state.currentId === id) {
    state.currentId = null;
    setDraft('', { immediate: true });
  }
  await persistSaved();
}

/** Open a saved script in the editor. */
export async function openNote(id) {
  const note = state.saved.find((n) => n.id === id);
  if (!note) return;
  state.currentId = note.id;
  note.updatedAt = new Date().toISOString();
  state.saved = [note, ...state.saved.filter((n) => n.id !== note.id)];
  setDraft(note.content, { immediate: true });
  await persistSaved();
}

export async function newScript() {
  state.currentId = null;
  setDraft('', { immediate: true });
  await setStored(KEY_CURRENT, null);
  changed();
}

/** Keep an imported file as a script titled by its filename. */
export async function importScript(title, content) {
  state.currentId = null;
  setDraft(content, { immediate: true });
  return saveAsNew(title);
}

export function addSampleText() {
  setDraft(DEFAULT_NOTE_TEXT, { immediate: true });
}

/** Everything this machine was keeping, gone. */
export async function clearAll() {
  state.draft = '';
  state.saved = [];
  state.currentId = null;
  await setStored(KEY_DRAFT, '');
  await setStored(KEY_SAVED, []);
  await setStored(KEY_CURRENT, null);
  changed();
}
