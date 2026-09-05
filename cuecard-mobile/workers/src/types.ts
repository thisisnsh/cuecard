// The wire format for GET /v2/notifications.
// Mirrored by RemoteConfig.swift on iOS and RemoteConfig.kt on Android — change
// all three together.

// Payload version. Bump only for a breaking change to the shape below.
export type Schema = 1;

// Where a notification is drawn.
//   homeBanner   Card above the editor on the home screen.
//   settingsRow  Row at the top of Settings. Quieter; good for cross-promotion.
export type Surface = "homeBanner" | "settingsRow";

// Picks the accent colour. No behaviour attached.
export type Severity = "info" | "warning" | "critical";

// Up to 2 per notification.
//   openURL   The url must be on cuecard.dev or github.com, or the store the
//             client itself is on (apps.apple.com for iOS, play.google.com for
//             Android). Clients drop the whole notification otherwise.
//   appStore  Opens the app's own listing. Needs no url.
//   dismiss   Closes the notification.
export type Action =
  | { kind: "openURL"; label: string; url: string }
  | { kind: "appStore"; label: string }
  | { kind: "dismiss"; label: string };

// Who a notification is for. Enforced on device, not here — the worker still
// serves one list to everyone — so targeting only reaches builds that understand
// these fields. Anything already in the field ignores them and shows the
// notification to all of its users.
export interface Target {
  // Not a closed union on device: a platform a build doesn't recognise simply
  // never matches, so adding one here can't break something already shipped.
  platform: "ios" | "android";
  // Marketing version, inclusive on both ends. One to four numbers separated by
  // dots — "1.3" and "1.3.0" both parse, "1.3.0-beta" doesn't and drops the
  // whole notification. Compared component-wise, so 1.10.0 is above 1.9.0.
  minVersion?: string;
  maxVersion?: string;
  // CURRENT_PROJECT_VERSION on iOS, versionCode on Android. Inclusive.
  minBuild?: number;
  maxBuild?: number;
}

export interface Notification {
  // Stable and unique. Clients remember dismissals by it, so never reuse an id
  // for different copy — a returning id reads as one the user already dismissed.
  id: string;
  surface: Surface;
  severity: Severity;
  // One line. Shown in bold.
  title: string;
  // A sentence or two.
  body?: string;
  // Higher first. Each surface shows at most one, so a second notification only
  // appears once the first is gone. Absent counts as 0.
  priority?: number;
  actions?: Action[];
  // Defaults to true. A notification with no actions and no dismiss is one
  // nobody can close, so only turn this off for something genuinely temporary.
  dismissible?: boolean;
  // Show only to builds matching at least one of these. Absent or empty means
  // everyone, which is what every notification was before targeting existed.
  // iOS and Android version numbers are unrelated — iOS is on 1.3.0 while
  // Android is on 1.0.0 — which is why a version range always sits inside a
  // platform rather than beside a list of them.
  targets?: Target[];
  // ISO 8601. Enforced on device. Optional but strongly encouraged — it's what
  // stops a stale incident banner outliving the incident.
  expiresAt?: string;
}

export interface NotificationsResponse {
  schema: Schema;
  notifications: Notification[];
}
