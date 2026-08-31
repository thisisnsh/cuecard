/**
 * CueCard mobile worker — cuecard-mobile.thisisnsh.workers.dev
 *
 *   GET  /v2/config   Remote config for the mobile apps: kill switches, and any
 *                     notice we want in front of people between releases.
 *   POST /v2/welcome  Retired welcome-email endpoint, kept as a 204 shim so
 *                     already-released builds don't surface an error.
 *
 * Everything /v2/config serves is hardcoded below. Changing what the apps show is
 * an edit to this file plus a deploy — there is no database and nothing to sign
 * into. An empty MESSAGES list is the normal, quiet state: a client that gets
 * nothing back, or a broken response, or no response at all, carries on exactly
 * as if this endpoint didn't exist. The one thing that can block an app is
 * minSupportedVersion, so treat that field with more care than the rest.
 */

const SCHEMA = 1;

/**
 * Behaviour the apps read silently. Nothing here draws UI on its own except
 * minSupportedVersion.
 *
 *   minSupportedVersion  Anything older is stopped at launch with an update
 *                        screen. Raising this locks people out until they
 *                        update, so it's for shipped-a-broken-build days only.
 *   updateURL            Where that screen sends people, per platform. The
 *                        response carries the one string that matches the
 *                        requesting platform; clients fall back to their own
 *                        store link if it's missing.
 *   features             Kill switches. Every one of them defaults to ON in the
 *                        client, so setting a flag to false is the only thing
 *                        that has any effect — a client that never reaches this
 *                        worker keeps its full feature set.
 */
const FLAGS = {
  minSupportedVersion: "0.0.0",
  updateURL: {
    ios: "https://apps.apple.com/app/id6757321325",
    android: "https://cuecard.dev/mobile",
  },
  features: {
    pip: true,
    appleSignIn: true,
    googleSignIn: true,
  },
};

/**
 * Things to show. Ordered by `priority` (higher first); each surface displays at
 * most one message, so a second one only appears once the first is gone.
 *
 *   id             Stable and unique. Clients remember dismissals by it, so
 *                  never reuse an id for different copy — a returning id is
 *                  treated as the message the user already dismissed.
 *   surface        "homeBanner" — card above the editor on the home screen.
 *                  "settingsRow" — row at the top of Settings. Quieter; good
 *                  for cross-promotion and anything not worth interrupting for.
 *   severity       "info" | "warning" | "critical". Picks the accent colour.
 *   title          One line. Required.
 *   body           A sentence or two. Optional.
 *   actions        Up to 2. { kind, label, url }, where kind is "openURL"
 *                  (url must be on cuecard.dev, apps.apple.com or github.com —
 *                  clients drop the whole message otherwise), "appStore" (the
 *                  app's own listing, no url needed) or "dismiss".
 *   dismissible    Defaults to true. A message with no actions and no dismiss
 *                  is one nobody can get rid of, so only turn this off for
 *                  something genuinely temporary like an ongoing incident.
 *   expiresAt      ISO 8601. Optional but strongly encouraged — it's what stops
 *                  a stale incident banner outliving the incident when we
 *                  forget to come back and delete it.
 *   rolloutPercent 0–100, default 100. Each install picks a stable bucket once,
 *                  so a partial rollout stays consistent for a given user.
 *   match          Narrows the audience: { platforms, minVersion, maxVersion,
 *                  minBuild, locales }. Filtered here and re-checked on device,
 *                  which matters because a client may still be holding a cached
 *                  copy from before it was updated.
 *
 * A worked example, left commented out as the template:
 *
 *   {
 *     id: "android-launch-2026-09",
 *     surface: "homeBanner",
 *     severity: "info",
 *     priority: 10,
 *     title: "CueCard for Android is here",
 *     body: "Same notes and cues, now on Android.",
 *     actions: [
 *       { kind: "openURL", label: "Take a look", url: "https://cuecard.dev/mobile" },
 *     ],
 *     dismissible: true,
 *     expiresAt: "2026-10-15T00:00:00Z",
 *     rolloutPercent: 100,
 *     match: { platforms: ["ios"], minVersion: "1.2.0", locales: ["en"] },
 *   },
 */
const MESSAGES = [];

/** Hosts a message is allowed to link to. Mirrored in the clients. */
const ALLOWED_HOSTS = ["cuecard.dev", "www.cuecard.dev", "apps.apple.com", "github.com"];

/** Compare two dotted versions. Returns -1, 0 or 1; missing parts count as 0. */
function compareVersions(a, b) {
  const left = String(a).split(".");
  const right = String(b).split(".");

  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const l = parseInt(left[i], 10) || 0;
    const r = parseInt(right[i], 10) || 0;
    if (l !== r) return l < r ? -1 : 1;
  }

  return 0;
}

/** Whether a message's `match` block and expiry admit this particular client. */
function isEligible(message, client, now) {
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

function configFor(client) {
  const now = new Date();

  return {
    schema: SCHEMA,
    flags: {
      minSupportedVersion: FLAGS.minSupportedVersion,
      updateURL: FLAGS.updateURL[client.platform] || null,
      features: FLAGS.features,
    },
    messages: MESSAGES.filter((message) => isEligible(message, client, now)).sort(
      (a, b) => (b.priority || 0) - (a.priority || 0)
    ),
  };
}

export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === "/v2/config") {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return new Response("Method Not Allowed", {
          status: 405,
          headers: { Allow: "GET" },
        });
      }

      const params = url.searchParams;
      const client = {
        platform: (params.get("p") || "").toLowerCase(),
        version: params.get("v") || "0.0.0",
        build: parseInt(params.get("b"), 10) || 0,
        locale: params.get("l") || "en",
      };

      return new Response(JSON.stringify(configFor(client)), {
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          // Five minutes is short enough that pulling a bad message is quick and
          // long enough that the edge absorbs the traffic. The whole response is
          // derived from the query string, so it caches per client shape.
          "Cache-Control": "public, max-age=300",
        },
      });
    }

    if (url.pathname === "/welcome" || url.pathname === "/v2/welcome") {
      if (request.method !== "POST") {
        return new Response("Method Not Allowed", {
          status: 405,
          headers: { Allow: "POST" },
        });
      }

      // Compatibility shim for released app versions. Welcome emails have been
      // retired, but returning success avoids unnecessary client-side errors.
      return new Response(null, { status: 204 });
    }

    return new Response("Not Found", { status: 404 });
  },
};
