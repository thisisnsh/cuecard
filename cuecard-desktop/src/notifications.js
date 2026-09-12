/**
 * Notices from the worker, shown above the script or quietly in Settings.
 *
 * A port of the phone app's `RemoteNotificationService`, against the same
 * `/v2/notifications` payload. The worker serves one list to everyone and
 * leaves the filtering to the client, so every check below is ours to make.
 *
 * The whole thing fails open: the last good response is kept and used at
 * launch, a fetch that times out or comes back malformed changes nothing, and
 * a client that has never reached the worker shows nothing at all.
 */

import { appVersion, fetchNotificationsPayload, getStored, platformInfo, setStored, track } from './tauri.js';

const KEY_PAYLOAD = 'notifications_payload';
const KEY_DISMISSED = 'notifications_dismissed';

/** Long enough not to hammer the edge, short enough to pull a bad notice within a session. */
const MIN_REFRESH_MS = 15 * 60 * 1000;

/**
 * Hosts a notification may link to, mirrored from the worker. The worker no
 * longer checks these itself, so this is the only enforcement: a link anywhere
 * else means the notification is dropped rather than shown.
 */
const ALLOWED_HOSTS = new Set(['cuecard.dev', 'www.cuecard.dev', 'github.com', 'apps.apple.com']);

const SURFACES = new Set(['homeBanner', 'settingsRow']);
const SEVERITIES = new Set(['info', 'warning', 'critical']);
const ACTION_KINDS = new Set(['openURL', 'appStore', 'dismiss']);

const state = {
  list: [],
  dismissed: new Set(),
  lastRefresh: 0,
  build: { platform: platformInfo().platform, version: null },
};

const listeners = new Set();
export function onNotificationsChange(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}
const changed = () => listeners.forEach((fn) => fn());

// =============================================================================
// READING THE PAYLOAD
// =============================================================================

/** "1.3.0" -> [1, 3, 0]. Null for anything that isn't one to four plain numbers. */
function versionComponents(text) {
  const parts = String(text ?? '').split('.');
  if (parts.length < 1 || parts.length > 4) return null;

  const numbers = [];
  for (const part of parts) {
    if (!/^\d+$/.test(part)) return null;
    numbers.push(Number(part));
  }
  return numbers;
}

/** Component-wise, padding the shorter side, so 1.10.0 lands above 1.9.0. */
function compareVersions(left, right) {
  for (let i = 0; i < Math.max(left.length, right.length); i += 1) {
    const a = left[i] ?? 0;
    const b = right[i] ?? 0;
    if (a !== b) return a < b ? -1 : 1;
  }
  return 0;
}

/** One notification, or null. A malformed one drops out without taking the rest with it. */
function readNotification(raw) {
  if (!raw || typeof raw !== 'object') return null;
  if (typeof raw.id !== 'string' || !raw.id) return null;
  if (!SURFACES.has(raw.surface)) return null;
  if (typeof raw.title !== 'string' || !raw.title.trim()) return null;

  const actions = [];
  for (const action of Array.isArray(raw.actions) ? raw.actions : []) {
    // An action kind we cannot carry out is usually the point of the notice, so
    // the whole thing goes rather than showing a button that does nothing.
    if (!action || !ACTION_KINDS.has(action.kind) || typeof action.label !== 'string') return null;
    if (action.kind === 'openURL') {
      let host;
      try {
        host = new URL(action.url).host;
      } catch {
        return null;
      }
      if (!ALLOWED_HOSTS.has(host)) return null;
    }
    actions.push({ kind: action.kind, label: action.label, url: action.url });
  }
  if (actions.length > 2) return null;

  const targets = [];
  for (const target of Array.isArray(raw.targets) ? raw.targets : []) {
    if (!target || typeof target.platform !== 'string') return null;
    const min = target.minVersion === undefined ? null : versionComponents(target.minVersion);
    const max = target.maxVersion === undefined ? null : versionComponents(target.maxVersion);
    // A bound we cannot read is one we cannot honour; quieter to drop the notice
    // than to show it to the builds the bound was written to exclude.
    if (target.minVersion !== undefined && !min) return null;
    if (target.maxVersion !== undefined && !max) return null;
    targets.push({
      platform: target.platform,
      minVersion: min,
      maxVersion: max,
      minBuild: typeof target.minBuild === 'number' ? target.minBuild : null,
      maxBuild: typeof target.maxBuild === 'number' ? target.maxBuild : null,
    });
  }

  const dismissible = typeof raw.dismissible === 'boolean' ? raw.dismissible : true;
  // Something with no way out and nothing to do is something nobody can close.
  if (!dismissible && actions.length === 0) return null;

  return {
    id: raw.id,
    surface: raw.surface,
    severity: SEVERITIES.has(raw.severity) ? raw.severity : 'info',
    priority: typeof raw.priority === 'number' ? raw.priority : 0,
    title: raw.title,
    body: typeof raw.body === 'string' ? raw.body : '',
    actions,
    dismissible,
    targets,
    expiresAt: typeof raw.expiresAt === 'string' ? Date.parse(raw.expiresAt) : null,
  };
}

