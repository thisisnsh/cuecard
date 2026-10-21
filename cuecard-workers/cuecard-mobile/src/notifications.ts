import type { Notification } from "./types";

// Everything the apps show. An empty list is the normal, quiet state.
// Adding one here plus a deploy is the whole publishing flow; see README.md.
export const NOTIFICATIONS: Notification[] = [
  {
    id: "ios-update-from-1.5-2026-09",
    surface: "homeBanner",
    severity: "info",
    priority: 10,
    title: "Introducing Cards",
    body: "Split your script into cue cards and swipe through them as you speak.",
    actions: [
      { kind: "appStore", label: "Update" },
      { kind: "dismiss", label: "Later" },
    ],
    targets: [{ platform: "ios", maxVersion: "1.5.0" }],
    expiresAt: "2026-10-31T00:00:00Z",
  },
  {
    id: "feedback-95efa0d9",
    surface: "homeBanner",
    severity: "info",
    title: "Help make CueCard better",
    body: "Got an idea or found a bug? It takes a minute.",
    actions: [
      { kind: "openURL", label: "Tell us", url: "https://forms.gle/eQnYdfxJXu3uHHx76" },
      { kind: "dismiss", label: "Not now" },
    ],
    minInstallAgeDays: 3,
    expiresAt: "2026-12-31T00:00:00Z",
  },
];
