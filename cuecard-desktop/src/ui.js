/**
 * The pieces of interface the phone app gets from the system and a web view
 * does not: alerts, menus, sheets and the little HUD that says "Saved".
 */

import { icon } from './icons.js';
import { segments } from './parser.js';
import { isMac } from './tauri.js';

const host = () => document.getElementById('overlay-host');

// =============================================================================
// KEYBOARD SHORTCUTS
// =============================================================================

/** "mod+shift+s" as the platform writes it: ⇧⌘S, or Ctrl+Shift+S. */
export function formatShortcut(spec) {
  const parts = spec.split('+');
  const key = parts.pop();
  const has = (name) => parts.includes(name);
  const label = { enter: '↩', space: 'Space', up: '↑', down: '↓', left: '←', right: '→', esc: 'Esc', comma: ',' }[key]
    || key.toUpperCase();

  if (isMac) {
    return `${has('ctrl') ? '⌃' : ''}${has('alt') ? '⌥' : ''}${has('shift') ? '⇧' : ''}${has('mod') ? '⌘' : ''}${label}`;
  }
  const names = [has('mod') && 'Ctrl', has('ctrl') && 'Ctrl', has('alt') && 'Alt', has('shift') && 'Shift'].filter(Boolean);
  return [...names, label].join('+');
}

/** Whether a keydown matches a shortcut spec. */
export function matchesShortcut(event, spec) {
  const parts = spec.split('+');
  const key = parts.pop();
  const mod = isMac ? event.metaKey : event.ctrlKey;
  if (parts.includes('mod') !== mod) return false;
  if (parts.includes('shift') !== event.shiftKey) return false;
  if (parts.includes('alt') !== event.altKey) return false;

  const pressed = event.key.toLowerCase();
  const wanted = { enter: 'enter', space: ' ', esc: 'escape', comma: ',' }[key] || key;
  return pressed === wanted;
}

// =============================================================================
// ALERTS
// =============================================================================

/**
 * The alert the phone app raises, drawn here — a window with no decorations
 * should not be asking the system for one.
 *
 * Resolves with the chosen action's id, and the field's text when there is a
 * field. Backing out resolves with `null`.
 */
export function showAlert({ title, message = '', field = null, actions }) {
  return new Promise((resolve) => {
    const layer = document.createElement('div');
    layer.className = 'overlay alert-layer';
    layer.innerHTML = `
      <div class="alert" role="alertdialog" aria-modal="true" aria-label="${escapeAttribute(title)}">
        <div class="alert-body">
          <h2 class="alert-title">${escapeHtml(title)}</h2>
          ${message ? `<p class="alert-message">${escapeHtml(message)}</p>` : ''}
          ${field ? `<input class="alert-field" type="text" value="${escapeAttribute(field.value || '')}"
              placeholder="${escapeAttribute(field.placeholder || '')}" spellcheck="false">` : ''}
        </div>
        <div class="alert-actions${actions.length > 2 ? ' is-stacked' : ''}">
          ${actions.map((action) => `
            <button class="alert-action${action.style ? ` is-${action.style}` : ''}" data-action="${action.id}">
              ${escapeHtml(action.label)}
            </button>`).join('')}
        </div>
      </div>`;

    const input = layer.querySelector('.alert-field');
    const close = (id) => {
      layer.remove();
      document.removeEventListener('keydown', onKey, true);
      resolve(id === null ? null : { action: id, value: input ? input.value.trim() : '' });
    };

    const submit = () => {
      const preferred = actions.find((a) => a.style === 'preferred') || actions.find((a) => a.style !== 'cancel');
      if (preferred?.requiresText && !input?.value.trim()) return;
      close(preferred ? preferred.id : null);
    };

    const onKey = (event) => {
      if (event.key === 'Escape') {
        event.stopPropagation();
        close(null);
      }
      if (event.key === 'Enter' && !event.isComposing) {
        event.stopPropagation();
        submit();
      }
    };

    layer.querySelectorAll('.alert-action').forEach((button) => {
      button.addEventListener('click', () => {
        const action = actions.find((a) => a.id === button.dataset.action);
        if (action?.requiresText && !input?.value.trim()) return;
        close(action.style === 'cancel' ? null : action.id);
      });
    });

    document.addEventListener('keydown', onKey, true);
    host().appendChild(layer);
    requestAnimationFrame(() => layer.classList.add('is-in'));
    input?.focus();
    input?.select();
  });
}

/** Ask for one piece of text. Resolves with the text, or null. */
export async function promptForText({ title, message, value = '', placeholder = '', confirmLabel = 'Save' }) {
  const result = await showAlert({
    title,
    message,
    field: { value, placeholder },
    actions: [
      { id: 'cancel', label: 'Cancel', style: 'cancel' },
      { id: 'confirm', label: confirmLabel, style: 'preferred', requiresText: true },
    ],
  });
  return result ? result.value : null;
}

/** Ask a yes-or-no question. Resolves true only for the confirming answer. */
export async function confirmAction({ title, message, confirmLabel = 'OK', cancelLabel = 'Cancel', destructive = false }) {
  const result = await showAlert({
    title,
    message,
    actions: [
      { id: 'cancel', label: cancelLabel, style: 'cancel' },
      { id: 'confirm', label: confirmLabel, style: destructive ? 'destructive' : 'preferred' },
    ],
  });
  return result?.action === 'confirm';
}

/** Say that something went wrong, the way the phone app says it. */
export const showError = (message, title = 'Something Went Wrong') =>
  showAlert({ title, message, actions: [{ id: 'ok', label: 'OK', style: 'preferred' }] });

// =============================================================================
// MENUS
// =============================================================================

let openMenu = null;

