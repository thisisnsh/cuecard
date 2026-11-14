/**
 * The settings the phone app keeps, plus the few a window has that a phone
 * does not. Each one is stored under its own key, applied the moment it
 * changes, and read back by whoever needs it.
 *
 * Teleprompter and Cards each keep their own text sizes, cue colour and timer,
 * as they do on the phone.
 */

import { getStored, setStored, setInvisible, trackSetting } from './tauri.js';
import { CUE_COLORS, DEFAULT_CUE_COLOR } from './parser.js';

/** The script as it scrolls, or a card as it's read. */
export const VIEWER_SIZE_PRESETS = [
  { label: 'XS', value: 20 },
  { label: 'S', value: 24 },
  { label: 'M', value: 28 },
  { label: 'L', value: 34 },
  { label: 'XL', value: 40 },
];

/** The script as it's written. */
export const EDITOR_SIZE_PRESETS = [
  { label: 'XS', value: 12 },
  { label: 'S', value: 14 },
  { label: 'M', value: 16 },
  { label: 'L', value: 20 },
  { label: 'XL', value: 24 },
];

export const VIEWER_SIZE_RANGE = [16, 72];
export const EDITOR_SIZE_RANGE = [12, 40];
/** The speeds a typed lines-a-minute figure is held to. */
export const LPM_RANGE = [1, 300];
/** The delays a typed countdown is held to. */
export const COUNTDOWN_RANGE = [0, 60];

/**
 * How a set timer is coloured: one colour while there's time, another from
 * `warningSeconds` left, and a third from zero on into overtime. With no timer
 * set it counts up in the normal colour, and the teleprompter's countdown
 * counts down in another.
 */
export const DEFAULT_TIMER_STYLE = Object.freeze({
  warningSeconds: 10,
  normalColor: 'green',
  warningColor: 'yellow',
  overtimeColor: 'red',
  countdownColor: 'pink',
});

export const DEFAULTS = {
  opacity: 100,
  invisible: true,
  theme: 'system',

  // Teleprompter
  cueColor: DEFAULT_CUE_COLOR,
  // No timer until one is set: a run nobody has given a length counts up from
  // zero rather than down from a length it was never asked for.
  timerMinutes: 0,
  timerSeconds: 0,
  timerStyle: DEFAULT_TIMER_STYLE,
  countdownSeconds: 5,
  linesPerMinute: 50,
  fontSize: 28,
  editorFontSize: 16,
  showsReadingGuide: true,
  // As high as the guide goes, so the most of the script is in view under it.
  readingGuidePosition: 0,
  mirrorsText: false,
  flipsTextVertically: false,

  // Cards
  cardsCueColor: DEFAULT_CUE_COLOR,
  cardsTimerMinutes: 0,
  cardsTimerSeconds: 0,
  cardsTimerStyle: DEFAULT_TIMER_STYLE,
  cardsFontSize: 28,
  cardsEditorFontSize: 16,
};

const KEYS = {
  opacity: 'settings_opacity',
  invisible: 'settings_ghost_mode',
  theme: 'settings_theme',
  cueColor: 'settings_cue_color',
  timerMinutes: 'settings_timer_minutes',
  timerSeconds: 'settings_timer_seconds',
  timerStyle: 'settings_timer_style',
  countdownSeconds: 'settings_countdown_seconds',
  linesPerMinute: 'settings_lines_per_minute',
  fontSize: 'settings_font_size',
  editorFontSize: 'settings_editor_font_size',
  showsReadingGuide: 'settings_reading_guide',
  readingGuidePosition: 'settings_reading_guide_position',
  mirrorsText: 'settings_flip_horizontal',
  flipsTextVertically: 'settings_flip_vertical',
  cardsCueColor: 'settings_cards_cue_color',
  cardsTimerMinutes: 'settings_cards_timer_minutes',
  cardsTimerSeconds: 'settings_cards_timer_seconds',
  cardsTimerStyle: 'settings_cards_timer_style',
  cardsFontSize: 'settings_cards_font_size',
  cardsEditorFontSize: 'settings_cards_editor_font_size',
};

/** The settings Reset to Defaults leaves alone: where things are, not how they look. */
const NOT_RESET = new Set(['readingGuidePosition']);

/** The live settings. Read freely; change only through `setSetting`. */
export const settings = { ...DEFAULTS };

/** True when a timer duration was already stored, so nothing should seed one. */
export let hadStoredTimer = false;

