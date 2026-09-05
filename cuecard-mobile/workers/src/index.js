/**
 * CueCard mobile worker — cuecard-mobile.thisisnsh.workers.dev
 *
 * Remote config for the mobile apps. Everything it serves is hardcoded, so
 * changing what the apps show is an edit here plus a deploy. See README.md.
 */
import { handleConfig } from "./endpoints/config.js";
import { handleWelcome } from "./endpoints/welcome.js";

export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === "/v2/config") return handleConfig(request, url);
    if (url.pathname === "/welcome" || url.pathname === "/v2/welcome") return handleWelcome(request);

    return new Response("Not Found", { status: 404 });
  },
};
