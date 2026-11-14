/**
 * A folder the user picked where saved scripts are also kept, one text file
 * each — the phone app's storage folder, kept the same way, so one folder in
 * iCloud Drive brings the same scripts to both. Edits made to the files outside
 * the app come back in on the next sync, and whichever side changed last wins.
 *
 * A port of the iOS app's `NoteFolder`, writing exactly what it writes:
 *
 * - every script's file at the top of the folder, `.txt` or `.md`
 * - `.cuecard.json`, the index matching each file to its script
 * - `.cuecard-library.json`, which scripts are in each collection
 * - `.cuecard-images/`, the images the scripts place
 *
 * The two hidden lists are read and written the way Swift's JSONEncoder writes
 * them: the index as a flat array of id and entry, and every date as seconds
 * since 2001.
 */

import * as T from './tauri.js';
import { imageNames, normalizingTags, suggestedFileName } from './parser.js';
import { imageBytes, keepImage } from './images.js';
import { imagesList } from './tauri.js';

const INDEX = '.cuecard.json';
const LIBRARY = '.cuecard-library.json';
const IMAGES = '.cuecard-images';
const TEXT_EXTENSIONS = new Set(['txt', 'md']);
const MAX_FILE_SIZE = 10 * 1024 * 1024;

const KEY_PATH = 'notes_folder_path';
const KEY_PENDING = 'notes_folder_pending_deletions';
const KEY_LIBRARY_MODIFIED = 'notes_folder_library_modified';
const KEY_SYNCED_COLLECTIONS = 'notes_folder_synced_collections';

/** Milliseconds from 1970 to 2001, where Swift counts dates from. */
const REFERENCE = 978_307_200_000;
const toSwift = (ms) => (ms - REFERENCE) / 1000;
const fromSwift = (seconds) => seconds * 1000 + REFERENCE;
const ms = (iso) => Date.parse(iso);
const iso = (time) => new Date(time).toISOString();

/** Dates read back from the index can be off in the last fraction. */
const sameDate = (a, b) => (a == null || b == null ? a == null && b == null : Math.abs(a - b) < 1);

const MODES = ['teleprompter', 'cards'];
const isPlainName = (name) => typeof name === 'string' && name && name !== '.' && name !== '..' && !/[/\\]/.test(name);
const extensionOf = (name) => (name.includes('.') ? name.split('.').pop().toLowerCase() : '');
const sameName = (a, b) => a.localeCompare(b, undefined, { sensitivity: 'accent' }) === 0;
const containsCollection = (list, name) => list.some((c) => sameName(c, name));

const local = {
  path: null,
  pending: new Set(),
  libraryModified: null,
  syncedCollections: null,
};

// =============================================================================
// THE FOLDER ITSELF
// =============================================================================

export async function loadFolder() {
  local.path = (await T.getStored(KEY_PATH)) || null;
  local.pending = new Set((await T.getStored(KEY_PENDING)) || []);
  local.libraryModified = (await T.getStored(KEY_LIBRARY_MODIFIED)) ?? null;
  local.syncedCollections = (await T.getStored(KEY_SYNCED_COLLECTIONS)) ?? null;
}

export const isChosen = () => Boolean(local.path);
export const folderPath = () => local.path;

/** The folder's name, as Finder shows it. */
export const folderName = () => (local.path ? local.path.split(/[\\/]/).filter(Boolean).pop() : null);

export const isReachable = () => (local.path ? T.folder.check(local.path) : Promise.resolve(false));
export const isInICloud = () => (local.path ? T.folder.isICloud(local.path) : Promise.resolve(false));

const persistPending = () => T.setStored(KEY_PENDING, [...local.pending]);
async function setLibraryState(modified, collections) {
  local.libraryModified = modified ?? null;
  local.syncedCollections = collections;
  await T.setStored(KEY_LIBRARY_MODIFIED, local.libraryModified);
  await T.setStored(KEY_SYNCED_COLLECTIONS, local.syncedCollections);
}

/** Start keeping scripts in `path`. Its collections, if CueCard kept them
 *  there before, are taken in on the next sync. */
export async function choose(path) {
  local.path = path;
  local.pending = new Set();
  await T.setStored(KEY_PATH, path);
  await persistPending();
  await setLibraryState(null, null);
}

