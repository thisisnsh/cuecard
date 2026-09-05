/**
 * POST /welcome, POST /v2/welcome
 *
 * Welcome emails are retired. Released builds still call this, so answer 204
 * rather than let them surface an error.
 */
export function handleWelcome(request) {
  if (request.method !== "POST") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: { Allow: "POST" },
    });
  }

  return new Response(null, { status: 204 });
}
