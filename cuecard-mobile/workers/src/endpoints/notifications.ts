import { NOTIFICATIONS } from "../notifications";
import type { NotificationsResponse, Schema } from "../types";

const SCHEMA: Schema = 1;

// GET /v2/notifications
//
// The same list for everyone — no targeting, no per-client filtering. Clients
// handle expiry, dismissal and the link allowlist themselves.
export function handleNotifications(request: Request): Response {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: { Allow: "GET" },
    });
  }

  const body: NotificationsResponse = {
    schema: SCHEMA,
    // Copied before sorting so the module-level list keeps its authored order.
    notifications: [...NOTIFICATIONS].sort((a, b) => (b.priority ?? 0) - (a.priority ?? 0)),
  };

  return new Response(JSON.stringify(body), {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      // Five minutes is short enough that pulling a bad notification is quick
      // and long enough that the edge absorbs the traffic.
      "Cache-Control": "public, max-age=300",
    },
  });
}