/** Stop using the folder. The files in it are left alone, for the phone. */
export async function forget() {
  local.path = null;
  local.pending = new Set();
  await T.setStored(KEY_PATH, null);
  await persistPending();
  await setLibraryState(null, null);
}

/** An image from the folder, for one this computer doesn't have yet. */
export async function folderImage(name) {
  if (!local.path) return null;
  return T.folder.imageRead(local.path, name);
}

// One thing at a time: each step reads the index, changes it and writes it.
let chain = Promise.resolve();
function enqueue(fn) {
  const run = chain.then(() => (local.path ? fn(local.path) : undefined));
  chain = run.catch((error) => console.error('Storage folder:', error));
  return run;
}

// =============================================================================
// THE HIDDEN LISTS
// =============================================================================

/** `{ [id]: { file, title, mode, createdAt, noteUpdatedAt, fileModifiedAt } }`,
 *  dates in milliseconds. Entries naming a path rather than a file in the
 *  folder are dropped: anything with access can rewrite the index. */
async function readIndex(folder) {
  const text = await T.folder.readText(folder, INDEX);
  if (!text) return {};
  let raw;
  try {
    raw = JSON.parse(text);
  } catch {
    return {};
  }
  const pairs = [];
  if (Array.isArray(raw)) for (let i = 0; i + 1 < raw.length; i += 2) pairs.push([raw[i], raw[i + 1]]);
  else if (raw && typeof raw === 'object') pairs.push(...Object.entries(raw));

  const index = {};
  for (const [id, entry] of pairs) {
    if (typeof id !== 'string' || !entry || !isPlainName(entry.file)) continue;
    if (typeof entry.createdAt !== 'number' || typeof entry.noteUpdatedAt !== 'number') continue;
    index[id.toUpperCase()] = {
      file: entry.file,
      title: String(entry.title ?? ''),
      mode: MODES.includes(entry.mode) ? entry.mode : 'teleprompter',
      createdAt: fromSwift(entry.createdAt),
      noteUpdatedAt: fromSwift(entry.noteUpdatedAt),
      fileModifiedAt: typeof entry.fileModifiedAt === 'number' ? fromSwift(entry.fileModifiedAt) : null,
    };
  }
  return index;
}

/** Written as Swift writes a dictionary keyed by UUID: id, entry, id, entry. */
async function writeIndex(folder, index) {
  const flat = [];
  for (const [id, entry] of Object.entries(index)) {
    const out = {
      createdAt: toSwift(entry.createdAt),
      file: entry.file,
      mode: entry.mode,
      noteUpdatedAt: toSwift(entry.noteUpdatedAt),
      title: entry.title,
    };
    if (entry.fileModifiedAt != null) out.fileModifiedAt = toSwift(entry.fileModifiedAt);
    flat.push(id, out);
  }
  await T.folder.writeText(folder, INDEX, JSON.stringify(flat));
}

function sameIndex(a, b) {
  const ids = Object.keys(a);
  if (ids.length !== Object.keys(b).length) return false;
  return ids.every((id) => {
    const x = a[id];
    const y = b[id];
    return y && x.file === y.file && x.title === y.title && x.mode === y.mode
      && sameDate(x.noteUpdatedAt, y.noteUpdatedAt) && sameDate(x.fileModifiedAt, y.fileModifiedAt);
  });
}

const cloneIndex = (index) => Object.fromEntries(Object.entries(index).map(([id, entry]) => [id, { ...entry }]));

/** A name for a collection, on one line and not too long. */
const collectionName = (name) => String(name || '').replace(/\s+/g, ' ').trim().slice(0, 40).trim();

/** The folder's list of how the scripts are filed, and when it last changed. */
async function readLibrary(folder, listing) {
  const text = await T.folder.readText(folder, LIBRARY);
  if (!text) return null;
  let raw;
  try {
    raw = JSON.parse(text);
  } catch {
    return null;
  }
  if (!raw || !Array.isArray(raw.collections) || !Array.isArray(raw.unfiled)) return null;
  const seen = [];
  const collections = [];
  for (const entry of raw.collections) {
    const name = collectionName(entry?.name);
    if (!name || containsCollection(seen, name)) continue;
    seen.push(name);
    collections.push({ name, notes: (entry.notes || []).filter((id) => typeof id === 'string').map((id) => id.toUpperCase()) });
  }
  const library = { collections, unfiled: raw.unfiled.filter((id) => typeof id === 'string').map((id) => id.toUpperCase()) };
  const modified = listing.find((entry) => entry.name === LIBRARY)?.modified ?? null;
  return { library, modified };
}

