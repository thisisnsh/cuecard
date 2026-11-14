/**
 * The sheets the editor opens: the timer for the mode being written in, a
 * saved script's versions, and help.
 */

import { icon } from './icons.js';
import * as notes from './notes.js';
import { CUE_COLORS, colorName, formatDuration } from './parser.js';
import {
  COUNTDOWN_RANGE,
  DEFAULT_TIMER_STYLE,
  modeKey,
  onSettingsChange,
  setSetting,
  settings,
  timerDuration,
  timerStyle,
} from './settings.js';
import { track, trackClick, trackScreen } from './tauri.js';
import * as ui from './ui.js';

const esc = ui.escapeHtml;

// =============================================================================
// A WHEEL, AS NEAR AS A WINDOW GETS TO ONE
// =============================================================================

/** Scroll it, click it, or type. `range()` can change as other wheels do. */
export function createWheel(el, { range, get, set, pad = 2, label }) {
  let typed = '';
  let typedAt = 0;
  let wheelDelta = 0;

  el.classList.add('wheel');
  el.tabIndex = 0;
  el.setAttribute('role', 'spinbutton');
  if (label) el.setAttribute('aria-label', label);

  function render() {
    const [min, max] = range();
    const value = Math.min(Math.max(get(), min), max);
    const span = max - min + 1;
    const at = (n) => String(((((n - min) % span) + span) % span) + min).padStart(pad, '0');
    // With only two or three to pick from, wrapping would show the same number
    // above and below, so the ends stop instead.
    const wraps = span > 3;
    const above = wraps || value > min ? at(value - 1) : '';
    const below = wraps || value < max ? at(value + 1) : '';
    el.innerHTML = `
      <div class="wheel-row">${span > 1 ? above : ''}</div>
      <div class="wheel-row is-current">${at(value)}</div>
      <div class="wheel-row">${span > 1 ? below : ''}</div>
      <div class="wheel-band"></div>`;
    el.setAttribute('aria-valuenow', String(value));
    el.setAttribute('aria-valuemin', String(min));
    el.setAttribute('aria-valuemax', String(max));
  }

  // Wraps, because the faded rows above and below say it will.
  const step = (by) => {
    const [min, max] = range();
    const span = max - min + 1;
    set(((((get() - min + by) % span) + span) % span) + min);
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
      const [min, max] = range();
      set(Math.min(Math.max(Number(typed), min), max));
      render();
    }
  });

  render();
  return { render };
}

// =============================================================================
// TIMER
// =============================================================================

/**
 * The timer for the mode being written in: how long it runs, when it warns,
 * the countdown before it, and the colours it turns.
 */
