# CueCard workers

One folder per Cloudflare Worker, named after the worker itself.

| Folder | URL | Purpose |
| --- | --- | --- |
| [`cuecard`](cuecard) | `cuecard.thisisnsh.workers.dev` | GitHub releases proxy for the website's download section |
| [`cuecard-mobile`](cuecard-mobile/README.md) | `cuecard-mobile.thisisnsh.workers.dev` | Notifications for the mobile and desktop apps |

Neither name can change: the website calls `cuecard`, and released app builds call
`cuecard-mobile`.

Deploy a worker by running this from its folder; it only deploys that one:

```
npx wrangler deploy
```

## cuecard

Only allows `GET /repos/thisisnsh/cuecard/releases` and forwards it to the GitHub
API with `GITHUB_TOKEN`. The token is a worker secret, set once with
`npx wrangler secret put GITHUB_TOKEN`; deploys keep it.