/** The collection a script is in: undefined if the list doesn't place it,
 *  null for none. */
function placed(library, id) {
  if (library.unfiled.includes(id)) return null;
  const found = library.collections.find((c) => c.notes.includes(id));
  return found ? found.name : undefined;
}

/** The list of `collections`, each of `ids` in its collection or unfiled,
 *  sorted, so an unchanged list is written the same. */
function makeLibrary(ids, collections, collectionOf) {
  const filed = new Map();
  const unfiled = [];
  for (const id of [...ids].sort()) {
    const name = collectionOf(id);
    const match = name ? collections.find((c) => sameName(c, name)) : null;
    if (match) filed.set(match, [...(filed.get(match) || []), id]);
    else unfiled.push(id);
  }
  return { collections: collections.map((name) => ({ name, notes: filed.get(name) || [] })), unfiled };
}

const sameLibrary = (a, b) => JSON.stringify(a) === JSON.stringify(b);

/** Pretty and with sorted keys, as the phone writes it. */
async function writeLibrary(folder, library) {
  const sorted = {
    collections: library.collections.map((c) => ({ name: c.name, notes: c.notes })),
    unfiled: library.unfiled,
  };
  const modified = await T.folder.writeText(folder, LIBRARY, JSON.stringify(sorted, null, 2));
  if (modified === undefined) return;
  await setLibraryState(modified, library.collections.map((c) => c.name));
}

// =============================================================================
// FILES
// =============================================================================

/** `base` as a file name, numbered if another file has it. */
function uniqueName(base, ext, taken) {
  let name = `${base}.${ext}`;
  let number = 2;
  while (taken.has(name.toLowerCase())) {
    name = `${base} ${number}.${ext}`;
    number += 1;
  }
  return name;
}

async function takenNames(folder, index) {
  const listing = (await T.folder.list(folder)) || [];
  return new Set([...listing.map((e) => e.name), ...Object.values(index).map((e) => e.file)].map((n) => n.toLowerCase()));
}

async function readContent(folder, file) {
  const text = await T.folder.readText(folder, file);
  return text == null ? null : normalizingTags(text.replace(/\r\n?/g, '\n'));
}

/** Copy the images a script places into the folder, the ones not already there. */
async function writeImages(folder, content, present) {
  const names = imageNames(content);
  if (!names.size) return;
  const there = present || new Set(await T.folder.imagesList(folder));
  for (const name of names) {
    if (there.has(name) || there.has(`.${name}.icloud`)) continue;
    const bytes = await imageBytes(name);
    if (bytes && (await T.folder.imageWrite(folder, name, bytes))) there.add(name);
  }
}

/** Write a script to its file, renaming the file if the title changed. */
async function writeNote(folder, note, index) {
  const existing = index[note.id];
  const base = suggestedFileName(note.title, note.content);
  let file = existing?.file;
  if (file && existing.title !== note.title) {
    // Renamed in the app, so the file follows, keeping its extension.
    const taken = await takenNames(folder, index);
    taken.delete(file.toLowerCase());
    const target = uniqueName(base, extensionOf(file) || 'txt', taken);
    if (target !== file && (await T.folder.rename(folder, file, target))) file = target;
  }
  const name = file || uniqueName(base, 'txt', await takenNames(folder, index));
  await writeImages(folder, note.content);
  const modified = await T.folder.writeText(folder, name, note.content);
  if (modified === undefined) return;
  index[note.id] = {
    file: name,
    title: note.title,
    mode: note.mode,
    createdAt: ms(note.createdAt),
    noteUpdatedAt: ms(note.updatedAt),
    fileModifiedAt: modified,
  };
}

/** Try again to delete the files of scripts deleted in the app, dropping each
 *  from the index once it's gone. Returns the entries still waiting. */
async function deletePending(folder, index) {
  const waiting = {};
  for (const id of local.pending) {
    const entry = index[id];
    if (entry && !(await T.folder.remove(folder, entry.file))) waiting[id] = entry;
    else delete index[id];
  }
  local.pending = new Set(Object.keys(waiting));
  await persistPending();
  return waiting;
}

// =============================================================================
// WHAT THE APP CALLS
// =============================================================================

