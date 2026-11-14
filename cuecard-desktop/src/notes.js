/**
 * The library: the scripts and decks that were saved, the collections they
 * are filed in, every saved version of each, and the one being written in each
 * mode.
 *
 * Saving is something you do, as it is on the phone — each mode's draft is
 * kept for you between launches, but it only joins the library when you name
 * it. Every save is a new version, and restoring an old one adds a copy of it
 * on top, so nothing saved is ever written over.
 */

import { getStored, setStored } from './tauri.js';
import { hasSeparators, limitedTitle, normalizingTags, plainText } from './parser.js';

export const MODES = ['teleprompter', 'cards'];

const KEY_SAVED = 'saved_notes';
const KEY_COLLECTIONS = 'library_collections';
const KEY_DRAFTS = 'library_drafts';
const KEY_MODE = 'library_mode';
const KEY_VERSIONS = 'note_versions';

// Written by older versions, read once on the way past.
const KEY_LEGACY_DRAFT = 'add_notes_content';
const KEY_LEGACY_CURRENT = 'current_note_id';
const KEY_MIGRATED_TIME = 'migrated_time_tags';
const KEY_MIGRATED_BARE_CUES = 'migrated_bare_cues';

/** What Add Sample Text writes, word for word as the phone app writes it. */
export const SAMPLE_TEXT = {
  teleprompter: `Welcome everyone.

I'm excited to be here today to talk about CueCard.

[smile and pause]

It keeps your speaker notes visible above all apps, so you can use your existing camera apps and still read your notes.

[pause]

It has a timer so you know if you're being brief… or too passionate.

[light chuckle]

And the colored highlights?

[emphasize]

Those are your secret cues — reminders to smile, pause, or not panic.

[pause]

Try it out. I think you'll love it.`,
  cards: `Welcome everyone. [smile]
[separator]
CueCard keeps your notes in view, *one card at a time*.
[separator]
Press → for the next card, and ← to go back. [pause]
[separator]
Thank you! [smile and wave]`,
};

const emptyDraft = (collection = null) => ({ text: '', noteId: null, collection });

export const state = {
  mode: 'teleprompter',
  saved: [],
  collections: [],
  drafts: { teleprompter: emptyDraft(), cards: emptyDraft() },
  /** Every version of every saved note: `{ [id]: [{ number, content, createdAt, restoredFrom }] }`. */
  versions: {},
};

const listeners = new Set();
export function onNotesChange(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}
const changed = () => listeners.forEach((fn) => fn());

const now = () => new Date().toISOString();

/** A UUID, upper case, as the phone app writes them: the storage folder it
 *  shares with the phone names every script by one. */