export function openTimerSheet(mode) {
  const isTeleprompter = mode === 'teleprompter';
  const key = (name) => modeKey(mode, name);
  const style = () => timerStyle(mode);
  const duration = () => timerDuration(mode);
  const setStyle = (changes) => setSetting(key('timerStyle'), { ...style(), ...changes });

  trackScreen('timer');
  const sheet = ui.presentSheet({
    title: isTeleprompter ? 'Teleprompter Timer' : 'Cards Timer',
    className: 'is-compact',
    onClose: () => {
      unsubscribe();
      trackClick('timer_done', 'timer');
    },
  });

  sheet.body.innerHTML = `
    <div class="sheet-page">
      <section class="group">
        <div class="cells"><div class="timer-preview" data-role="preview"></div></div>
      </section>

      <section class="group">
        <div class="cells">
          <div class="cell timer-row">
            <span class="cell-title">Duration</span>
            <span class="time-wheels">
              <span data-wheel="minutes"></span><span class="wheel-unit">min</span>
              <span data-wheel="seconds"></span><span class="wheel-unit">sec</span>
            </span>
          </div>
          <div class="cell timer-row" data-row="warning">
            <span class="cell-title">Warn in Last</span>
            <span class="time-wheels">
              <span data-wheel="warn-minutes"></span><span class="wheel-unit">min</span>
              <span data-wheel="warn-seconds"></span><span class="wheel-unit">sec</span>
            </span>
          </div>
          ${isTeleprompter ? `
          <div class="cell timer-row">
            <span class="cell-title">Countdown</span>
            <span class="time-wheels">
              <span data-wheel="countdown"></span><span class="wheel-unit">sec</span>
            </span>
          </div>` : ''}
        </div>
        <p class="group-footer" data-role="footer"></p>
      </section>

      <section class="group">
        <h3 class="group-title">Timer Colors</h3>
        <div class="cells" data-role="colors"></div>
      </section>
    </div>`;

  const $ = (selector) => sheet.body.querySelector(selector);

  /** The warning is always short of the duration. */
  const latestWarning = () => Math.max(duration() - 1, 0);
  const clampWarning = () => {
    if (style().warningSeconds > latestWarning()) void setStyle({ warningSeconds: latestWarning() });
  };

  const wheels = [
    createWheel($('[data-wheel="minutes"]'), {
      label: 'Duration minutes',
      range: () => [0, 59],
      get: () => settings[key('timerMinutes')],
      set: (v) => {
        void setSetting(key('timerMinutes'), v);
        clampWarning();
      },
    }),
    createWheel($('[data-wheel="seconds"]'), {
      label: 'Duration seconds',
      range: () => [0, 59],
      get: () => settings[key('timerSeconds')],
      set: (v) => {
        void setSetting(key('timerSeconds'), v);
        clampWarning();
      },
    }),
    createWheel($('[data-wheel="warn-minutes"]'), {
      label: 'Warn in last minutes',
      range: () => [0, Math.floor(latestWarning() / 60)],
      get: () => Math.floor(style().warningSeconds / 60),
      set: (v) => void setStyle({ warningSeconds: Math.min(v * 60 + (style().warningSeconds % 60), latestWarning()) }),
    }),
    createWheel($('[data-wheel="warn-seconds"]'), {
      label: 'Warn in last seconds',
      range: () => {
        const minutes = Math.floor(style().warningSeconds / 60);
        const latest = latestWarning();
        return minutes === Math.floor(latest / 60) ? [0, latest % 60] : [0, 59];
      },
      get: () => style().warningSeconds % 60,
      set: (v) => void setStyle({ warningSeconds: Math.min(Math.floor(style().warningSeconds / 60) * 60 + v, latestWarning()) }),
    }),
  ];
  if (isTeleprompter) {
    wheels.push(createWheel($('[data-wheel="countdown"]'), {
      label: 'Countdown seconds',
      range: () => COUNTDOWN_RANGE,
      pad: 1,
      get: () => settings.countdownSeconds,
      set: (v) => void setSetting('countdownSeconds', v),
    }));
  }

  function stage(title, seconds, color) {
    return `
      <div class="timer-stage">
        <span class="timer-stage-time" style="color: var(--color-${color})">${formatDuration(seconds)}</span>
        <span class="timer-stage-label">${title}</span>
      </div>`;
  }

  function swatchRow(title, name) {
    const selected = style()[name];
    return `
      <div class="cell">
        <span class="cell-title">${title}</span>
        <div class="swatches is-small" data-color-key="${name}">
          ${CUE_COLORS.map((color) => `
            <button class="swatch${color === selected ? ' is-selected' : ''}" data-color="${color}"
              style="background: var(--color-${color})" aria-label="${title}: ${colorName(color)}" title="${colorName(color)}">
              ${icon('check', 11, 2.6)}
            </button>`).join('')}
        </div>
      </div>`;
  }

  function render() {
    const d = duration();
    const s = style();

    $('[data-role="preview"]').innerHTML = d === 0
      ? stage('Counts Up', 0, s.normalColor)
      : [
          stage('Start', d, s.normalColor),
          s.warningSeconds > 0 ? stage('Warning', s.warningSeconds, s.warningColor) : '',
          stage('Overtime', 0, s.overtimeColor),
        ].join('');

    $('[data-row="warning"]').hidden = d <= 1;

    const footer = [];
    if (d > 0) footer.push('0:00 turns off the timer.');
    if (isTeleprompter) footer.push('Countdown is the time before the script starts scrolling.');
    $('[data-role="footer"]').textContent = footer.join(' ');
    $('[data-role="footer"]').hidden = !footer.length;

    const defaults = { ...DEFAULT_TIMER_STYLE, warningSeconds: s.warningSeconds };
    const isDefault = JSON.stringify(s) === JSON.stringify(defaults);
    $('[data-role="colors"]').innerHTML = [
      isTeleprompter && settings.countdownSeconds > 0 ? swatchRow('Countdown', 'countdownColor') : '',
      swatchRow('Normal', 'normalColor'),
      d > 0 && s.warningSeconds > 0 ? swatchRow('Warning', 'warningColor') : '',
      d > 0 ? swatchRow('Overtime', 'overtimeColor') : '',
      isDefault ? '' : '<button class="cell is-action" data-role="reset-colors"><span class="cell-title is-tinted">Reset Timer Colors</span></button>',
    ].join('');

    wheels.forEach((wheel) => wheel.render());
  }

  sheet.body.addEventListener('click', (event) => {
    const swatch = event.target.closest('.swatch');
    if (swatch) {
      const name = swatch.closest('[data-color-key]').dataset.colorKey;
      trackClick(`timer_color_${name.replace('Color', '')}`, 'timer');
      void setStyle({ [name]: swatch.dataset.color });
      return;
    }
    if (event.target.closest('[data-role="reset-colors"]')) {
      trackClick('reset_timer_colors', 'timer');
      void setStyle({ ...DEFAULT_TIMER_STYLE, warningSeconds: style().warningSeconds });
    }
  });

  const unsubscribe = onSettingsChange(render);
  render();
}

