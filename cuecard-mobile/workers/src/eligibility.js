import { ALLOWED_HOSTS } from "./messages.js";

/** Compare two dotted versions. Returns -1, 0 or 1; missing parts count as 0. */
export function compareVersions(a, b) {
  const left = String(a).split(".");
  const right = String(b).split(".");

  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const l = parseInt(left[i], 10) || 0;
    const r = parseInt(right[i], 10) || 0;
    if (l !== r) return l < r ? -1 : 1;
  }

  return 0;
}

/** Whether a message's expiry, links and `match` block admit this client. */
export function isEligible(message, client, now) {
  if (message.expiresAt && new Date(message.expiresAt) <= now) return false;

  for (const action of message.actions || []) {
    if (action.kind !== "openURL") continue;
    try {
      if (!ALLOWED_HOSTS.includes(new URL(action.url).hostname)) return false;
    } catch {
      return false;
    }
  }

  const match = message.match;
  if (!match) return true;

  if (match.platforms && !match.platforms.includes(client.platform)) return false;
  if (match.minVersion && compareVersions(client.version, match.minVersion) < 0) return false;
  if (match.maxVersion && compareVersions(client.version, match.maxVersion) > 0) return false;
  if (match.minBuild && client.build < match.minBuild) return false;

  // Locales are matched on language alone: "en" covers en-US, en-GB and the rest.
  if (match.locales) {
    const language = client.locale.split("-")[0].toLowerCase();
    if (!match.locales.some((l) => l.split("-")[0].toLowerCase() === language)) return false;
  }

  return true;
}