function newId() {
  if (crypto.randomUUID) return crypto.randomUUID().toUpperCase();
  const hex = [...crypto.getRandomValues(new Uint8Array(16))].map((b) => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20, 32)}`.toUpperCase();
}

const UUID = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/;

// =============================================================================
// THE STORAGE FOLDER
// =============================================================================

/**
 * What keeps the storage folder in step as scripts change, set once one is
 * chosen: `write(note)`, `arrange()`, `remove(ids)` and `sync()`.
 */
let folder = null;
export function setFolderHooks(hooks) {
  folder = hooks;
}

/** Bring in what a sync of the storage folder found changed outside the app. */
export async function applyFolderChanges(changes) {
  if (!changes) return false;
  let touched = false;

  if (changes.collections && JSON.stringify(changes.collections) !== JSON.stringify(state.collections)) {
    state.collections = [...changes.collections];
    touched = true;
  }
  const named = (name) => (name ? state.collections.find((c) => sameName(c, name)) || name : null);

  for (const incoming of changes.updated) {
    const note = { ...incoming, collection: named(incoming.collection) };
    const existing = noteById(note.id);
    // A script open in the editor with nothing unsaved follows its file.
    for (const mode of MODES) {
      const d = state.drafts[mode];
      if (d.noteId !== note.id) continue;
      if (existing && d.text === existing.content) d.text = note.content;
      d.collection = note.collection;
    }
    if (existing) {
      const previous = { ...existing };
      Object.assign(existing, note);
      if (previous.content !== note.content) recordVersion(existing, previous);
    } else {
      state.saved.unshift(note);
      recordVersion(note);
    }
    touched = true;
  }

  for (const id of changes.deleted) {
    state.saved = state.saved.filter((note) => note.id !== id);
    delete state.versions[id];
    // What was open stays in the editor, as a script of its own again.
    for (const mode of MODES) if (state.drafts[mode].noteId === id) state.drafts[mode].noteId = null;
    touched = true;
  }

  // Scripts in a collection deleted elsewhere are left in none.
  for (const note of state.saved) {
    if (note.collection && !hasCollection(note.collection)) {
      note.collection = null;
      touched = true;
    }
  }

  if (!touched) return false;
  await Promise.all([persistSaved(), persistVersions(), persistDrafts(), persistCollections()]);
  changed();
  return true;
}

// =============================================================================
// READING
// =============================================================================

export const draft = (mode = state.mode) => state.drafts[mode];
export const noteById = (id) => state.saved.find((note) => note.id === id) || null;
export const currentNote = (mode = state.mode) => noteById(draft(mode).noteId);
export const hasScript = (mode = state.mode) => Boolean(plainText(draft(mode).text).trim());

/** Whether there is anything to save: an edited note, or writing with no note yet. */
export function hasUnsavedChanges(mode = state.mode) {
  const note = currentNote(mode);
  if (!note) return hasScript(mode);
  return note.content !== draft(mode).text;
}

/** How many versions a note has. A note saved before versions existed has one. */
export const versionCount = (id) => state.versions[id]?.length || 1;

/** A note's versions, oldest first. Empty for a note that has only ever had one. */
export const versionsOf = (id) => state.versions[id] || [];

/** What a script says, tags and line breaks flattened, for a list row. */
export const preview = (content) => plainText(content || '').replace(/\s+/g, ' ').trim();

export const collectionsSorted = () =>
  [...state.collections].sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base', numeric: true }));

const sameName = (a, b) => (a || '').localeCompare(b || '', undefined, { sensitivity: 'accent' }) === 0;
export const hasCollection = (name) => state.collections.some((c) => sameName(c, name));

/** The collection's name as it was made, for a name typed in any case. */
const canonicalCollection = (name) => state.collections.find((c) => sameName(c, name)) || null;

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
  state.saved = (await getStored(KEY_SAVED)) || [];
  state.collections = (await getStored(KEY_COLLECTIONS)) || [];
  state.versions = (await getStored(KEY_VERSIONS)) || {};
  state.mode = MODES.includes(await getStored(KEY_MODE)) ? await getStored(KEY_MODE) : 'teleprompter';

  const drafts = await getStored(KEY_DRAFTS);
  if (drafts && typeof drafts === 'object') {
    for (const mode of MODES) state.drafts[mode] = { ...emptyDraft(), ...(drafts[mode] || {}) };
  }

  await migrateNotes();
  if (!drafts) await migrateLegacyDraft();
  await migrateIds();
  await migrateTimeTags(seedTimer);
  await migrateBareCues();

  // A draft can't point at a note that's gone.
  for (const mode of MODES) {
    const d = state.drafts[mode];
    if (d.noteId && !noteById(d.noteId)) d.noteId = null;
    if (d.collection && !hasCollection(d.collection)) d.collection = null;
  }
  changed();
}

/**
 * Notes used to be titled by their first line, and had no mode or collection.
 * The ones stored before get a title from their first line, the mode their
 * script is written in, and no collection.
 */
async function migrateNotes() {
  const needs = (note) => !note.title || !MODES.includes(note.mode) || !('collection' in note) || !note.createdAt;
  if (!state.saved.some(needs)) return;

  state.saved = state.saved.map((note) => ({
    ...note,
    title: note.title || limitedTitle(firstLine(note.content)) || 'Untitled Script',
    mode: MODES.includes(note.mode) ? note.mode : hasSeparators(note.content) ? 'cards' : 'teleprompter',
    collection: note.collection ?? null,
    createdAt: note.createdAt || note.updatedAt || now(),
    updatedAt: note.updatedAt || note.createdAt || now(),
  }));
  await setStored(KEY_SAVED, state.saved);
}

/**
 * Scripts used to be named by the time they were saved. The storage folder
 * names them by UUID, as the phone does, so every other id is swapped for one —
 * once — along with whatever pointed at it.
 */
async function migrateIds() {
  const renamed = new Map();
  for (const note of state.saved) {
    const id = String(note.id);
    const next = UUID.test(id.toUpperCase()) ? id.toUpperCase() : newId();
    if (next !== id) renamed.set(id, next);
  }
  if (!renamed.size) return;

  state.saved = state.saved.map((note) => (renamed.has(note.id) ? { ...note, id: renamed.get(note.id) } : note));
  const versions = {};
  for (const [id, list] of Object.entries(state.versions)) versions[renamed.get(id) || id] = list;
  state.versions = versions;
  for (const mode of MODES) {
    const d = state.drafts[mode];
    if (d.noteId && renamed.has(d.noteId)) d.noteId = renamed.get(d.noteId);
  }
  await Promise.all([persistSaved(), persistVersions(), persistDrafts()]);
}

/** One draft and one open note, from before there were two modes. */
async function migrateLegacyDraft() {
  const text = (await getStored(KEY_LEGACY_DRAFT)) || '';
  const id = (await getStored(KEY_LEGACY_CURRENT)) || null;
  const note = id ? noteById(id) : null;
  const mode = note?.mode || (hasSeparators(text) ? 'cards' : 'teleprompter');
  state.drafts[mode] = { text, noteId: note ? note.id : null, collection: note?.collection ?? null };
  await persistDrafts();
}

/**
 * Timing used to be written into the script as `[time mm:ss]`. It is a duration
 * set in the app now, so the tags come out of every stored script — once — and
 * the run is seeded from their sum, so nobody's timings quietly vanish.
 */
async function migrateTimeTags(seedTimer) {
  if (await getStored(KEY_MIGRATED_TIME)) return;

  const draftText = state.drafts.teleprompter.text;
  let seconds = timeTagTotal(draftText);
  if (!seconds) {
    const tagged = state.saved.find((note) => timeTagTotal(note.content || '') > 0);
    if (tagged) seconds = timeTagTotal(tagged.content);
  }

  for (const mode of MODES) state.drafts[mode].text = stripTimeTags(state.drafts[mode].text);
  await persistDrafts();
  if (state.saved.some((note) => timeTagTotal(note.content || '') > 0)) {
    state.saved = state.saved.map((note) => ({ ...note, content: stripTimeTags(note.content || '') }));
    await setStored(KEY_SAVED, state.saved);
  }

  if (seconds > 0) seedTimer?.(seconds);
  await setStored(KEY_MIGRATED_TIME, true);
}

/**
 * Cues used to be written `[cue …]`. The drafts and every saved script are
 * brought up to `[…]` — once — keeping each note's date so nothing looks edited.
 */
async function migrateBareCues() {
  if (await getStored(KEY_MIGRATED_BARE_CUES)) return;

  for (const mode of MODES) state.drafts[mode].text = normalizingTags(state.drafts[mode].text);
  await persistDrafts();
  const rewritten = state.saved.map((note) => ({ ...note, content: normalizingTags(note.content || '') }));
  if (rewritten.some((note, index) => note.content !== (state.saved[index].content || ''))) {
    state.saved = rewritten;
    await setStored(KEY_SAVED, state.saved);
  }

  await setStored(KEY_MIGRATED_BARE_CUES, true);
}

function firstLine(content) {
  for (const line of (content || '').split(/\r?\n/)) {
    const cleaned = plainText(line).trim();
    if (cleaned) return cleaned.slice(0, 60);
  }
  return '';
}

// =============================================================================
// PERSISTING
// =============================================================================

let draftTimer = null;

const persistDrafts = () => setStored(KEY_DRAFTS, state.drafts);
const persistSaved = () => setStored(KEY_SAVED, state.saved);
const persistVersions = () => setStored(KEY_VERSIONS, state.versions);
const persistCollections = () => setStored(KEY_COLLECTIONS, state.collections);

/** Write the drafts out now, without waiting for the pause in the typing. */
export async function flushDraft() {
  clearTimeout(draftTimer);
  await persistDrafts();
}

// =============================================================================
// THE MODE AND ITS DRAFT
// =============================================================================

export async function setMode(mode) {
  if (!MODES.includes(mode) || mode === state.mode) return;
  state.mode = mode;
  await setStored(KEY_MODE, mode);
  changed();
}

/** Hold the draft. Persisting it can wait for a pause in the typing. */
export function setDraft(text, { mode = state.mode, immediate = false } = {}) {
  state.drafts[mode].text = text;
  clearTimeout(draftTimer);
  if (immediate) void persistDrafts();
  else draftTimer = setTimeout(persistDrafts, 400);
  changed();
}

/** Start a new script or deck, in the collection being shown. */
export async function newScript(mode = state.mode, collection = null) {
  state.drafts[mode] = emptyDraft(canonicalCollection(collection));
  await persistDrafts();
  changed();
}

/** Let go of what was written without saving it. */
export async function discardDraft(mode = state.mode) {
  const note = currentNote(mode);
  state.drafts[mode] = note
    ? { text: note.content, noteId: note.id, collection: note.collection }
    : emptyDraft(state.drafts[mode].collection);
  await persistDrafts();
  changed();
}

/** Close the note open in a mode, leaving that mode's draft empty. */
export async function closeNote(mode = state.mode) {
  state.drafts[mode] = emptyDraft();
  await persistDrafts();
  changed();
}

/** Open a saved note in the editor of its own mode. */
export async function openNote(id) {
  const note = noteById(id);
  if (!note) return;
  state.drafts[note.mode] = { text: note.content, noteId: note.id, collection: note.collection };
  state.mode = note.mode;
  await setStored(KEY_MODE, note.mode);
  await persistDrafts();
  changed();
}

export function addSampleText(mode = state.mode) {
  setDraft(SAMPLE_TEXT[mode], { mode, immediate: true });
}

// =============================================================================
// SAVING, AND EVERY VERSION OF IT
// =============================================================================

/**
 * Keep `note`'s text as its newest version, unless it already is. `previous`
 * is the note as it was saved before, so a note saved before versions existed
 * starts its history with what it held then.
 */
function recordVersion(note, previous = null, restoredFrom = null) {
  const list = state.versions[note.id] ? [...state.versions[note.id]] : [];
  if (!list.length && previous && previous.content !== note.content) {
    list.push({ number: 1, content: previous.content, createdAt: previous.updatedAt, restoredFrom: null });
  }
  const last = list[list.length - 1];
  if (last && last.content === note.content) return;
  list.push({ number: (last?.number || 0) + 1, content: note.content, createdAt: note.updatedAt, restoredFrom });
  state.versions[note.id] = list;
}

/** Save the draft as a new script under a title of its own. */
export async function saveAsNew(title, mode = state.mode) {
  if (!hasScript(mode)) return null;
  const d = state.drafts[mode];
  const stamp = now();
  const note = {
    id: newId(),
    title: limitedTitle(title) || 'Untitled Script',
    content: d.text,
    mode,
    collection: canonicalCollection(d.collection ?? currentNote(mode)?.collection),
    createdAt: stamp,
    updatedAt: stamp,
  };
  state.saved.unshift(note);
  recordVersion(note);
  d.noteId = note.id;
  d.collection = note.collection;
  await Promise.all([persistSaved(), persistVersions(), persistDrafts()]);
  changed();
  void folder?.write(note);
  void folder?.arrange();
  return note;
}

/** Save over the script that is open, as its next version. */
export async function saveCurrent(mode = state.mode) {
  const note = currentNote(mode);
  if (!note) return;
  const previous = { ...note };
  note.content = state.drafts[mode].text;
  note.updatedAt = now();
  recordVersion(note, previous);
  await Promise.all([persistSaved(), persistVersions()]);
  changed();
  void folder?.write(note);
}

/**
 * Bring an older version back, as a new version on top. The editor, if it has
 * the note open, takes it too.
 */
export async function restoreVersion(id, number) {
  const note = noteById(id);
  const version = versionsOf(id).find((v) => v.number === number);
  if (!note || !version) return false;
  const previous = { ...note };
  note.content = version.content;
  note.updatedAt = now();
  recordVersion(note, previous, number);
  for (const mode of MODES) {
    if (state.drafts[mode].noteId === id) state.drafts[mode].text = version.content;
  }
  await Promise.all([persistSaved(), persistVersions(), persistDrafts()]);
  changed();
  void folder?.write(note);
  return true;
}

// =============================================================================
// THE LIBRARY
// =============================================================================

export async function renameNote(id, title) {
  const note = noteById(id);
  const name = limitedTitle(title);
  if (!note || !name) return;
  note.title = name;
  await persistSaved();
  changed();
  void folder?.write(note);
}

/** A copy of a note, as a script of its own with its own history. */
export async function duplicateNote(id) {
  const note = noteById(id);
  if (!note) return null;
  const stamp = now();
  const copy = {
    ...note,
    id: newId(),
    title: limitedTitle(`${note.title} Copy`),
    createdAt: stamp,
    updatedAt: stamp,
  };
  state.saved.unshift(copy);
  recordVersion(copy);
  await Promise.all([persistSaved(), persistVersions()]);
  changed();
  void folder?.write(copy);
  void folder?.arrange();
  return copy;
}

export async function deleteNote(id) {
  void folder?.remove([id]);
  state.saved = state.saved.filter((note) => note.id !== id);
  delete state.versions[id];
  for (const mode of MODES) {
    if (state.drafts[mode].noteId === id) state.drafts[mode] = emptyDraft();
  }
  await Promise.all([persistSaved(), persistVersions(), persistDrafts()]);
  changed();
}

/** Every saved script, gone. What's being written and was never saved stays. */
export async function deleteAll() {
  void folder?.remove(state.saved.map((note) => note.id));
  state.saved = [];
  state.versions = {};
  for (const mode of MODES) {
    if (state.drafts[mode].noteId) state.drafts[mode] = emptyDraft();
  }
  await Promise.all([persistSaved(), persistVersions(), persistDrafts()]);
  changed();
}

/** Keep an imported file as a script titled by its filename, and open it. */
export async function importScript(title, content, collection = null) {
  const mode = hasSeparators(content) ? 'cards' : 'teleprompter';
  const stamp = now();
  const note = {
    id: newId(),
    title: limitedTitle(title) || 'Imported Script',
    content,
    mode,
    collection: canonicalCollection(collection),
    createdAt: stamp,
    updatedAt: stamp,
  };
  state.saved.unshift(note);
  recordVersion(note);
  await Promise.all([persistSaved(), persistVersions()]);
  void folder?.write(note);
  void folder?.arrange();
  await openNote(note.id);
  return note;
}

// =============================================================================
// COLLECTIONS
// =============================================================================

/** A name for a collection, on one line and not too long. */
export const collectionName = (name) => String(name || '').replace(/\s+/g, ' ').trim().slice(0, 40).trim();

export async function createCollection(name) {
  const clean = collectionName(name);
  if (!clean) return null;
  if (hasCollection(clean)) return canonicalCollection(clean);
  state.collections.push(clean);
  await persistCollections();
  changed();
  void folder?.sync();
  return clean;
}

export async function renameCollection(from, to) {
  const clean = collectionName(to);
  if (!clean || !hasCollection(from)) return null;
  if (hasCollection(clean) && !sameName(clean, from)) return null;
  const old = canonicalCollection(from);
  state.collections = state.collections.map((c) => (c === old ? clean : c));
  for (const note of state.saved) if (note.collection === old) note.collection = clean;
  for (const mode of MODES) if (state.drafts[mode].collection === old) state.drafts[mode].collection = clean;
  await Promise.all([persistCollections(), persistSaved(), persistDrafts()]);
  changed();
  void folder?.sync();
  return clean;
}

/** The scripts in it aren't deleted. They stay in All. */
export async function deleteCollection(name) {
  const old = canonicalCollection(name);
  if (!old) return;
  state.collections = state.collections.filter((c) => c !== old);
  for (const note of state.saved) if (note.collection === old) note.collection = null;
  for (const mode of MODES) if (state.drafts[mode].collection === old) state.drafts[mode].collection = null;
  await Promise.all([persistCollections(), persistSaved(), persistDrafts()]);
  changed();
  void folder?.sync();
}

/** File a note in a collection, or in none. An empty id is the mode's draft. */
export async function setNoteCollection(id, name, mode = state.mode) {
  const collection = name ? canonicalCollection(name) : null;
  if (!id) {
    state.drafts[mode].collection = collection;
    await persistDrafts();
    changed();
    return;
  }
  const note = noteById(id);
  if (!note) return;
  note.collection = collection;
  for (const m of MODES) if (state.drafts[m].noteId === id) state.drafts[m].collection = collection;
  await Promise.all([persistSaved(), persistDrafts()]);
  changed();
  void folder?.arrange();
}
