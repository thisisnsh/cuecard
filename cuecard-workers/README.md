# cuecard-mobile worker

Notifications for the CueCard mobile apps, served from
`cuecard-mobile.thisisnsh.workers.dev`.

| Endpoint | Purpose |
| --- | --- |
| `GET /v2/notifications` | Everything the apps should show right now. |
| `POST /v2/welcome` | Retired welcome-email endpoint, kept as a 204 shim so already-released builds don't surface an error. |

The list is hardcoded, so publishing a notification is an edit to
`src/notifications.ts` plus a deploy — there is no database and nothing to sign
into. An empty list is the normal, quiet state: a client that gets nothing back,
or a broken response, or no response at all, carries on exactly as if this
endpoint didn't exist.

Everyone gets the same list — the worker sorts by `priority` and serves, with no
rollout percentage and nothing per-client. All the filtering happens on device:
expiry, the link allowlist, remembering dismissals, and the `targets` audience
check below.

## Layout

```
src/
  types.ts                  The wire format. Start here.
  notifications.ts          The list itself.
  index.ts                  Routing.
  endpoints/
    notifications.ts        GET /v2/notifications
    welcome.ts              POST /welcome, POST /v2/welcome
```

Type-check with `npx tsc --noEmit`. Deploy from this directory with:

```
npx wrangler deploy src/index.ts --name cuecard-mobile --compatibility-date 2025-08-30
```

Wrangler compiles the TypeScript on the way out; there is nothing to build first
and no `node_modules` to install.

## Writing a notification

Fields, defaults and the exact unions live in `src/types.ts` — that file is the
schema, and `tsc` will reject anything that doesn't fit. The shape is mirrored by
`RemoteConfig.swift` on iOS and `RemoteConfig.kt` on Android, so a change to the
type is a change to three files.

Two things worth care:

- **`id` must be stable and unique.** Clients remember dismissals by it, so
  reusing an id for different copy shows nothing to anyone who dismissed the
  first one.
- **Set `expiresAt`.** It's what stops a stale incident banner outliving the
  incident when nobody remembers to come back and delete it.

```ts
export const NOTIFICATIONS: Notification[] = [
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
    expiresAt: "2026-10-15T00:00:00Z",
  },
];
```

## Targeting

A notification with no `targets` goes to everyone, which is how all of them
behaved before this existed. Adding some restricts it to the builds matching at
least one:

```ts
// Everyone on iOS.
targets: [{ platform: "ios" }],

// Anyone still on an old build of either app, told to update.
targets: [
  { platform: "ios", maxBuild: 7 },
  { platform: "android", maxBuild: 3 },
],

// A single Android version range.
targets: [{ platform: "android", minVersion: "1.1.0", maxVersion: "1.2.4" }],
```

`minVersion`/`maxVersion` are marketing versions — `MARKETING_VERSION` on iOS,
`versionName` on Android — and `minBuild`/`maxBuild` are the integers beside them
(`CURRENT_PROJECT_VERSION` and `versionCode`). All four bounds are inclusive, and
versions compare component-wise, so `1.10.0` sits above `1.9.0`. The two
platforms' numbers are unrelated — iOS is on 1.3.0 while Android is on 1.0.0 —
which is why a version range always sits inside a `platform` rather than beside a
list of them.

Two things to know before relying on it:

- **It doesn't reach builds already in the field.** The check runs on device, so
  it only works from the first release of each app that ships it. Anything older
  ignores `targets` and shows the notification to all of its users. Until both
  apps have shipped a build that understands the field, treat targeting as a
  narrowing of the *new* audience, not a guarantee about the whole one.
- **A malformed target drops the notification everywhere.** An unparseable
  `minVersion` takes the whole notification down on both platforms rather than
  quietly widening it back to everyone. `tsc` catches the shape; it can't catch
  `"1.3.0-beta"`.

An unrecognised `platform` isn't malformed — it just never matches, so a future
platform can be targeted without breaking either app as it stands.