/** Write a script to its file, as when it's saved or renamed. */
export function write(note) {
  return enqueue(async (folder) => {
    const index = await readIndex(folder);
    await writeNote(folder, note, index);
    await writeIndex(folder, index);
  });
}

/**
 * Write down which scripts are in each collection. If the list was changed
 * outside the app since it was last in step, it's left for the next sync to
 * take in first.
 */
export function arrange(notes, collections) {
  return enqueue(async (folder) => {
    const listing = (await T.folder.list(folder)) || [];
    const stored = await readLibrary(folder, listing);
    if (stored && !sameDate(stored.modified, local.libraryModified)) return;
    const index = await readIndex(folder);
    const appNotes = new Map(notes.map((n) => [n.id, n]));
    const ids = new Set([...Object.keys(index), ...appNotes.keys()].filter((id) => !local.pending.has(id)));
    const library = makeLibrary(ids, collections, (id) => {
      if (appNotes.has(id)) return appNotes.get(id).collection;
      return stored ? placed(stored.library, id) ?? null : null;
    });
    if (!stored || !sameLibrary(library, stored.library)) await writeLibrary(folder, library);
  });
}

/** Delete the files of scripts deleted in the app. Any that can't be yet are
 *  tried again on each sync, and kept from coming back in meanwhile. */
export function remove(ids) {
  if (!local.path) return Promise.resolve(true);
  ids.forEach((id) => local.pending.add(id));
  return enqueue(async (folder) => {
    await persistPending();
    const index = await readIndex(folder);
    const original = cloneIndex(index);
    await deletePending(folder, index);
    if (!sameIndex(index, original)) await writeIndex(folder, index);
    return ids.every((id) => !local.pending.has(id));
  }).then((done) => done ?? true);
}

/**
 * Bring the folder and the app's scripts in step: files edited, added,
 * renamed, moved or deleted outside the app come back as changes, and scripts
 * the folder doesn't have yet are written to it. Whichever side changed last
 * wins. Which scripts are in each of the `collections` is brought in step the
 * same way.
 *
 * Resolves with `{ updated, deleted, tooLarge, undeletable, collections }`,
 * or null if the folder couldn't be looked at.
 */
export function sync(notes, collections) {
  return enqueue((folder) => syncIn(folder, notes, collections)).then((changes) => changes ?? null);
}

