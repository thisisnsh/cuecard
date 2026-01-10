export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname !== "/welcome") {
      return new Response("Not Found", { status: 404 });
    }

    if (request.method !== "POST") {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: {
          Allow: "POST"
        }
      });
    }

    let payload;
    try {
      payload = await request.json();
    } catch (error) {
      console.log("welcome_payload_error", error?.message || "invalid_json");
      return new Response("Bad Request", { status: 400 });
    }

    console.log("welcome_payload", JSON.stringify(payload));

    const { email, name } = payload;

    if (!email) {
      return new Response("Bad Request: email is required", { status: 400 });
    }

    const firstName = name ? name.split(" ")[0] : "there";

    try {
      const emailResponse = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.RESEND_API_KEY}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          from: "Cuecard <welcome@cuecard.dev>",
          to: [email],
          subject: "Welcome to Cuecard!",
          html: getWelcomeEmailHtml(firstName)
        })
      });

      if (!emailResponse.ok) {
        const errorText = await emailResponse.text();
        console.log("welcome_email_error", errorText);
        return new Response("Failed to send email", { status: 500 });
      }

      console.log("welcome_email_sent", email);
      return new Response("OK", { status: 200 });
    } catch (error) {
      console.log("welcome_email_exception", error?.message || "unknown_error");
      return new Response("Internal Server Error", { status: 500 });
    }
  }
};

function getWelcomeEmailHtml(firstName) {
  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Welcome to Cuecard</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f5f5f5;">
  <table role="presentation" style="width: 100%; border-collapse: collapse;">
    <tr>
      <td align="center" style="padding: 40px 20px;">
        <table role="presentation" style="width: 100%; max-width: 600px; border-collapse: collapse; background-color: #ffffff; border-radius: 12px; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">
          <!-- Header -->
          <tr>
            <td style="padding: 40px 40px 30px; text-align: center; background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%); border-radius: 12px 12px 0 0;">
              <h1 style="margin: 0; color: #ffffff; font-size: 28px; font-weight: 700;">Welcome to Cuecard!</h1>
            </td>
          </tr>

          <!-- Body -->
          <tr>
            <td style="padding: 40px;">
              <p style="margin: 0 0 20px; color: #374151; font-size: 16px; line-height: 1.6;">
                Hey ${firstName},
              </p>
              <p style="margin: 0 0 20px; color: #374151; font-size: 16px; line-height: 1.6;">
                Thanks for joining Cuecard! We're excited to help you learn smarter with AI-powered flashcards.
              </p>
              <p style="margin: 0 0 30px; color: #374151; font-size: 16px; line-height: 1.6;">
                Here's what you can do to get started:
              </p>

              <!-- Feature List -->
              <table role="presentation" style="width: 100%; border-collapse: collapse; margin-bottom: 30px;">
                <tr>
                  <td style="padding: 15px; background-color: #f9fafb; border-radius: 8px; margin-bottom: 10px;">
                    <table role="presentation" style="width: 100%; border-collapse: collapse;">
                      <tr>
                        <td style="width: 40px; vertical-align: top;">
                          <span style="display: inline-block; width: 28px; height: 28px; background-color: #6366f1; border-radius: 50%; text-align: center; line-height: 28px; color: white; font-weight: bold;">1</span>
                        </td>
                        <td style="vertical-align: top;">
                          <p style="margin: 0; color: #374151; font-size: 15px;"><strong>Create your first deck</strong> – Add flashcards manually or let AI generate them from your notes.</p>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr><td style="height: 10px;"></td></tr>
                <tr>
                  <td style="padding: 15px; background-color: #f9fafb; border-radius: 8px;">
                    <table role="presentation" style="width: 100%; border-collapse: collapse;">
                      <tr>
                        <td style="width: 40px; vertical-align: top;">
                          <span style="display: inline-block; width: 28px; height: 28px; background-color: #6366f1; border-radius: 50%; text-align: center; line-height: 28px; color: white; font-weight: bold;">2</span>
                        </td>
                        <td style="vertical-align: top;">
                          <p style="margin: 0; color: #374151; font-size: 15px;"><strong>Study with spaced repetition</strong> – Our smart algorithm helps you remember more in less time.</p>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr><td style="height: 10px;"></td></tr>
                <tr>
                  <td style="padding: 15px; background-color: #f9fafb; border-radius: 8px;">
                    <table role="presentation" style="width: 100%; border-collapse: collapse;">
                      <tr>
                        <td style="width: 40px; vertical-align: top;">
                          <span style="display: inline-block; width: 28px; height: 28px; background-color: #6366f1; border-radius: 50%; text-align: center; line-height: 28px; color: white; font-weight: bold;">3</span>
                        </td>
                        <td style="vertical-align: top;">
                          <p style="margin: 0; color: #374151; font-size: 15px;"><strong>Track your progress</strong> – See your learning streaks and mastery levels grow.</p>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <!-- CTA Button -->
              <table role="presentation" style="width: 100%; border-collapse: collapse;">
                <tr>
                  <td align="center">
                    <a href="https://cuecard.dev" style="display: inline-block; padding: 14px 32px; background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%); color: #ffffff; text-decoration: none; font-size: 16px; font-weight: 600; border-radius: 8px;">Start Learning</a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding: 30px 40px; background-color: #f9fafb; border-radius: 0 0 12px 12px; text-align: center;">
              <p style="margin: 0 0 10px; color: #6b7280; font-size: 14px;">
                Questions? Reply to this email or reach out at <a href="mailto:support@cuecard.dev" style="color: #6366f1; text-decoration: none;">support@cuecard.dev</a>
              </p>
              <p style="margin: 0; color: #9ca3af; font-size: 12px;">
                © ${new Date().getFullYear()} Cuecard. All rights reserved.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
  `.trim();
}
