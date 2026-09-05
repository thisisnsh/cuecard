# cuecard-mobile worker

Remote config for the CueCard mobile apps, served from
`cuecard-mobile.thisisnsh.workers.dev`.

| Endpoint | Purpose |
| --- | --- |
| `GET /v2/config` | Kill switches, and any notice we want in front of people between releases. |
| `POST /v2/welcome` | Retired welcome-email endpoint, kept as a 204 shim so already-released builds don't surface an error. |

Everything `/v2/config` serves is hardcoded. Changing what the apps show is an
edit to these files plus a deploy — there is no database and nothing to sign
into. An empty `MESSAGES` list is the normal, quiet state: a client that gets
nothing back, or a broken response, or no response at all, carries on exactly as
if this endpoint didn't exist. The one thing that can block an app is
`minSupportedVersion`, so treat that field with more care than the rest.

## Layout

```
src/
  index.js            Routing.
  schema.js           SCHEMA version and FLAGS.
  messages.js         MESSAGES and the link allowlist.
  eligibility.js      Version comparison and per-client filtering.
  endpoints/
    config.js         GET /v2/config
    welcome.js        POST /welcome, POST /v2/welcome
```

Deploy from this directory with:

```
npx wrangler deploy src/index.js --name cuecard-mobile --compatibility-date 2025-08-30
```

## Flags (`src/schema.js`)

Behaviour the apps read silently. Nothing here draws UI on its own except
`minSupportedVersion`.

- **`minSupportedVersion`** — anything older is stopped at launch with an update
  screen. Raising this locks people out until they update, so it's for
  shipped-a-broken-build days only.
- **`updateURL`** — where that screen sends people, per platform. The response
  carries the one string that matches the requesting platform; clients fall back
  to their own store link if it's missing.
- **`features`** — kill switches. Every one of them defaults to ON in the client,
  so setting a flag to `false` is the only thing that has any effect — a client
  that never reaches this worker keeps its full feature set.

## Messages (`src/messages.js`)

Things to show. Ordered by `priority` (higher first); each surface displays at
most one message, so a second one only appears once the first is gone.

- **`id`** — stable and unique. Clients remember dismissals by it, so never reuse
  an id for different copy — a returning id is treated as the message the user
  already dismissed.
- **`surface`** — `"homeBanner"` is the card above the editor on the home screen.
  `"settingsRow"` is the row at the top of Settings; quieter, and good for
  cross-promotion and anything not worth interrupting for.
- **`severity`** — `"info" | "warning" | "critical"`. Picks the accent colour.
- **`title`** — one line. Required.
- **`body`** — a sentence or two. Optional.
- **`actions`** — up to 2, each `{ kind, label, url }`. `kind` is `"openURL"` (the
  url must be on cuecard.dev, apps.apple.com or github.com — clients drop the
  whole message otherwise), `"appStore"` (the app's own listing, no url needed)
  or `"dismiss"`.
- **`dismissible`** — defaults to true. A message with no actions and no dismiss
  is one nobody can get rid of, so only turn this off for something genuinely
  temporary like an ongoing incident.
- **`expiresAt`** — ISO 8601. Optional but strongly encouraged; it's what stops a
  stale incident banner outliving the incident when we forget to come back and
  delete it.
- **`rolloutPercent`** — 0–100, default 100. Each install picks a stable bucket
  once, so a partial rollout stays consistent for a given user.
- **`match`** — narrows the audience: `{ platforms, minVersion, maxVersion,
  minBuild, locales }`. Filtered in the worker and re-checked on device, which
  matters because a client may still be holding a cached copy from before it was
  updated.

A worked example to copy:

```js
{
  id: "android-launch-2026-09",
  surface: "homeBanner",
  severity: "info",
  priority: 10,
  title: "CueCard for Android is here",
  body: "Same notes and cues, now on Android.",
  actions: [
    { kind: "openURL", label: "Take a look", url: "https://cuecard.dev/mobile" },
  ],
  dismissible: true,
  expiresAt: "2026-10-15T00:00:00Z",
  rolloutPercent: 100,
  match: { platforms: ["ios"], minVersion: "1.2.0", locales: ["en"] },
}
```
