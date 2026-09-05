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

Everyone gets the same list. There is no targeting, no rollout percentage and no
per-client filtering — the worker sorts by `priority` and serves. Expiry, the
link allowlist and remembering dismissals are the clients' job.

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
