// CueCard worker — cuecard.thisisnsh.workers.dev
//
// Proxies the website's GitHub releases request with GITHUB_TOKEN so visitors don't hit
// GitHub's unauthenticated rate limit. See ../README.md.

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

    // Allowed endpoints (whitelist for security), limited to the CueCard repo
    const allowedPaths = [
      /^\/repos\/thisisnsh\/cuecard\/releases$/, // used by the website's download section
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
