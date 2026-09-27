/**
 * Cloudflare Worker - GitHub API Proxy
 *
 * This worker proxies requests to GitHub API with authentication,
 * avoiding rate limits and keeping your token secure.
 *
 * SETUP:
 * 1. Go to https://dash.cloudflare.com → Workers & Pages → Create Worker
 * 2. Paste this code
 * 3. Go to Settings → Variables → Add variable:
 *    - Name: GITHUB_TOKEN
 *    - Value: Your GitHub personal access token
 *    - Click "Encrypt" to secure it
 * 4. Deploy and note your worker URL (e.g., github-api.your-subdomain.workers.dev)
 * 5. (Optional) Add a custom domain like github-api.cuecard.live
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    // CORS headers for your website
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*', // Or restrict to 'https://cuecard.live'
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };

    // Handle preflight requests
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    // Only allow GET requests
    if (request.method !== 'GET') {
      return new Response('Method not allowed', {
        status: 405,
        headers: corsHeaders
      });
    }

    // Allowed endpoints (whitelist for security)
    // Restricted to the CueCard repository only, to prevent this proxy from
    // being abused to access arbitrary public GitHub repositories.
    const allowedPaths = [
      /^\/repos\/thisisnsh\/cuecard$/,           // /repos/thisisnsh/cuecard
      /^\/repos\/thisisnsh\/cuecard\/releases$/, // /repos/thisisnsh/cuecard/releases
    ];

    const isAllowed = allowedPaths.some(pattern => pattern.test(path));
    if (!isAllowed) {
      return new Response('Endpoint not allowed', {
        status: 403,
        headers: corsHeaders
      });
    }

    try {
      // Proxy to GitHub API with authentication
      const githubResponse = await fetch(`https://api.github.com${path}`, {
        headers: {
          'Authorization': `Bearer ${env.GITHUB_TOKEN}`,
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'CueCard-Website',
        },
      });

      const data = await githubResponse.text();

      return new Response(data, {
        status: githubResponse.status,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
          'Cache-Control': 'public, max-age=300', // Cache for 5 minutes
        },
      });
    } catch (error) {
      return new Response(JSON.stringify({ error: 'Failed to fetch from GitHub' }), {
        status: 500,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
        },
      });
    }
  },
};
