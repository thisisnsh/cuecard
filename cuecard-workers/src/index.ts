// CueCard mobile worker — cuecard-mobile.thisisnsh.workers.dev
//
// Serves the notifications the mobile apps show. The list is hardcoded, so
// publishing one is an edit plus a deploy. See README.md.
import { handleNotifications } from "./endpoints/notifications";
import { handleWelcome } from "./endpoints/welcome";

export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/v2/notifications") return handleNotifications(request);
    if (url.pathname === "/welcome" || url.pathname === "/v2/welcome") return handleWelcome(request);

    return new Response("Not Found", { status: 404 });
  },
};
