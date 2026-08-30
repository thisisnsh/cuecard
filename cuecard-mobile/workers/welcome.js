export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname !== "/welcome" && url.pathname !== "/v2/welcome") {
      return new Response("Not Found", { status: 404 });
    }

    if (request.method !== "POST") {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: { Allow: "POST" },
      });
    }

    // Compatibility shim for released app versions. Welcome emails have been
    // retired, but returning success avoids unnecessary client-side errors.
    return new Response(null, { status: 204 });
  },
};
