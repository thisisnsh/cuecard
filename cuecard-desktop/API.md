# CueCard Notes API

CueCard reads Google Slides notes through its browser extension. Other presentation apps, such as Keynote, PowerPoint and Deckset, and your own scripts, can send their speaker notes to the desktop app over the same local server. The notes show up in the Live row of the sidebar and in the teleprompter, the same way Google Slides notes do. No Google account is needed.

The server listens on `http://127.0.0.1:3642`. It only accepts connections from your own computer.

The API is for apps and scripts, not web pages. CueCard refuses any request a browser sends: a request with an `Origin` or `Sec-Fetch-Site` header, or one addressed to a host other than `127.0.0.1` or `localhost`. Decks that run in a browser, such as Marp or Slidev exports, can't send their notes from the page itself.

## The token

Every request also has to carry a token. CueCard creates the token on first launch and keeps it in a file only your user account can read:

| Platform | Token file |
|----------|------------|
| macOS | `~/Library/Application Support/com.thisisnsh.cuecard/api-token` |
| Windows | `%APPDATA%\com.thisisnsh.cuecard\api-token` |

You can also copy it from **Settings → Other Presentation Apps → Notes API Token**.

Send it with each request as:

```
X-CueCard-Token: <token>
```

`Authorization: Bearer <token>` works too. `GET /health` needs no token. It answers `{"status": "ok", "server": "cuecard-desktop", "api": 1}`, and clients can use the `api` field to check that this version of CueCard has the notes API.

## Endpoints

Both take a JSON body (`Content-Type: application/json`).

### `POST /notes`: show these notes now

```json
{ "source": "keynote", "notes": "Welcome everyone…", "deck": "Talk.key", "title": "My Talk", "slide": 4, "slides": 20 }
```

| Field | Required | Meaning |
|-------|----------|---------|
| `source` | yes | The app sending the notes. CueCard shows it in place of "Google Slides". `keynote`, `powerpoint`, `deckset`, `libreoffice`, `pdfpc` and `presenterm` get their proper names. Any other value is shown exactly as you sent it. Case doesn't matter. |
| `notes` | yes | The speaker notes for the slide on screen. An empty string means the slide has none. |
| `deck` | no | The presentation's file name, or any name that identifies it. Defaults to `source`. |
| `title` | no | The name shown for the presentation. Defaults to `deck`. |
| `slide` | no | Which slide this is, counting from 1. If you leave it out, each call counts as a new slide and the teleprompter starts it from the top. |
| `slides` | no | How many slides the deck has, for "Slide 4 of 20". |

Call it every time the slide changes. Call it again with the same `slide` to update the notes in place, for example after editing them.

### `POST /notes/clear`: the presentation is over

```json
{ "source": "keynote" }
```

This takes the live notes down, but only if the notes on screen came from that `source`. One app ending its slideshow can't clear another app's notes, or Google Slides notes. A teleprompter that is already open stays open.

### Responses

On success: `{"received": true}`. `/notes/clear` also returns `"cleared": true` or `false`, depending on whether there was anything of yours to take down.

On failure: `{"error": "…"}` with status `400` (a missing or invalid field), `401` (no token, or the wrong one), `403` (the request came from a web page) or `503` (CueCard is still starting).

## Examples

```bash
TOKEN=$(cat ~/Library/Application\ Support/com.thisisnsh.cuecard/api-token)

curl -s http://127.0.0.1:3642/notes \
  -H "X-CueCard-Token: $TOKEN" -H "Content-Type: application/json" \
  -d '{"source": "keynote", "deck": "Talk.key", "slide": 1, "slides": 12, "notes": "Hello, world"}'

curl -s http://127.0.0.1:3642/notes/clear \
  -H "X-CueCard-Token: $TOKEN" -H "Content-Type: application/json" \
  -d '{"source": "keynote"}'
```

### Keynote

This script needs only the Python standard library. While Keynote is playing a slideshow, it checks twice a second and sends the notes each time the slide changes. It also sends them again every few seconds, so CueCard catches up if it restarts in the middle of a talk. When the slideshow stops, it clears the notes. It never opens Keynote itself. The first time it runs, macOS asks whether your terminal may control Keynote.

```python
#!/usr/bin/env python3
"""Send Keynote's presenter notes to CueCard while you present."""
import json, pathlib, subprocess, sys, time, urllib.request

TOKEN_FILE = pathlib.Path.home() / "Library/Application Support/com.thisisnsh.cuecard/api-token"
TOKEN = TOKEN_FILE.read_text().strip()
RESEND_EVERY = 5  # seconds
SCRIPT = """
if application id "com.apple.Keynote" is not running then return ""
tell application id "com.apple.Keynote"
  if not playing then return ""
  set d to front document
  set s to current slide of d
  return (name of d) & linefeed & (slide number of s) & linefeed & (count of slides of d) & linefeed & (presenter notes of s)
end tell
"""

def send(path, body):
    request = urllib.request.Request(
        "http://127.0.0.1:3642" + path,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "X-CueCard-Token": TOKEN},
    )
    urllib.request.urlopen(request, timeout=2).close()

last, sent_at, failing = None, 0.0, False
while True:
    out = subprocess.run(["osascript", "-e", SCRIPT], capture_output=True, text=True).stdout.rstrip("\n")
    changed = out != (last or "")
    stale = bool(out) and time.monotonic() - sent_at > RESEND_EVERY
    if changed or stale:
        try:
            if out:
                deck, slide, slides, notes = (out.split("\n", 3) + [""] * 3)[:4]
                title = deck[:-4] if deck.lower().endswith(".key") else deck
                send("/notes", {"source": "keynote", "deck": deck, "title": title,
                                "slide": int(slide), "slides": int(slides), "notes": notes})
            else:
                send("/notes/clear", {"source": "keynote"})
            last, sent_at = out or None, time.monotonic()
            if failing:
                print("CueCard is answering again.", file=sys.stderr)
            failing = False
        except OSError as error:
            if not failing:
                print("CueCard isn't answering, still trying:", error, file=sys.stderr)
            failing = True
    time.sleep(0.5)
```

Other apps work the same way. Read the current slide through the app's scripting interface or plugin API, call `/notes` each time it changes, and call `/notes/clear` when the presentation ends.
