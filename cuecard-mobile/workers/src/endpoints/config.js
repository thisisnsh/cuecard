import { SCHEMA, FLAGS } from "../schema.js";
import { MESSAGES } from "../messages.js";
import { isEligible } from "../eligibility.js";

/** The client shape, read from the query string. Everything has a safe default. */
function clientFrom(params) {
  return {
    platform: (params.get("p") || "").toLowerCase(),
    version: params.get("v") || "0.0.0",
    build: parseInt(params.get("b"), 10) || 0,
    locale: params.get("l") || "en",
  };
}

/** The payload for one client: flags narrowed to its platform, plus eligible messages. */
export function configFor(client) {
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

/** GET /v2/config */
export function handleConfig(request, url) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: { Allow: "GET" },
    });
  }

  return new Response(JSON.stringify(configFor(clientFrom(url.searchParams))), {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      // Five minutes is short enough that pulling a bad message is quick and long
      // enough that the edge absorbs the traffic. The response is derived entirely
      // from the query string, so it caches per client shape.
      "Cache-Control": "public, max-age=300",
    },
  });
}