async function syncIn(folder, notes, collections) {
  // If the folder can't be listed, nothing can be told about it, so nothing is
  // changed on either side.
  const listing = await T.folder.list(folder);
  if (!listing) return null;

  const changes = { updated: [], deleted: [], tooLarge: [], undeletable: [], collections: null };
  const index = await readIndex(folder);
  const originalIndex = cloneIndex(index);
  // Files of deleted scripts still there are left alone, not read back in.
  const undeletable = await deletePending(folder, index);
  changes.undeletable = Object.values(undeletable).map((e) => e.file).sort();

  const appNotes = new Map(notes.map((n) => [n.id, n]));
  const meta = new Map(listing.map((entry) => [entry.name, entry]));
  const files = new Set(
    listing.filter((e) => !e.isDir && !e.name.startsWith('.') && TEXT_EXTENSIONS.has(extensionOf(e.name))).map((e) => e.name)
  );
  // Reading one of these fails, which leaves it and its script as they are.
  changes.tooLarge = [...files].filter((f) => meta.get(f).size > MAX_FILE_SIZE).sort();
  const tooLarge = new Set(changes.tooLarge);

  // Files in iCloud Drive that aren't downloaded show up as ".Name.txt.icloud".
  // They're still there, so they're asked for and left until they arrive.
  const pending = new Set();
  for (const entry of listing) {
    if (!entry.name.startsWith('.') || !entry.name.endsWith('.icloud')) continue;
    const name = entry.name.slice(1, -'.icloud'.length);
    if (name === INDEX || name === LIBRARY) continue;
    pending.add(name);
    void T.folder.download(folder, entry.name);
  }

  const claimed = new Set();
  const missing = [];

  for (const [id, entry] of Object.entries(index)) {
    if (pending.has(entry.file) || undeletable[id]) {
      claimed.add(entry.file);
      continue;
    }
    if (!files.has(entry.file)) {
      missing.push(id);
      continue;
    }
    claimed.add(entry.file);

    const modified = meta.get(entry.file).modified ?? null;
    const fileChanged = !sameDate(modified, entry.fileModifiedAt);
    const app = appNotes.get(id);
    const appUpdated = app ? ms(app.updatedAt) : null;

    if (app && !sameDate(appUpdated, entry.noteUpdatedAt) && appUpdated > entry.noteUpdatedAt
        && (!fileChanged || appUpdated >= (modified ?? -Infinity))) {
      await writeNote(folder, app, index);
    } else if (fileChanged || !app) {
      // Edited outside the app, or a script this computer doesn't have yet.
      if (tooLarge.has(entry.file)) continue;
      const content = await readContent(folder, entry.file);
      if (content == null) continue;
      // The same words with a new date — as a file copied in by iCloud Drive
      // can come — is no edit, and isn't written back, so the phone doesn't
      // see a change it would answer with one of its own.
      if (app && content === app.content && entry.title === app.title && entry.mode === app.mode) continue;
      const updatedAt = fileChanged ? modified ?? Date.now() : entry.noteUpdatedAt;
      const note = {
        id,
        title: entry.title || app?.title || 'Untitled Script',
        content,
        mode: entry.mode,
        // Its collection is settled below, with the others'.
        collection: app?.collection ?? null,
        createdAt: iso(entry.createdAt),
        updatedAt: iso(updatedAt),
      };
      changes.updated.push(note);
      index[id].noteUpdatedAt = updatedAt;
      index[id].fileModifiedAt = modified;
    } else if (app && entry.title && entry.title !== app.title) {
      // Renamed on the phone: the index has the title now. Renames here are
      // written as they're made, so this one came from there.
      changes.updated.push({ ...app, title: entry.title });
    }
  }

  const unknown = new Set([...files].filter((f) => !claimed.has(f)));

  // Every file gone at once is more likely a folder that hasn't loaded than one
  // that was emptied, so scripts are only let go of while the folder still
  // lists some file. A script's own file renamed counts.
  if (missing.length && files.size) {
    for (const id of missing) {
      const entry = index[id];
      if (!entry) continue;
      // A file renamed or moved outside the app still holds the same text.
      const content = appNotes.get(id)?.content;
      let renamed = null;
      if (content != null) {
        for (const file of [...unknown].sort()) {
          if ((await readContent(folder, file)) === content) {
            renamed = file;
            break;
          }
        }
      }
      if (renamed) {
        unknown.delete(renamed);
        const app = appNotes.get(id);
        if (!app) continue;
        const title = renamed.replace(/\.[^.]+$/, '').trim() || 'Imported Script';
        changes.updated.push({ ...app, title });
        index[id] = { ...entry, file: renamed, title, noteUpdatedAt: ms(app.updatedAt), fileModifiedAt: meta.get(renamed)?.modified ?? null };
      } else {
        delete index[id];
        if (appNotes.has(id)) changes.deleted.push(id);
      }
    }
  }

  // Files added outside the app become new scripts.
  for (const file of [...unknown].sort()) {
    if (tooLarge.has(file)) continue;
    const content = await readContent(folder, file);
    if (content == null) continue;
    const info = meta.get(file);
    const modified = info?.modified ?? Date.now();
    const created = info?.created ?? modified;
    const mode = /\[separator\]/i.test(content) ? 'cards' : 'teleprompter';
    const id = (crypto.randomUUID?.() || `${Date.now()}`).toUpperCase();
    const title = file.replace(/\.[^.]+$/, '').trim() || 'Imported Script';
    changes.updated.push({ id, title, content, mode, collection: null, createdAt: iso(created), updatedAt: iso(modified) });
    index[id] = { file, title, mode, createdAt: created, noteUpdatedAt: modified, fileModifiedAt: info?.modified ?? null };
  }

  // Scripts the folder doesn't have yet, as when it's first chosen.
  const deleted = new Set(changes.deleted);
  for (const note of notes) {
    if (!index[note.id] && !deleted.has(note.id)) await writeNote(folder, note, index);
  }

  if (!sameIndex(index, originalIndex)) await writeIndex(folder, index);

  await arrangeIn(folder, listing, appNotes, collections, index, deleted, changes);

  // Every script as it stands after the sync, for the images they place.
  const updated = new Map(changes.updated.map((n) => [n.id, n]));
  const contents = [
    ...notes.filter((n) => !deleted.has(n.id)).map((n) => updated.get(n.id)?.content ?? n.content),
    ...changes.updated.filter((n) => !appNotes.has(n.id)).map((n) => n.content),
  ];
  // A file that couldn't be read yet may place images nothing here does, so
  // none are deleted until every file has been.
  const readAll = pending.size === 0 && changes.tooLarge.length === 0 && (files.size > 0 || !Object.keys(originalIndex).length);
  await syncImages(folder, contents, readAll);
  return changes;
}