const listeners = new Set();
export function onSettingsChange(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export const clamp = (value, [min, max]) => Math.min(Math.max(value, min), max);

// =============================================================================
// PER MODE
// =============================================================================

/** The keys a mode keeps its own of. */
export const modeKey = (mode, key) =>
  mode === 'cards' ? `cards${key[0].toUpperCase()}${key.slice(1)}` : key;

export const modeSetting = (mode, key) => settings[modeKey(mode, key)];

export const timerDuration = (mode = 'teleprompter') =>
  modeSetting(mode, 'timerMinutes') * 60 + modeSetting(mode, 'timerSeconds');

export const timerStyle = (mode = 'teleprompter') => modeSetting(mode, 'timerStyle');

/** The colour for `remaining` seconds left of `duration`. Untimed counts up in
 *  the normal colour. */
export function timerColor(style, remaining, duration) {
  if (duration <= 0) return style.normalColor;
  if (remaining <= 0) return style.overtimeColor;
  if (remaining <= style.warningSeconds) return style.warningColor;
  return style.normalColor;
}

// =============================================================================
// LOADING
// =============================================================================

const isNumber = (value) => typeof value === 'number' && Number.isFinite(value);

function sanitizeTimerStyle(value) {
  if (!value || typeof value !== 'object') return DEFAULT_TIMER_STYLE;
  const color = (name) => (CUE_COLORS.includes(value[name]) ? value[name] : DEFAULT_TIMER_STYLE[name]);
  return {
    warningSeconds: isNumber(value.warningSeconds) ? clamp(Math.round(value.warningSeconds), [0, 3599]) : 10,
    normalColor: color('normalColor'),
    warningColor: color('warningColor'),
    overtimeColor: color('overtimeColor'),
    countdownColor: color('countdownColor'),
  };
}

const VALIDATORS = {
  opacity: (v) => (isNumber(v) ? clamp(v, [10, 100]) : undefined),
  invisible: (v) => (typeof v === 'boolean' ? v : undefined),
  theme: (v) => (['system', 'light', 'dark'].includes(v) ? v : undefined),
  cueColor: (v) => (CUE_COLORS.includes(v) ? v : undefined),
  cardsCueColor: (v) => (CUE_COLORS.includes(v) ? v : undefined),
  timerMinutes: (v) => (isNumber(v) ? clamp(v, [0, 59]) : undefined),
  timerSeconds: (v) => (isNumber(v) ? clamp(v, [0, 59]) : undefined),
  cardsTimerMinutes: (v) => (isNumber(v) ? clamp(v, [0, 59]) : undefined),
  cardsTimerSeconds: (v) => (isNumber(v) ? clamp(v, [0, 59]) : undefined),
  timerStyle: (v) => (v ? sanitizeTimerStyle(v) : undefined),
  cardsTimerStyle: (v) => (v ? sanitizeTimerStyle(v) : undefined),
  countdownSeconds: (v) => (isNumber(v) ? clamp(v, COUNTDOWN_RANGE) : undefined),
  linesPerMinute: (v) => (isNumber(v) ? clamp(v, LPM_RANGE) : undefined),
  fontSize: (v) => (isNumber(v) ? clamp(v, VIEWER_SIZE_RANGE) : undefined),
  cardsFontSize: (v) => (isNumber(v) ? clamp(v, VIEWER_SIZE_RANGE) : undefined),
  editorFontSize: (v) => (isNumber(v) ? clamp(v, EDITOR_SIZE_RANGE) : undefined),
  cardsEditorFontSize: (v) => (isNumber(v) ? clamp(v, EDITOR_SIZE_RANGE) : undefined),
  showsReadingGuide: (v) => (typeof v === 'boolean' ? v : undefined),
  readingGuidePosition: (v) => (isNumber(v) ? clamp(v, [0, 1]) : undefined),
  mirrorsText: (v) => (typeof v === 'boolean' ? v : undefined),
  flipsTextVertically: (v) => (typeof v === 'boolean' ? v : undefined),
};

export async function loadSettings() {
  for (const [key, storageKey] of Object.entries(KEYS)) {
    const value = VALIDATORS[key](await getStored(storageKey));
    settings[key] = value === undefined ? DEFAULTS[key] : value;
  }

  const storedMinutes = await getStored(KEYS.timerMinutes);
  const storedSeconds = await getStored(KEYS.timerSeconds);
  hadStoredTimer = isNumber(storedMinutes) || isNumber(storedSeconds);

  await migrateLegacy();
  applyAll();
}

/** Settings written by older versions, brought up to what they are now. */
async function migrateLegacy() {
  // Text size used to be Small, Medium or Large.
  if (!isNumber(await getStored(KEYS.fontSize))) {
    const preset = await getStored('settings_font_size_preset');
    const size = { small: 20, medium: 28, large: 40 }[preset];
    if (size) {
      settings.fontSize = size;
      await setStored(KEYS.fontSize, size);
    }
  }

  // Speed used to be a 0–2x multiplier applied per animation frame. Anyone who
  // set one carries that figure and no lines-a-minute setting, so convert it at
  // the speed it actually scrolled: 1x moved a 24px line about 2.5 times a second.
  if (!isNumber(await getStored(KEYS.linesPerMinute))) {
    const legacy = await getStored('settings_auto_scroll_speed');
    const multiplier = typeof legacy === 'string' ? { off: 0, low: 0.5, medium: 1, high: 2 }[legacy] : legacy;
    settings.linesPerMinute =
      isNumber(multiplier) && multiplier > 0 ? clamp(Math.round(multiplier * 150), LPM_RANGE) : DEFAULTS.linesPerMinute;
    await setStored(KEYS.linesPerMinute, settings.linesPerMinute);
  }
}

// =============================================================================
// CHANGING
// =============================================================================

/**
 * Change a setting: store it, apply it, and tell everyone who is watching.
 *
 * `force` writes even when the value has not changed, which is what seeding a
 * setting from an older install needs — the figure may already be the default,
 * and it still has to reach the store.
 */
export async function setSetting(key, value, { track = true, force = false } = {}) {
  if (!(key in KEYS)) return;
  if (settings[key] === value && !force) return;

  settings[key] = value;
  apply(key);
  listeners.forEach((fn) => fn(key, value));

  await setStored(KEYS[key], value);
  if (track) trackSetting(key, typeof value === 'object' ? JSON.stringify(value) : value);
}

/** Whether anything Reset to Defaults would change. */
export function canResetSettings() {
  return Object.keys(DEFAULTS).some(
    (key) => !NOT_RESET.has(key) && JSON.stringify(settings[key]) !== JSON.stringify(DEFAULTS[key])
  );
}

/** Put every setting back to what the app ships with. */
export async function resetSettings() {
  for (const [key, value] of Object.entries(DEFAULTS)) {
    if (NOT_RESET.has(key)) continue;
    settings[key] = value;
    await setStored(KEYS[key], value);
  }
  applyAll();
  listeners.forEach((fn) => fn('*', null));
}

// =============================================================================
// APPLYING
// =============================================================================

function apply(key) {
  const root = document.documentElement.style;
  switch (key) {
    case 'theme':
      applyTheme();
      break;
    case 'opacity':
      root.setProperty('--bg-opacity', settings.opacity / 100);
      break;
    case 'cueColor':
      root.setProperty('--cue-teleprompter', `var(--color-${settings.cueColor})`);
      break;
    case 'cardsCueColor':
      root.setProperty('--cue-cards', `var(--color-${settings.cardsCueColor})`);
      break;
    case 'editorFontSize':
      root.setProperty('--editor-size-teleprompter', `${settings.editorFontSize}px`);
      break;
    case 'cardsEditorFontSize':
      root.setProperty('--editor-size-cards', `${settings.cardsEditorFontSize}px`);
      break;
    case 'invisible':
      setInvisible(settings.invisible);
      break;
    default:
      break;
  }
}

function applyAll() {
  ['theme', 'opacity', 'cueColor', 'cardsCueColor', 'editorFontSize', 'cardsEditorFontSize', 'invisible'].forEach(apply);
}

function applyTheme() {
  const root = document.documentElement;
  const dark = settings.theme === 'dark' || (settings.theme === 'system' && !prefersLight());
  root.classList.toggle('theme-light', !dark);
  root.classList.toggle('theme-dark', dark);
  root.style.colorScheme = dark ? 'dark' : 'light';
}

const prefersLight = () => window.matchMedia?.('(prefers-color-scheme: light)').matches ?? false;

/** Follow the system when the system is what we are following. */
export function watchSystemTheme() {
  window.matchMedia?.('(prefers-color-scheme: light)').addEventListener('change', () => {
    if (settings.theme === 'system') applyTheme();
  });
}