function readPayload(raw) {
  const list = Array.isArray(raw?.notifications) ? raw.notifications : [];
  return list.map(readNotification).filter(Boolean);
}

// =============================================================================
// WHO SEES WHAT
// =============================================================================

/** No targets means everyone, which is what every notice was before targeting. */
function isTargeted(notification) {
  if (notification.targets.length === 0) return true;

  return notification.targets.some((target) => {
    if (target.platform !== state.build.platform) return false;

    if (target.minVersion || target.maxVersion) {
      if (!state.build.version) return false;
      if (target.minVersion && compareVersions(state.build.version, target.minVersion) < 0) return false;
      if (target.maxVersion && compareVersions(state.build.version, target.maxVersion) > 0) return false;
    }
    // A desktop build has no build number, so a notice bounded by one passes it by.
    if (target.minBuild !== null || target.maxBuild !== null) return false;

    return true;
  });
}

const hasExpired = (notification) =>
  notification.expiresAt !== null && !Number.isNaN(notification.expiresAt) && notification.expiresAt <= Date.now();

const isShowable = (notification) =>
  isTargeted(notification) && !hasExpired(notification) && !state.dismissed.has(notification.id);

/** The one notice for a surface: the highest priority still showable. */
export function notificationFor(surface) {
  return state.list
    .filter((n) => n.surface === surface && isShowable(n))
    .sort((a, b) => b.priority - a.priority)[0] || null;
}

// =============================================================================
// LOADING AND REFRESHING
// =============================================================================

export async function loadNotifications() {
  state.build.version = versionComponents(await appVersion());
  state.dismissed = new Set((await getStored(KEY_DISMISSED)) || []);

  const cached = await getStored(KEY_PAYLOAD);
  if (cached) state.list = readPayload(cached);
  changed();
}

/** Pull the current list. Safe on every launch: it throttles itself and never throws. */
export async function refreshNotifications({ force = false } = {}) {
  if (!force && Date.now() - state.lastRefresh < MIN_REFRESH_MS) return;

  try {
    const body = await fetchNotificationsPayload();
    if (!body) return;

    const raw = JSON.parse(body);
    state.lastRefresh = Date.now();
    state.list = readPayload(raw);
    await setStored(KEY_PAYLOAD, raw);
    await pruneDismissals();
    changed();
  } catch {
    // Offline, slow, or unreadable. Whatever was cached stays in force.
  }
}

/** Forget dismissals for notices the worker has stopped sending. */
async function pruneDismissals() {
  const live = new Set(state.list.map((n) => n.id));
  const kept = [...state.dismissed].filter((id) => live.has(id));
  if (kept.length === state.dismissed.size) return;

  state.dismissed = new Set(kept);
  await setStored(KEY_DISMISSED, kept);
}

export async function dismissNotification(notification) {
  if (!notification.dismissible) return;
  state.dismissed.add(notification.id);
  await setStored(KEY_DISMISSED, [...state.dismissed]);
  track('remote_message_dismissed', { message_id: notification.id });
  changed();
}

export const logImpression = (notification) =>
  track('remote_message_shown', { message_id: notification.id, surface: notification.surface });

export const logAction = (action, notification) =>
  track('remote_message_action', { message_id: notification.id, action: action.kind });