/**
 * Bring which scripts are in each collection in step with the folder's own
 * list. If the list was changed outside the app since it was last in step, as
 * on the phone, it wins; otherwise the app does.
 */
async function arrangeIn(folder, listing, appNotes, collections, index, deleted, changes) {
  const fresh = (await T.folder.list(folder)) || listing;
  const stored = await readLibrary(folder, fresh);
  const changedOutside = stored ? !sameDate(stored.modified, local.libraryModified) : false;
  const listed = stored?.library;
  const ids = new Set(
    [...Object.keys(index), ...appNotes.keys(), ...changes.updated.map((n) => n.id)].filter(
      (id) => !deleted.has(id) && !local.pending.has(id)
    )
  );

  let names = [...collections];
  if (changedOutside && listed) {
    // The list's collections, but for those deleted here since it was last in
    // step, and those made here since.
    const synced = local.syncedCollections || [];
    names = listed.collections.map((c) => c.name).filter((n) => !containsCollection(synced, n) || containsCollection(collections, n));
    for (const name of collections) {
      if (!containsCollection(synced, name) && !containsCollection(names, name)) names.push(name);
    }
    // One a script here is in that the list doesn't place.
    for (const id of [...ids].sort()) {
      if (placed(listed, id) !== undefined) continue;
      const extra = appNotes.get(id)?.collection;
      if (extra && !containsCollection(names, extra)) names.push(extra);
    }
  }

  const collectionOf = (id) => {
    let name;
    const where = listed ? placed(listed, id) : undefined;
    if (changedOutside && where !== undefined) name = where;
    else if (appNotes.has(id)) name = appNotes.get(id).collection;
    else name = where ?? null;
    // Named as the list names it; in one it's in no longer, in none.
    return name ? names.find((n) => sameName(n, name)) ?? null : null;
  };

  const library = makeLibrary(ids, names, collectionOf);
  for (const id of ids) {
    const name = placed(library, id) ?? null;
    const i = changes.updated.findIndex((n) => n.id === id);
    if (i >= 0) changes.updated[i].collection = name;
    else if (appNotes.has(id) && appNotes.get(id).collection !== name) changes.updated.push({ ...appNotes.get(id), collection: name });
  }
  changes.collections = names;

  if (!listed || !sameLibrary(library, listed)) await writeLibrary(folder, library);
  else if (stored) await setLibraryState(stored.modified, names);
}

/**
 * Bring in the images the scripts place that this computer doesn't have, and
 * delete the folder's copies of any no script places any more.
 */
async function syncImages(folder, contents, deletingUnplaced) {
  const names = new Set();
  contents.forEach((content) => imageNames(content).forEach((name) => names.add(name)));
  const have = new Set((await imagesList()).map((image) => image.name));
  const there = await T.folder.imagesList(folder);

  for (const name of names) {
    if (have.has(name)) continue;
    const bytes = await T.folder.imageRead(folder, name);
    if (bytes) await keepImage(name, bytes);
    // Not downloaded from iCloud Drive yet; it's taken in once it is.
    else if (there.includes(`.${name}.icloud`)) void T.folder.download(folder, `${IMAGES}/.${name}.icloud`);
  }

  // Images the scripts place that only this computer has go to the folder.
  await writeImagesFor(folder, names, new Set(there));

  if (!deletingUnplaced) return;
  for (const file of there) {
    // A file in iCloud Drive that isn't downloaded is ".name.icloud".
    const name = file.startsWith('.') && file.endsWith('.icloud') ? file.slice(1, -'.icloud'.length) : file;
    if (!names.has(name)) await T.folder.imageRemove(folder, file);
  }
}

async function writeImagesFor(folder, names, there) {
  for (const name of names) {
    if (there.has(name) || there.has(`.${name}.icloud`)) continue;
    const bytes = await imageBytes(name);
    if (bytes && (await T.folder.imageWrite(folder, name, bytes))) there.add(name);
  }
}
