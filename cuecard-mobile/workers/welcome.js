const FIREBASE_PROJECT_ID = "cuecard-mobile";
const JWKS_URL =
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

let cachedJwks = null;
let cachedJwksExpiry = 0;

async function fetchJwks() {
  if (cachedJwks && Date.now() < cachedJwksExpiry) {
    return cachedJwks;
  }

  const response = await fetch(JWKS_URL);
  if (!response.ok) {
    throw new Error("jwks_fetch_failed");
  }

  const jwks = await response.json();
  const maxAge = Number(
    (/max-age=(\d+)/.exec(response.headers.get("cache-control") || "") || [])[1] || 3600
  );

  cachedJwks = jwks;
  cachedJwksExpiry = Date.now() + maxAge * 1000;
  return jwks;
}

function base64UrlToBytes(value) {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function decodeJsonSegment(segment) {
  return JSON.parse(new TextDecoder().decode(base64UrlToBytes(segment)));
}

async function verifyIdToken(token) {
  const parts = token.split(".");
  if (parts.length !== 3) {
    return null;
  }

  let header;
  try {
    header = decodeJsonSegment(parts[0]);
  } catch {
    return null;
  }

  if (header.alg !== "RS256" || !header.kid) {
    return null;
  }

  const jwks = await fetchJwks();
  const jwk = (jwks.keys || []).find((candidate) => candidate.kid === header.kid);
  if (!jwk) {
    return null;
  }

  const key = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );

  const signatureIsValid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    base64UrlToBytes(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`)
  );
  if (!signatureIsValid) {
    return null;
  }

  let claims;
  try {
    claims = decodeJsonSegment(parts[1]);
  } catch {
    return null;
  }

  const now = Math.floor(Date.now() / 1000);
  if (claims.aud !== FIREBASE_PROJECT_ID) return null;
  if (claims.iss !== `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`) return null;
  if (typeof claims.exp !== "number" || claims.exp <= now) return null;
  if (typeof claims.iat !== "number" || claims.iat > now + 300) return null;
  if (!claims.sub) return null;

  return claims;
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // /welcome is the original unauthenticated endpoint that app builds already
    // in the store still call. /v2/welcome takes the recipient from a verified
    // Firebase ID token rather than from the request body.
    const isLegacy = url.pathname === "/welcome";
    const isVerified = url.pathname === "/v2/welcome";

    if (!isLegacy && !isVerified) {
      return new Response("Not Found", { status: 404 });
    }

    if (request.method !== "POST") {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: { Allow: "POST" },
      });
    }

    let claims = null;
    if (isVerified) {
      const authorization = request.headers.get("Authorization") || "";
      const idToken = authorization.startsWith("Bearer ")
        ? authorization.slice("Bearer ".length).trim()
        : "";

      if (!idToken) {
        return new Response("Unauthorized", { status: 401 });
      }

      try {
        claims = await verifyIdToken(idToken);
      } catch (error) {
        console.log("welcome_token_error", error?.message || "verification_failed");
        return new Response("Service Unavailable", { status: 503 });
      }

      if (!claims) {
        return new Response("Unauthorized", { status: 401 });
      }
    }

    let payload;
    try {
      payload = await request.json();
    } catch (error) {
      console.log("welcome_payload_error", error?.message || "invalid_json");
      return new Response("Bad Request", { status: 400 });
    }

    // On the verified route the recipient comes from the token, never the body.
    const email = claims ? claims.email : payload.email;

    if (!email) {
      return new Response("Bad Request: email is required", { status: 400 });
    }

    const fullName = (claims && claims.name) || payload.name || payload.displayName;
    const firstName = fullName ? String(fullName).split(" ")[0] : "there";

    try {
      const emailResponse = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.RESEND_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: "CueCard Teleprompter <support@cuecard.dev>",
          to: [email],
          subject: "Welcome to CueCard Teleprompter!",
          html: getWelcomeEmailHtml(firstName),
        }),
      });

      if (!emailResponse.ok) {
        const errorText = await emailResponse.text();
        console.log("welcome_email_error", errorText);
        return new Response("Failed to send email", { status: 500 });
      }

      console.log("welcome_email_sent", claims ? claims.sub : "legacy");
      return new Response("OK", { status: 200 });
    } catch (error) {
      console.log("welcome_email_exception", error?.message || "unknown_error");
      return new Response("Internal Server Error", { status: 500 });
    }
  },
};

function getWelcomeEmailHtml(firstName) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="X-UA-Compatible" content="IE=edge">
  <title>CueCard Teleprompter</title>
</head>
<body style="margin: 0; padding: 0; background-color: #ffffff; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
  <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="border-collapse: collapse;">
    <tr>
      <td align="center" style="padding: 40px 20px;">
        <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="border-collapse: collapse; max-width: 480px;">

          <!-- Logo -->
          <tr>
            <td align="left" style="padding-bottom: 32px;">
              <img src="https://cuecard.dev/assets/logo-circle.png" alt="CueCard" width="48" height="48" style="display: block; border-radius: 50%;">
            </td>
          </tr>

          <!-- Main Content -->
          <tr>
            <td style="background-color: #ffffff;">
              <h1 style="margin: 0 0 16px; font-size: 24px; font-weight: 700; color: #000000;">
                Welcome to CueCard
              </h1>

              <p style="margin: 0 0 24px; font-size: 16px; line-height: 1.6; color: #555555;">
                Hey ${escapeHtml(firstName)}, thanks for signing up.
              </p>

              <p style="margin: 0 0 20px; font-size: 16px; line-height: 1.6; color: #555555;">
                CueCard is a floating teleprompter that displays your notes above any app. Stay on script while recording videos, presenting, or streaming.
              </p>

              <!-- Features -->
              <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="border-collapse: collapse; margin-bottom: 28px;">
                <tr>
                  <td style="padding: 12px 0; border-bottom: 1px solid #eeeeee;">
                    <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="border-collapse: collapse;">
                      <tr>
                        <td width="28" valign="top" style="color: #febc2e; font-weight: 700; font-size: 15px;">1.</td>
                        <td style="font-size: 15px; line-height: 1.5; color: #555555;">
                          <strong style="color: #000000;">Auto-scroll your script</strong> at a comfortable pace so you can stay focused.
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr>
                  <td style="padding: 12px 0; border-bottom: 1px solid #eeeeee;">
                    <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="border-collapse: collapse;">
                      <tr>
                        <td width="28" valign="top" style="color: #febc2e; font-weight: 700; font-size: 15px;">2.</td>
                        <td style="font-size: 15px; line-height: 1.5; color: #555555;">
                          <strong style="color: #000000;">Floats over all apps</strong> including Camera, Instagram, TikTok, and YouTube.
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr>
                  <td style="padding: 12px 0;">
                    <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="border-collapse: collapse;">
                      <tr>
                        <td width="28" valign="top" style="color: #febc2e; font-weight: 700; font-size: 15px;">3.</td>
                        <td style="font-size: 15px; line-height: 1.5; color: #555555;">
                          <strong style="color: #000000;">Customize font size and speed</strong> for comfortable reading.
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <!-- CTA Button -->
              <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="border-collapse: collapse; margin-bottom: 24px;">
                <tr>
                  <td align="left">
                    <a href="https://cuecard.dev/mobile" style="display: inline-block; padding: 14px 28px; background-color: #000000; color: #ffffff; text-decoration: none; font-size: 15px; font-weight: 600; border-radius: 8px;">
                      Visit Website
                    </a>
                  </td>
                </tr>
              </table>

              <p style="margin: 0; font-size: 14px; line-height: 1.6; color: #555555;">
                Also available on <a href="https://cuecard.dev" style="color: #000000; text-decoration: underline;">Mac and Windows</a>.
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding-top: 32px; border-top: 1px solid #eeeeee;">
              <p style="margin: 0 0 12px; font-size: 13px; color: #888888;">
                Questions? Just reply to this email.
              </p>
              <p style="margin: 0 0 12px; font-size: 13px; color: #888888;">
                <a href="https://cuecard.dev" style="color: #888888; text-decoration: underline;">CueCard</a> ·
                <a href="https://cuecard.dev/privacy" style="color: #888888; text-decoration: underline;">Privacy Policy</a> ·
                <a href="https://github.com/thisisnsh/cuecard" style="color: #888888; text-decoration: underline;">GitHub</a> ·
                <a href="https://github.com/thisisnsh/cuecard/blob/main/LICENSE" style="color: #888888; text-decoration: underline;">MIT License</a>
              </p>
              <p style="margin: 0; font-size: 12px; color: #888888;">
                &copy; 2026 Nishant Hada
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}
