/**
 * The settings the phone app keeps, plus the few a window has that a phone
 * does not. Each one is stored under its own key, applied the moment it
 * changes, and read back by whoever needs it.
 */

import { getStored, setStored, setInvisible, trackSetting } from './tauri.js';
import { CUE_COLORS, DEFAULT_CUE_COLOR } from './parser.js';

/** Script sizes, as the phone app offers them. */
export const FONT_SIZES = { small: 20, medium: 28, large: 40 };

/** The speeds a typed lines-a-minute figure is held to. */
export const LPM_RANGE = [1, 300];
/** The delays a typed start delay is held to. */
export const COUNTDOWN_RANGE = [0, 60];

export const DEFAULTS = {
  opacity: 100,
  invisible: true,
  theme: 'system',
  cueColor: DEFAULT_CUE_COLOR,
  timerMinutes: 1,
  timerSeconds: 0,
  countdownSeconds: 5,
  linesPerMinute: 50,
  fontSizePreset: 'medium',
};

const KEYS = {
  opacity: 'settings_opacity',
  invisible: 'settings_ghost_mode',
  theme: 'settings_theme',
  cueColor: 'settings_cue_color',
  timerMinutes: 'settings_timer_minutes',
  timerSeconds: 'settings_timer_seconds',
  countdownSeconds: 'settings_countdown_seconds',
  linesPerMinute: 'settings_lines_per_minute',
  fontSizePreset: 'settings_font_size_preset',
};

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
export const timerDuration = () => settings.timerMinutes * 60 + settings.timerSeconds;
export const scriptFontSize = () => FONT_SIZES[settings.fontSizePreset] || FONT_SIZES.medium;

export async function loadSettings() {
  const stored = {};
  for (const [key, storageKey] of Object.entries(KEYS)) stored[key] = await getStored(storageKey);

  settings.opacity = typeof stored.opacity === 'number' ? clamp(stored.opacity, [10, 100]) : DEFAULTS.opacity;
  settings.invisible = typeof stored.invisible === 'boolean' ? stored.invisible : DEFAULTS.invisible;
  settings.theme = ['system', 'light', 'dark'].includes(stored.theme) ? stored.theme : DEFAULTS.theme;
  settings.cueColor = CUE_COLORS.includes(stored.cueColor) ? stored.cueColor : DEFAULTS.cueColor;
  settings.countdownSeconds =
    typeof stored.countdownSeconds === 'number' ? clamp(stored.countdownSeconds, COUNTDOWN_RANGE) : DEFAULTS.countdownSeconds;
  settings.fontSizePreset = stored.fontSizePreset in FONT_SIZES ? stored.fontSizePreset : DEFAULTS.fontSizePreset;

  hadStoredTimer = typeof stored.timerMinutes === 'number' || typeof stored.timerSeconds === 'number';
  settings.timerMinutes = typeof stored.timerMinutes === 'number' ? clamp(stored.timerMinutes, [0, 59]) : DEFAULTS.timerMinutes;
  settings.timerSeconds = typeof stored.timerSeconds === 'number' ? clamp(stored.timerSeconds, [0, 59]) : DEFAULTS.timerSeconds;

  // Speed used to be a 0–2x multiplier applied per animation frame. Anyone who
  // set one carries that figure and no lines-a-minute setting, so convert it at
  // the speed it actually scrolled: 1x moved a 24px line about 2.5 times a second.
  if (typeof stored.linesPerMinute === 'number') {
    settings.linesPerMinute = clamp(stored.linesPerMinute, LPM_RANGE);
  } else {
    const legacy = await getStored('settings_auto_scroll_speed');
    const multiplier = typeof legacy === 'string' ? { off: 0, low: 0.5, medium: 1, high: 2 }[legacy] : legacy;
    settings.linesPerMinute =
      typeof multiplier === 'number' && multiplier > 0
        ? clamp(Math.round(multiplier * 150), LPM_RANGE)
        : DEFAULTS.linesPerMinute;
    await setStored(KEYS.linesPerMinute, settings.linesPerMinute);
  }

  applyAll();
}

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
  await setStored(KEYS[key], value);
  if (track) trackSetting(key, value);

  apply(key);
  listeners.forEach((fn) => fn(key, value));
}

/** Put every setting back to what the app ships with. */
export async function resetSettings() {
  for (const [key, value] of Object.entries(DEFAULTS)) {
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
  switch (key) {
    case 'theme':
      applyTheme();
      break;
    case 'opacity':
      document.documentElement.style.setProperty('--bg-opacity', settings.opacity / 100);
      break;
    case 'cueColor':
      document.documentElement.style.setProperty('--cue-color', `var(--color-${settings.cueColor})`);
      break;
    case 'invisible':
      setInvisible(settings.invisible);
      break;
    default:
      break;
  }
}

function applyAll() {
  ['theme', 'opacity', 'cueColor', 'invisible'].forEach(apply);
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