// =============================================================================
// VERSIONS
// =============================================================================

/** Lines added and removed going from `before` to `after`, as runs. */
function lineDiff(before, after) {
  const a = before.split('\n');
  const b = after.split('\n');
  const n = a.length;
  const m = b.length;

  // Too long to compare line by line in good time: show it all as changed.
  if (n * m > 4_000_000) {
    return [...a.map((text) => ({ type: 'removed', text })), ...b.map((text) => ({ type: 'added', text }))];
  }

  const lcs = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
  for (let i = n - 1; i >= 0; i -= 1) {
    for (let j = m - 1; j >= 0; j -= 1) {
      lcs[i][j] = a[i] === b[j] ? lcs[i + 1][j + 1] + 1 : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }

  const lines = [];
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (a[i] === b[j]) {
      lines.push({ type: 'same', text: a[i] });
      i += 1;
      j += 1;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      lines.push({ type: 'removed', text: a[i] });
      i += 1;
    } else {
      lines.push({ type: 'added', text: b[j] });
      j += 1;
    }
  }
  while (i < n) lines.push({ type: 'removed', text: a[i++] });
  while (j < m) lines.push({ type: 'added', text: b[j++] });
  return lines;
}

const changeCount = (lines) => ({
  added: lines.filter((l) => l.type === 'added').length,
  removed: lines.filter((l) => l.type === 'removed').length,
});

/** Unchanged lines kept on show either side of a change. */
const CONTEXT = 2;

function diffHtml(lines) {
  if (!lines.some((l) => l.type !== 'same')) return '<p class="diff-empty">No changes</p>';
  const keep = lines.map((line, index) =>
    line.type !== 'same' ||
    lines.slice(Math.max(index - CONTEXT, 0), index + CONTEXT + 1).some((l) => l.type !== 'same')
  );

  const rows = [];
  let folded = 0;
  const flush = () => {
    if (folded) rows.push(`<div class="diff-fold">⋯ ${folded} unchanged line${folded === 1 ? '' : 's'}</div>`);
    folded = 0;
  };
  lines.forEach((line, index) => {
    if (!keep[index]) {
      folded += 1;
      return;
    }
    flush();
    const mark = line.type === 'added' ? '+' : line.type === 'removed' ? '−' : '';
    rows.push(`<div class="diff-line is-${line.type}"><span class="diff-mark">${mark}</span><span class="diff-text">${esc(line.text) || '&nbsp;'}</span></div>`);
  });
  flush();
  return rows.join('');
}

