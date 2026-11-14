/**
 * The library, in the sidebar: every script or deck of the mode chosen at the
 * top, filed in collections, searched, sorted, and in sections by when they
 * were edited — as the phone app's library lists them.
 */

import { icon } from './icons.js';
import * as notes from './notes.js';
import { cards as cardsOf } from './parser.js';
import { getStored, setStored, trackClick } from './tauri.js';
import * as ui from './ui.js';

const esc = ui.escapeHtml;

export const SORTS = [
  { id: 'edited', label: 'Date Edited' },
  { id: 'created', label: 'Date Created' },
  { id: 'title', label: 'Title' },
];

/** Each collection's colour, by the order the collections were made in, so it
 *  stays the same as more are made. */
const COLLECTION_COLORS = ['blue', 'purple', 'pink', 'red', 'green', 'yellow'];
const collectionColor = (name) => {
  const index = notes.state.collections.findIndex((c) => c.localeCompare(name, undefined, { sensitivity: 'accent' }) === 0);
  return COLLECTION_COLORS[Math.max(index, 0) % COLLECTION_COLORS.length];
};

// =============================================================================
// DATES
// =============================================================================

const startOfDay = (date) => new Date(date.getFullYear(), date.getMonth(), date.getDate());

function dateGroup(iso, now = new Date()) {
  const days = Math.round((startOfDay(now) - startOfDay(new Date(iso))) / 86_400_000);
  if (days <= 0) return 'today';
  if (days === 1) return 'yesterday';
  if (days < 7) return 'week';
  if (days < 30) return 'month';
  return 'earlier';
}

const GROUP_TITLES = {
  today: 'Today',
  yesterday: 'Yesterday',
  week: 'Previous 7 Days',
  month: 'Previous 30 Days',
  earlier: 'Earlier',
};

/** When, as the row in that section says it: a time today, a weekday this
 *  week, a date before that. Yesterday's section says it all. */
function rowDate(iso, group) {
  const date = new Date(iso);
  switch (group) {
    case 'today':
      return date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
    case 'yesterday':
      return '';
    case 'week':
      return date.toLocaleDateString(undefined, { weekday: 'long' });
    default:
      return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  }
}

const cardCount = (content) => {
  const count = cardsOf(content).length;
  return count === 1 ? '1 Card' : `${count} Cards`;
};

// =============================================================================
// THE LIBRARY
// =============================================================================