/**
 * A menu hanging off a button. Items are `{ label, icon, shortcut, disabled,
 * destructive, onSelect }`, or `{ divider: true }`.
 */
export function showMenu(anchor, items) {
  closeMenu();

  const layer = document.createElement('div');
  layer.className = 'overlay menu-layer';

  const menu = document.createElement('div');
  menu.className = 'menu';
  menu.setAttribute('role', 'menu');
  menu.innerHTML = items
    .map((item, index) => {
      if (item.divider) return '<div class="menu-divider"></div>';
      return `
        <button class="menu-item${item.destructive ? ' is-destructive' : ''}" role="menuitem"
          data-index="${index}" ${item.disabled ? 'disabled' : ''}>
          <span class="menu-label">${escapeHtml(item.label)}</span>
          ${item.shortcut ? `<span class="menu-shortcut">${escapeHtml(formatShortcut(item.shortcut))}</span>` : ''}
          ${item.icon ? `<span class="menu-icon">${icon(item.icon, 16)}</span>` : ''}
        </button>`;
    })
    .join('');

  layer.appendChild(menu);
  host().appendChild(layer);

  // Hung below the button and aligned to its trailing edge, kept on screen.
  const box = anchor.getBoundingClientRect();
  const width = menu.offsetWidth;
  const left = Math.min(Math.max(box.right - width, 8), window.innerWidth - width - 8);
  const top = Math.min(box.bottom + 6, window.innerHeight - menu.offsetHeight - 8);
  menu.style.left = `${Math.max(left, 8)}px`;
  menu.style.top = `${Math.max(top, 8)}px`;

  const buttons = [...menu.querySelectorAll('.menu-item:not([disabled])')];
  let active = -1;
  const focusItem = (next) => {
    active = (next + buttons.length) % buttons.length;
    buttons[active]?.focus();
  };

  const onKey = (event) => {
    if (event.key === 'Escape') {
      event.stopPropagation();
      closeMenu();
    } else if (event.key === 'ArrowDown') {
      event.preventDefault();
      focusItem(active + 1);
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      focusItem(active - 1);
    }
  };

  menu.querySelectorAll('.menu-item').forEach((button) => {
    button.addEventListener('click', () => {
      const item = items[Number(button.dataset.index)];
      closeMenu();
      item.onSelect?.();
    });
  });

  layer.addEventListener('mousedown', (event) => {
    if (!menu.contains(event.target)) closeMenu();
  });
  document.addEventListener('keydown', onKey, true);

  anchor.setAttribute('aria-expanded', 'true');
  openMenu = () => {
    layer.remove();
    document.removeEventListener('keydown', onKey, true);
    anchor.setAttribute('aria-expanded', 'false');
    openMenu = null;
  };

  requestAnimationFrame(() => menu.classList.add('is-in'));
}

export function closeMenu() {
  openMenu?.();
}

// =============================================================================
// SHEETS
// =============================================================================

let sheetCloser = null;

/** Present a sheet over the window, as the phone app presents one. */
export function openSheet(sheet, { onClose } = {}) {
  const layer = document.createElement('div');
  layer.className = 'overlay sheet-layer';
  const scrim = document.createElement('div');
  scrim.className = 'sheet-scrim';
  layer.appendChild(scrim);

  const home = sheet.parentElement;
  layer.appendChild(sheet);
  sheet.hidden = false;
  host().appendChild(layer);

  const close = () => {
    document.removeEventListener('keydown', onKey, true);
    layer.classList.remove('is-in');
    const done = () => {
      sheet.hidden = true;
      home.appendChild(sheet);
      layer.remove();
    };
    // A transition that never runs must not leave the sheet sitting there.
    sheet.addEventListener('transitionend', done, { once: true });
    setTimeout(done, 420);
    sheetCloser = null;
    onClose?.();
  };

  const onKey = (event) => {
    if (event.key === 'Escape') {
      event.stopPropagation();
      close();
    }
  };

  scrim.addEventListener('click', close);
  document.addEventListener('keydown', onKey, true);
  sheetCloser = close;

  requestAnimationFrame(() => layer.classList.add('is-in'));
  return close;
}

export const closeSheet = () => sheetCloser?.();
export const isSheetOpen = () => Boolean(sheetCloser);

// =============================================================================
// TOAST
// =============================================================================

let toastTimer = null;

/** A brief word that something happened, in the middle of the window. */
export function showToast(text) {
  const toast = document.getElementById('toast');
  if (!toast) return;
  toast.textContent = text;
  toast.hidden = false;
  requestAnimationFrame(() => toast.classList.add('is-in'));

  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toast.classList.remove('is-in');
    setTimeout(() => {
      toast.hidden = true;
    }, 220);
  }, 1300);
}

// =============================================================================
// RENDERING A SCRIPT
// =============================================================================

/**
 * A script as the phone app lays it out: paragraphs, with each cue inline,
 * smaller, and drawn in the one colour from Settings.
 */
export function scriptHtml(text) {
  const normalized = String(text || '').replace(/\r\n?/g, '\n').trim();
  if (!normalized) return '';

  return normalized
    .split(/\n{2,}/)
    .map((paragraph) => {
      const lines = paragraph
        .split('\n')
        .map((line) =>
          segments(line)
            .map((segment) =>
              segment.type === 'cue'
                ? `<span class="cue">${escapeHtml(segment.value)}</span>`
                : escapeHtml(segment.value)
            )
            .join(' ')
        )
        .filter((line) => line.length);
      return lines.length ? `<p>${lines.join('<br>')}</p>` : '';
    })
    .filter(Boolean)
    .join('');
}

// =============================================================================
// ESCAPING
// =============================================================================

export function escapeHtml(text) {
  return String(text ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

export const escapeAttribute = escapeHtml;