const versionDate = (iso) =>
  new Date(iso).toLocaleString(undefined, { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' });

/**
 * Every version of a saved note, newest first, to compare and restore.
 * @param onRestored Called once a version has been brought back.
 */
export function openVersionsSheet(noteId, { onRestored } = {}) {
  trackScreen('version_history');
  const sheet = ui.presentSheet({ title: 'Version History' });
  let comparison = 'previous';

  const note = () => notes.noteById(noteId);
  /** The versions on file, or the note as it is if it has none yet. */
  const versions = () => {
    const list = notes.versionsOf(noteId);
    const current = note();
    if (list.length || !current) return list;
    return [{ number: 1, content: current.content, createdAt: current.updatedAt, restoredFrom: null }];
  };
  /** The editor's text for this note, if it's open in one. */
  const editorText = () => {
    const current = note();
    if (!current) return null;
    const draft = notes.draft(current.mode);
    return draft.noteId === noteId ? draft.text : null;
  };

  function showList() {
    sheet.setTitle('Version History');
    sheet.setBack(null);
    const list = versions();
    const current = note();
    if (!current) {
      sheet.close();
      return;
    }

    const rows = [...list].reverse().map((version) => {
      const index = list.indexOf(version);
      const before = index > 0 ? list[index - 1].content : '';
      const change = changeCount(lineDiff(before, version.content));
      const isCurrent = index === list.length - 1 && version.content === current.content;
      return `
        <button class="cell is-action version-row" data-number="${version.number}">
          <span class="cell-label">
            <span class="cell-title">Version ${version.number}${isCurrent ? ' <span class="pill-tag">Current</span>' : ''}</span>
            <span class="cell-sub">${esc(versionDate(version.createdAt))}${version.restoredFrom ? ` · Restored from Version ${version.restoredFrom}` : ''}</span>
          </span>
          <span class="version-change">
            ${change.added ? `<span class="is-added">+${change.added}</span>` : ''}
            ${change.removed ? `<span class="is-removed">−${change.removed}</span>` : ''}
          </span>
          <span class="cell-accessory">${icon('chevronRight', 14)}</span>
        </button>`;
    });

    sheet.body.innerHTML = `
      <div class="sheet-page">
        <section class="group">
          <h3 class="group-title">${esc(current.title)}</h3>
          <div class="cells">${rows.join('')}</div>
          <p class="group-footer">Every save is a new version. Restoring one adds it as the newest, so nothing is lost.</p>
        </section>
      </div>`;
    sheet.body.scrollTo(0, 0);

    sheet.body.querySelectorAll('.version-row').forEach((row) => {
      row.addEventListener('click', () => {
        trackClick('version_open', 'version_history');
        showVersion(Number(row.dataset.number));
      });
    });
  }

  function showVersion(number) {
    const list = versions();
    const index = list.findIndex((v) => v.number === number);
    const version = list[index];
    const current = note();
    if (!version || !current) return showList();

    const previous = index > 0 ? list[index - 1] : null;
    const draftText = editorText();
    const canCompareEditor = draftText !== null;
    if (comparison === 'editor' && !canCompareEditor) comparison = 'previous';

    const isNewest = index === list.length - 1 && version.content === current.content;
    const lines = comparison === 'editor'
      ? lineDiff(version.content, draftText)
      : lineDiff(previous ? previous.content : '', version.content);

    sheet.setTitle(`Version ${number}`);
    sheet.setBack('Versions', showList);
    sheet.body.innerHTML = `
      <div class="sheet-page">
        <section class="group">
          <div class="version-head">
            <span class="cell-sub">${esc(versionDate(version.createdAt))}${version.restoredFrom ? ` · Restored from Version ${version.restoredFrom}` : ''}</span>
            <div class="segmented" role="group" aria-label="Compare with">
              <button class="segment${comparison === 'previous' ? ' is-selected' : ''}" data-compare="previous">${previous ? `Version ${previous.number}` : 'Nothing Before'}</button>
              ${canCompareEditor ? `<button class="segment${comparison === 'editor' ? ' is-selected' : ''}" data-compare="editor">Current Edit</button>` : ''}
            </div>
          </div>
          <h3 class="group-title">Compare Changes</h3>
          <div class="cells diff">${diffHtml(lines)}</div>
          <p class="group-footer">${comparison === 'editor'
            ? `What changes from Version ${number} to what's in the editor now.`
            : previous ? `What Version ${number} changed from Version ${previous.number}.` : `Version ${number} is the first.`}</p>
        </section>
        ${isNewest ? '' : `
        <section class="group">
          <div class="cells">
            <button class="cell is-action" data-role="restore"><span class="cell-title is-tinted">Restore This Version</span></button>
          </div>
        </section>`}
      </div>`;
    sheet.body.scrollTo(0, 0);

    sheet.body.querySelectorAll('[data-compare]').forEach((button) => {
      button.addEventListener('click', () => {
        comparison = button.dataset.compare;
        trackClick(`version_compare_${comparison}`, 'version_history');
        showVersion(number);
      });
    });

    sheet.body.querySelector('[data-role="restore"]')?.addEventListener('click', async () => {
      trackClick('version_restore', 'version_history');
      const draft = notes.draft(current.mode);
      const hasUnsaved = draft.noteId === noteId && draft.text !== current.content;
      if (hasUnsaved) {
        const sure = await ui.confirmAction({
          title: `Restore Version ${number}?`,
          message: "The editor has changes that aren't saved. Restoring replaces them with this version.",
          confirmLabel: `Restore Version ${number}`,
          destructive: true,
        });
        if (!sure) return;
      }
      if (await notes.restoreVersion(noteId, number)) {
        track('version_restored', { version: number });
        ui.showToast(`Restored Version ${number}`);
        onRestored?.();
        showList();
      } else {
        await ui.showError("This version couldn't be restored. Try again.");
      }
    });
  }

  showList();
}

// =============================================================================
// HELP
// =============================================================================

const topic = (title, detail) => ({ title, detail });

/** Help, as the phone app has it, for what this app does. */
export function helpSections({ isMac }) {
  const mod = isMac ? '⌘' : 'Ctrl+';
  const global = isMac ? '⌃⌥' : 'Ctrl+Alt+';
  return [
    {
      id: 'writing',
      title: 'Writing',
      summary: 'Modes, cues, formatting, anchors and cards',
      icon: 'compose',
      topics: [
        topic('Pick a Mode', 'At the top of your library, choose Teleprompter or Cards, then click + to start one. Teleprompter scrolls your whole script. Cards shows it one card at a time.'),
        topic('Add Cues', 'Cues are reminders like [pause], shown in color and not read out. Type [ or click the cue button at the bottom left of the editor.'),
        topic('Bold and Italic', `Select words and click B or I at the bottom left, or press ${mod}B or ${mod}I. Or type *bold* or _italic_.`),
        topic('Add Anchors', 'Anchors mark spots in your script, like [anchor]. Type one or click the anchor button at the bottom left. In the teleprompter, the buttons at the far left and right jump to the anchor before or after.'),
        topic('Add Images', 'Click the photo button at the bottom left of the editor, or paste or drag a picture in. It goes in as [image …] on a line of its own, with the picture beside it, and shows in full in the teleprompter and on cards.'),
        topic('Add Cards', `Each box in the editor is one card. Click Create New Card, or press ${mod}Return in a card, to add another. Backspace in an empty card removes it.`),
        topic('Keep Cards Short', 'Each card shows how many characters it has. Past 280 the count turns red, as the card is getting long to read at a glance.'),
      ],
    },
    {
      id: 'notes',
      title: 'Library & Saving',
      summary: 'Collections, saving, import, versions and sharing',
      icon: 'library',
      topics: [
        topic('Open a Script', 'Your library is in the sidebar, with every script and deck you saved. Click one to write in it. Switch between Teleprompter and Cards at the top.'),
        topic('Save Your Work', `When there are changes to save, the title bar says Unsaved and Save appears at the top. Click it, or press ${mod}S. To keep your changes as a separate script, open ••• and choose Save as New. A new script you haven't saved shows in the library as a draft.`),
        topic('Rename, Duplicate or Delete', 'In your library, right-click a script, or hover it and click •••. In the editor, click the title to rename it.'),
        topic('Organize in Collections', 'In your library, click + after your collections. Click a collection to show only its scripts, or All to show every one. To add a script to one, right-click it and choose Add to Collection. A script you start or import goes in the collection you are in. Right-click a collection to rename or delete it. Choose Sort By in the library\'s ••• menu to change the order.'),
        topic('Search Your Library', `Type in the search field at the top of the library, or press ${mod}F. It looks through every title and script in the mode you are in.`),
        topic('Import a Text File', "In your library's ••• menu, choose Import File to add a text file as a script. A file with [separator]s in it comes in as a deck."),
        topic('Go Back to an Older Version', 'Every save is a new version. Click the version number in the title bar to compare changes and restore one. It is also under ••• at the top, in Version History.'),
        topic('Share a Script', 'Right-click a script and choose Export to File or Copy Text. It goes as text, cues included.'),
        topic('Keep Scripts in a Folder', "In your library's ••• menu, choose Choose Storage Folder. Each saved script is kept there as a text file, with its images and the collections it's in. Edit a file in another app and the change comes back into CueCard."),
        topic('Use With the Phone App', 'Pick a folder in iCloud Drive here, and the same folder in the phone app (in its library, ••• › Choose Storage Folder). Scripts saved on either one show up on the other, with their collections and images.'),
        topic('Stop Using the Folder', "In your library's ••• menu, choose Stop Using Storage Folder. Your scripts stay in CueCard, and their files stay in the folder for the phone app."),
        topic('Your Privacy', "There's no account, and CueCard doesn't upload your scripts. They're kept on this computer, and in the storage folder if you choose one."),
      ],
    },
    {
      id: 'settings',
      title: 'Settings & Timer',
      summary: 'Text size, colors and the timer',
      icon: 'gear',
      topics: [
        topic('Change Text Size and Colors', `Click the gear, or press ${mod},. Text sizes and cue color are under Teleprompter and Cards, and each keeps its own. Show Advanced Settings to type in any size.`),
        topic('Set a Timer', 'Click the timer beside Play at the bottom of the editor to set how long you have, when it warns you, and the colors it turns. Teleprompter and Cards each keep their own.'),
        topic('Count Down Before Scrolling', "In the teleprompter's timer, set a Countdown to get a few seconds before the script starts scrolling."),
      ],
    },
    {
      id: 'teleprompter',
      title: 'Teleprompter',
      summary: 'Scrolling, anchors, mirroring and the reading line',
      icon: 'teleprompter',
      topics: [
        topic('Play and Pause', 'Click Play or press Space. The buttons fade while the script scrolls so they stay out of the way. Move the pointer to show them again. Press R to start over.'),
        topic('Scroll by Hand', 'Scroll the script to go back or skip ahead, or press ↑ and ↓ to move a line. It keeps scrolling from where you leave it.'),
        topic('Change Speed', 'Scroll Speed in Settings sets how many lines pass each minute.'),
        topic('Jump Between Anchors', 'Press ← and →, or click the buttons at the far left and right, to jump to the anchor before or after. The top and the end of the script count as anchors too.'),
        topic('Keep Your Place', 'The pointer at the side of the script marks the line to read. Drag it up or down to read where it suits your eyes, and the script lines up with it. Turn off Reading Guide Line in Settings to hide it.'),
        topic('Mirror', "Turn on Flip Horizontally or Flip Vertically under Teleprompter in Settings to flip the text for a teleprompter's glass. Both are off by default."),
        topic('Know When Time Is Running Out', 'The timer changes color when you are near the end and again once you are over time. Pick the colors in the timer.'),
      ],
    },
    {
      id: 'cards',
      title: 'Cards',
      summary: 'Turning cards and the timer',
      icon: 'cards',
      topics: [
        topic('Turn Cards', 'Click Next and Back, press → and ←, or swipe sideways with two fingers on the trackpad. The dots at the top show which card you are on.'),
        topic('Count Up Without a Timer', 'The time at the top counts down your cards timer. With no timer set, it counts up from when you opened the deck.'),
      ],
    },
    {
      id: 'slides',
      title: 'Google Slides',
      summary: 'The notes of the slide you are on',
      icon: 'slides',
      topics: [
        topic('Read Your Speaker Notes', 'Install the CueCard browser extension and connect Google Slides in the sidebar. As you present, the notes for the slide you are on show up here, and the teleprompter moves on with each slide.'),
        topic('Refresh the Notes', 'Edited the notes while presenting? Click the refresh button above them to read them again.'),
      ],
    },
    {
      id: 'window',
      title: 'The Window',
      summary: 'Staying invisible, opacity and shortcuts',
      icon: 'eyeOff',
      topics: [
        topic('Stay Out of Screen Shares', 'While Invisible is on in the title bar, CueCard is left out of screen sharing, screenshots and recordings. Everyone else sees what is behind it.'),
        topic('See Through the Window', `Set Opacity in Settings, or press ${global}- and ${global}= from any app.`),
        topic('Control It From Any App', `Press ${global}C to show or hide CueCard, ${global}Space to play or pause, ${global}0 to restart and ${global}arrow keys to move the window, while you are in another app.`),
      ],
    },
  ];
}