export function createLibrary(el, handlers) {
  const view = {
    sort: 'edited',
    /** The collection chosen, or empty for All. */
    collection: '',
    query: '',
  };

  async function load() {
    const sort = await getStored('library_sort');
    if (SORTS.some((s) => s.id === sort)) view.sort = sort;
    view.collection = (await getStored('library_collection')) || '';
  }

  /** The collection shown, or null for All. One deleted since it was chosen is All. */
  const collection = () => (view.collection && notes.hasCollection(view.collection) ? view.collection : null);

  const trimmedQuery = () => view.query.trim().toLowerCase();

  const matches = (title, content) => {
    const query = trimmedQuery();
    if (!query) return true;
    return title.toLowerCase().includes(query) || notes.preview(content).toLowerCase().includes(query);
  };

  /** The saved notes shown: the chosen collection's, or every one under All,
   *  of the chosen mode, matching the search, in the chosen order. */
  function shownNotes() {
    const mode = notes.state.mode;
    const chosen = collection();
    const shown = notes.state.saved.filter(
      (note) => note.mode === mode && (!chosen || note.collection === chosen) && matches(note.title, note.content)
    );
    if (view.sort === 'title') return shown.sort((a, b) => a.title.localeCompare(b.title, undefined, { numeric: true }));
    const key = view.sort === 'created' ? 'createdAt' : 'updatedAt';
    return shown.sort((a, b) => (b[key] || '').localeCompare(a[key] || ''));
  }

  /** A new script of the chosen mode that isn't saved yet, if there's one. */
  function showsDraft() {
    const draft = notes.draft();
    const chosen = collection();
    return !draft.noteId && notes.hasScript() && (!chosen || draft.collection === chosen) && matches('', draft.text);
  }

  const kindName = () => (notes.state.mode === 'cards' ? 'Decks' : 'Scripts');

  // ---------------------------------------------------------------------------

  function render({ source, selectedId }) {
    renderModeSwitch();
    el.sectionTitle.textContent = kindName();
    el.search.placeholder = `Search ${kindName()}`;
    renderChips();
    renderList({ source, selectedId });
    renderFooter();
  }

  function renderModeSwitch() {
    el.modeSwitch.querySelectorAll('.segment').forEach((segment) => {
      segment.classList.toggle('is-selected', segment.dataset.value === notes.state.mode);
      segment.setAttribute('aria-pressed', String(segment.dataset.value === notes.state.mode));
    });
  }

  function renderChips() {
    const mode = notes.state.mode;
    const ofMode = notes.state.saved.filter((note) => note.mode === mode);
    const chosen = collection();
    const chips = [
      chip('', 'All', ofMode.length, !chosen),
      ...notes.collectionsSorted().map((name) =>
        chip(name, name, ofMode.filter((note) => note.collection === name).length, chosen === name)
      ),
      `<button class="chip is-add" data-role="new-collection" aria-label="New Collection" title="New Collection">${icon('plus', 13)}</button>`,
    ];
    el.chips.innerHTML = chips.join('');

    function chip(value, title, count, selected) {
      const dot = value ? `<span class="chip-dot" style="background: var(--color-${collectionColor(value)})"></span>` : '';
      return `
        <button class="chip${selected ? ' is-selected' : ''}" data-collection="${ui.escapeAttribute(value)}"
          aria-pressed="${selected}" aria-label="${ui.escapeAttribute(title)}, ${count}">
          ${dot}<span class="chip-title">${esc(title)}</span><span class="chip-count">${count}</span>
        </button>`;
    }
  }

  function renderList({ source, selectedId }) {
    const list = shownNotes();
    const rows = [];
    const draftSelected = source === 'script' && !notes.draft().noteId;

    if (showsDraft()) {
      rows.push(rowHtml({
        id: '',
        title: notes.state.mode === 'cards' ? 'New Deck' : 'New Script',
        preview: notes.preview(notes.draft().text),
        detail: notes.state.mode === 'cards' ? cardCount(notes.draft().text) : '',
        badge: 'Draft',
        collectionName: notes.draft().collection,
        selected: draftSelected,
      }));
    }

    // Searched, or sorted by title, they're one list. Otherwise in sections by
    // when they were edited or made.
    const grouped = !trimmedQuery() && view.sort !== 'title';
    const now = new Date();
    let lastGroup = null;
    for (const note of list) {
      const stamp = view.sort === 'created' ? note.createdAt : note.updatedAt;
      const group = grouped ? dateGroup(stamp, now) : null;
      if (grouped && group !== lastGroup) {
        rows.push(`<h3 class="library-group">${GROUP_TITLES[group]}</h3>`);
        lastGroup = group;
      }
      const selected = source === 'script' && selectedId === note.id;
      const date = grouped ? rowDate(stamp, group) : rowDate(stamp, 'earlier');
      rows.push(rowHtml({
        id: note.id,
        title: note.title,
        preview: notes.preview(note.content),
        detail: [note.mode === 'cards' ? cardCount(note.content) : '', date].filter(Boolean).join(' · '),
        badge: selected && notes.hasUnsavedChanges() ? 'Unsaved' : null,
        collectionName: collection() ? null : note.collection,
        selected,
      }));
    }

    el.list.innerHTML = rows.join('');

    const empty = !rows.length;
    el.empty.hidden = !empty;
    if (empty) {
      el.empty.innerHTML = trimmedQuery()
        ? `<strong>No Results</strong><span>Nothing in your ${kindName().toLowerCase()} matches “${esc(view.query.trim())}”.</span>`
        : collection()
          ? `<strong>Nothing in “${esc(collection())}”</strong><span>Right-click a ${notes.state.mode === 'cards' ? 'deck' : 'script'} and choose Add to Collection.</span>`
          : `<strong>No ${kindName()} Yet</strong><span>${notes.state.mode === 'cards' ? 'Decks' : 'Scripts'} you save show up here.</span>`;
    }
  }

  function rowHtml({ id, title, preview, detail, badge, collectionName, selected }) {
    const tag = collectionName
      ? `<span class="row-collection"><span class="chip-dot" style="background: var(--color-${collectionColor(collectionName)})"></span>${esc(collectionName)}</span>`
      : '';
    const meta = [detail ? `<span>${esc(detail)}</span>` : '', tag].filter(Boolean).join('');
    return `
      <div class="note-row${selected ? ' is-selected' : ''}" data-id="${ui.escapeAttribute(id)}" role="button" tabindex="0"
        aria-current="${selected}">
        <span class="note-text">
          <span class="note-title">${badge ? '<span class="note-dot" aria-hidden="true"></span>' : ''}${esc(title)}</span>
          ${preview ? `<span class="note-preview">${esc(preview)}</span>` : ''}
          ${meta || badge ? `<span class="note-meta">${badge ? `<span class="note-badge">${esc(badge)}</span>` : ''}${meta}</span>` : ''}
        </span>
        <button class="icon-btn is-small note-more" data-act="more" aria-label="More" title="More">${icon('ellipsisPlain', 15)}</button>
      </div>`;
  }

  /** Where the scripts are kept: on this computer, or in the storage folder too. */
  function renderFooter() {
    const where = handlers.folderInfo?.() || {};
    let line;
    let glyph = 'laptop';
    if (!where.chosen) {
      line = notes.state.saved.length ? 'Your scripts stay on this computer.' : 'Scripts stay on this computer.';
    } else if (!where.reachable) {
      glyph = 'folder';
      line = "The storage folder can't be reached, so your scripts stay only on this computer until it's back.";
    } else {
      glyph = where.icloud ? 'cloud' : 'folder';
      line = where.icloud
        ? `Kept in “${esc(where.name)}” in iCloud Drive.`
        : `Kept in the “${esc(where.name)}” folder.`;
      if (where.tooLarge?.length) line += ` ${where.tooLarge.length === 1 ? 'One file is' : `${where.tooLarge.length} files are`} too large to read.`;
    }
    el.footer.innerHTML = `${icon(glyph, 12)}<span>${where.chosen ? line : esc(line)}</span>`;
    el.footer.title = where.chosen && where.reachable ? 'Choose Storage Folder in the library menu to change it.' : '';
  }

  // ---------------------------------------------------------------------------
  // MENUS
  // ---------------------------------------------------------------------------

  function rowMenu(id, anchor, at) {
    if (!id) {
      ui.showMenu(anchor, [
        { label: 'Keep Writing', icon: 'compose', onSelect: () => handlers.onOpenDraft() },
        { label: 'Add to Collection…', icon: 'collection', onSelect: () => collectionMenu('', anchor, at) },
        { divider: true },
        { label: 'Discard', icon: 'trash', destructive: true, onSelect: () => handlers.onDiscardDraft() },
      ], { at });
      return;
    }
    const note = notes.noteById(id);
    if (!note) return;
    ui.showMenu(anchor, [
      { label: 'Open', icon: 'compose', onSelect: () => handlers.onOpen(id) },
      { label: 'Rename…', icon: 'pencil', onSelect: () => handlers.onRename(id) },
      { label: 'Duplicate', icon: 'duplicate', onSelect: () => handlers.onDuplicate(id) },
      { label: 'Add to Collection…', icon: 'collection', onSelect: () => collectionMenu(id, anchor, at) },
      { label: 'Version History', icon: 'history', disabled: notes.versionCount(id) < 2, onSelect: () => handlers.onVersions(id) },
      { divider: true },
      { label: 'Export to File…', icon: 'docUp', onSelect: () => handlers.onExport(id) },
      { label: 'Copy Text', icon: 'copy', onSelect: () => handlers.onCopy(id) },
      { divider: true },
      { label: 'Delete', icon: 'trash', destructive: true, onSelect: () => handlers.onDelete(id) },
    ], { at });
  }

  /** Which collection a note goes in: one of them, a new one, or none. */
  function collectionMenu(id, anchor, at) {
    const current = id ? notes.noteById(id)?.collection : notes.draft().collection;
    const items = [{ header: 'Add to Collection' }];
    for (const name of notes.collectionsSorted()) {
      items.push({
        label: name,
        checked: name === current,
        onSelect: () => {
          trackClick('add_to_collection_choose', 'library');
          void notes.setNoteCollection(id, name);
        },
      });
    }
    items.push({ divider: true }, {
      label: 'New Collection…',
      icon: 'plus',
      onSelect: async () => {
        trackClick('add_to_collection_new', 'library');
        const name = await handlers.promptCollectionName();
        if (!name) return;
        const made = await notes.createCollection(name);
        if (made) await notes.setNoteCollection(id, made);
      },
    });
    if (current) {
      items.push({
        label: `Remove from “${current}”`,
        icon: 'xmark',
        onSelect: () => {
          trackClick('remove_from_collection', 'library');
          void notes.setNoteCollection(id, null);
        },
      });
    }
    // The first menu has to be gone before the next one opens.
    requestAnimationFrame(() => ui.showMenu(anchor, items, { at }));
  }

  function chipMenu(name, anchor, at) {
    ui.showMenu(anchor, [
      { label: 'Rename…', icon: 'pencil', onSelect: () => handlers.onRenameCollection(name) },
      { divider: true },
      { label: 'Delete Collection', icon: 'trash', destructive: true, onSelect: () => handlers.onDeleteCollection(name) },
    ], { at });
  }

  /** The library's ••• menu. */
  function libraryMenu(anchor) {
    const chosen = collection();
    const items = [
      { header: 'Sort By' },
      ...SORTS.map((sort) => ({
        label: sort.label,
        checked: view.sort === sort.id,
        onSelect: () => {
          trackClick(`library_sort_${sort.id}`, 'library');
          view.sort = sort.id;
          void setStored('library_sort', sort.id);
          handlers.onChange();
        },
      })),
      { divider: true },
      { label: notes.state.mode === 'cards' ? 'New Deck' : 'New Script', icon: 'compose', shortcut: 'mod+n', onSelect: () => handlers.onNew() },
      { label: 'Import File…', icon: 'docDown', onSelect: () => handlers.onImport() },
      { label: 'New Collection…', icon: 'collection', onSelect: () => handlers.onNewCollection() },
    ];
    const where = handlers.folderInfo?.() || {};
    items.push(
      { divider: true },
      { label: where.chosen ? 'Change Storage Folder…' : 'Choose Storage Folder…', icon: 'folder', onSelect: () => handlers.onChooseFolder() }
    );
    if (where.chosen) {
      items.push({ label: 'Stop Using Storage Folder', icon: 'folderMinus', onSelect: () => handlers.onStopFolder() });
    }
    if (chosen) {
      items.push(
        { label: `Rename “${chosen}”…`, icon: 'pencil', onSelect: () => handlers.onRenameCollection(chosen) },
        { label: `Delete “${chosen}”`, icon: 'trash', destructive: true, onSelect: () => handlers.onDeleteCollection(chosen) }
      );
    }
    items.push(
      { divider: true },
      { label: 'Delete All Scripts…', icon: 'trash', destructive: true, disabled: !notes.state.saved.length, onSelect: () => handlers.onDeleteAll() }
    );
    ui.showMenu(anchor, items);
  }

  // ---------------------------------------------------------------------------
  // WIRING
  // ---------------------------------------------------------------------------

  el.modeSwitch.addEventListener('click', (event) => {
    const segment = event.target.closest('.segment');
    if (!segment || segment.dataset.value === notes.state.mode) return;
    trackClick(`library_mode_${segment.dataset.value}`, 'library');
    handlers.onMode(segment.dataset.value);
  });

  el.search.addEventListener('input', () => {
    view.query = el.search.value;
    handlers.onChange();
  });
  el.search.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && el.search.value) {
      event.stopPropagation();
      el.search.value = '';
      view.query = '';
      handlers.onChange();
    }
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      el.list.querySelector('.note-row')?.focus();
    }
  });

  el.chips.addEventListener('click', (event) => {
    if (event.target.closest('[data-role="new-collection"]')) {
      trackClick('new_collection_chip', 'library');
      handlers.onNewCollection();
      return;
    }
    const chip = event.target.closest('[data-collection]');
    if (!chip) return;
    trackClick(chip.dataset.collection ? 'library_collection_choose' : 'library_collection_all', 'library');
    view.collection = chip.dataset.collection;
    void setStored('library_collection', view.collection);
    handlers.onChange();
  });

  el.chips.addEventListener('contextmenu', (event) => {
    const chip = event.target.closest('[data-collection]');
    if (!chip?.dataset.collection) return;
    event.preventDefault();
    chipMenu(chip.dataset.collection, chip, { x: event.clientX, y: event.clientY });
  });

  el.list.addEventListener('click', (event) => {
    const row = event.target.closest('.note-row');
    if (!row) return;
    const { id } = row.dataset;
    const more = event.target.closest('[data-act="more"]');
    if (more) {
      trackClick(id ? 'note_menu' : 'draft_menu', 'library');
      rowMenu(id, more);
      return;
    }
    if (id) handlers.onOpen(id);
    else handlers.onOpenDraft();
  });

  el.list.addEventListener('contextmenu', (event) => {
    const row = event.target.closest('.note-row');
    if (!row) return;
    event.preventDefault();
    rowMenu(row.dataset.id, row, { x: event.clientX, y: event.clientY });
  });

  el.list.addEventListener('keydown', (event) => {
    const row = event.target.closest('.note-row');
    if (!row) return;
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      row.click();
    } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      const rows = [...el.list.querySelectorAll('.note-row')];
      rows[rows.indexOf(row) + (event.key === 'ArrowDown' ? 1 : -1)]?.focus();
    } else if ((event.key === 'Backspace' || event.key === 'Delete') && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      if (row.dataset.id) handlers.onDelete(row.dataset.id);
      else handlers.onDiscardDraft();
    }
  });

  el.more.addEventListener('click', () => {
    trackClick('library_menu', 'library');
    libraryMenu(el.more);
  });
  el.add.addEventListener('click', () => handlers.onNew());

  return {
    load,
    render,
    /** The collection a new or imported script goes in: the one being shown. */
    collection,
    focusSearch() {
      el.search.focus();
      el.search.select();
    },
    /** Show a collection, as when one was just made. */
    showCollection(name) {
      view.collection = name || '';
      void setStored('library_collection', view.collection);
    },
  };
}