/** The topics with any of the words searched for, best match first. */
function searchHelp(sections, query) {
  const words = [...new Set(query.toLowerCase().split(/\s+/).filter(Boolean))];
  const fold = (s) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
  const results = [];
  let order = 0;
  for (const section of sections) {
    for (const t of section.topics) {
      const haystack = fold(`${t.title} ${t.detail}`);
      const count = words.filter((w) => haystack.includes(fold(w))).length;
      if (count) results.push({ section, topic: t, count, order });
      order += 1;
    }
  }
  return results.sort((a, b) => b.count - a.count || a.order - b.order);
}

export function openHelpSheet({ isMac, page = 'home', onWhatsNew = null, onSupport, onFeature } = {}) {
  track('screen_view', { screen_name: 'help', page });
  const sections = helpSections({ isMac });
  const sheet = ui.presentSheet({ title: 'Help' });
  let query = '';

  function topicRow(t, sectionTitle = '') {
    return `
      <details class="help-topic">
        <summary class="cell is-action">
          <span class="cell-label">
            <span class="cell-title">${esc(t.title)}</span>
            ${sectionTitle ? `<span class="cell-sub">${esc(sectionTitle)}</span>` : ''}
          </span>
          <span class="cell-accessory">${icon('chevronDown', 14)}</span>
        </summary>
        <p class="help-detail">${esc(t.detail)}</p>
      </details>`;
  }

  function showFront() {
    sheet.setTitle('Help');
    sheet.setBack(null);
    sheet.body.innerHTML = `
      <div class="sheet-page">
        <label class="search-field is-sheet">
          ${icon('search', 14)}
          <input type="search" placeholder="Search Help" value="${ui.escapeAttribute(query)}" spellcheck="false">
        </label>
        <div data-role="content"></div>
      </div>`;
    const input = sheet.body.querySelector('input');
    input.addEventListener('input', () => {
      query = input.value;
      renderContent();
    });
    renderContent();
    requestAnimationFrame(() => input.focus());
  }

  function renderContent() {
    const content = sheet.body.querySelector('[data-role="content"]');
    const trimmed = query.trim();
    if (trimmed) {
      const results = searchHelp(sections, trimmed);
      content.innerHTML = results.length
        ? `<section class="group"><div class="cells">${results.map((r) => topicRow(r.topic, r.section.title)).join('')}</div></section>`
        : `<div class="help-empty"><h3 class="empty-title">No Results</h3><p class="empty-text">Nothing in Help matches “${esc(trimmed)}”.</p></div>`;
      if (results.length === 1) content.querySelector('details').open = true;
      return;
    }

    content.innerHTML = `
      <section class="group">
        <div class="cells">
          ${sections.map((section) => `
            <button class="cell is-action help-section" data-section="${section.id}">
              <span class="help-section-icon">${icon(section.icon, 16)}</span>
              <span class="cell-label">
                <span class="cell-title">${esc(section.title)}</span>
                <span class="cell-sub">${esc(section.summary)}</span>
              </span>
              <span class="cell-accessory">${icon('chevronRight', 14)}</span>
            </button>`).join('')}
        </div>
      </section>
      <section class="group">
        <div class="cells">
          <button class="cell is-action" data-role="support"><span class="cell-title">Report a Problem</span><span class="cell-accessory">${icon('arrowUpRight', 13)}</span></button>
          <button class="cell is-action" data-role="feature"><span class="cell-title">Ask for a Feature</span><span class="cell-accessory">${icon('arrowUpRight', 13)}</span></button>
          ${onWhatsNew ? `<button class="cell is-action" data-role="whats-new"><span class="cell-title">What's New</span><span class="cell-accessory">${icon('chevronRight', 14)}</span></button>` : ''}
        </div>
      </section>`;

    content.querySelectorAll('.help-section').forEach((button) => {
      button.addEventListener('click', () => {
        trackClick(`help_section_${button.dataset.section}`, 'help');
        showSection(sections.find((s) => s.id === button.dataset.section));
      });
    });
    content.querySelector('[data-role="support"]')?.addEventListener('click', () => {
      trackClick('help_report_issue', 'help');
      onSupport?.();
    });
    content.querySelector('[data-role="feature"]')?.addEventListener('click', () => {
      trackClick('help_request_feature', 'help');
      onFeature?.();
    });
    content.querySelector('[data-role="whats-new"]')?.addEventListener('click', () => onWhatsNew?.());
  }

  function showSection(section) {
    sheet.setTitle(section.title);
    sheet.setBack('Help', showFront);
    sheet.body.innerHTML = `
      <div class="sheet-page">
        <section class="group">
          <div class="cells">${section.topics.map((t) => topicRow(t)).join('')}</div>
        </section>
      </div>`;
    sheet.body.scrollTo(0, 0);
  }

  sheet.body.addEventListener('toggle', (event) => {
    if (event.target.open) trackClick('help_topic', 'help', { topic: event.target.querySelector('.cell-title')?.textContent });
  }, true);

  showFront();
}
