# Google Slides Tracker Extension

Browser extension that tracks Google Slides presentations and sends slide information to a local API endpoint.

## Features

- Detects when a Google Slides presentation is opened
- Tracks slide changes in both **edit mode** and **slideshow/presentation mode**
- Sends slide data to `localhost:3000/slides?query={slideInfo}`
- Works on Chrome, Firefox, Edge, and Safari

## API Payload

When a slide is opened or changed, the extension sends a GET request:

```
GET http://localhost:3000/slides?query={encodedJSON}
```

The `query` parameter contains URL-encoded JSON:

```json
{
  "presentationId": "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms",
  "slideId": "p3",
  "slideNumber": 3,
  "title": "My Presentation",
  "mode": "edit",
  "timestamp": 1702156800000,
  "url": "https://docs.google.com/presentation/d/.../edit#slide=id.p3"
}
```

## Installation

### Build the Extension

```bash
# Install dependencies (none required for now)
cd extension

# Build for all browsers
npm run build

# Or build for a specific browser
npm run build:chrome
npm run build:firefox
npm run build:safari
```

### Chrome / Edge

1. Run `npm run build`
2. Open `chrome://extensions` (Chrome) or `edge://extensions` (Edge)
3. Enable **Developer mode** (toggle in top-right)
4. Click **Load unpacked**
5. Select the `dist/chrome` folder

### Firefox

1. Run `npm run build`
2. Open `about:debugging#/runtime/this-firefox`
3. Click **Load Temporary Add-on**
4. Select `dist/firefox/manifest.json`

Note: Firefox temporary add-ons are removed when Firefox closes. For permanent installation, you need to sign the extension via [addons.mozilla.org](https://addons.mozilla.org).

### Safari

1. Run `npm run build:safari`
2. Open the generated Xcode project: `open dist/safari-xcode/SlidesTracker/SlidesTracker.xcodeproj`
3. Select your development team in Xcode
4. Build and run (Cmd+R)
5. Enable the extension in **Safari > Preferences > Extensions**

Note: Safari requires the extension to be packaged as a native app via Xcode.

## Development

### Project Structure

```
extension/
├── src/
│   ├── content/
│   │   └── content.js      # Main content script
│   ├── background/
│   │   └── background.js   # Service worker
│   └── popup/
│       ├── popup.html
│       ├── popup.js
│       └── popup.css
├── manifests/
│   ├── manifest.chrome.json
│   └── manifest.firefox.json
├── icons/
│   └── icon-*.png
├── scripts/
│   ├── build.js
│   └── safari-convert.sh
└── dist/                   # Built extensions
```

### Testing

1. Make sure your local server is running at `localhost:3000`
2. Add a `/slides` endpoint that accepts GET requests with a `query` parameter
3. Load the extension in your browser
4. Open any Google Slides presentation
5. Check the browser console and your server logs

### Server Example (Node.js)

```javascript
const express = require('express');
const app = express();

app.get('/slides', (req, res) => {
  const data = JSON.parse(decodeURIComponent(req.query.query));
  console.log('Slide change:', data);
  res.json({ received: true });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.listen(3000, () => {
  console.log('Server running on http://localhost:3000');
});
```

## Browser Compatibility

| Browser | Minimum Version | Notes |
|---------|-----------------|-------|
| Chrome  | 120+           | Primary target |
| Edge    | 120+           | Uses Chrome manifest |
| Firefox | 109+           | Manifest V3 |
| Safari  | 15.4+          | Requires Xcode |

## Publishing / Releasing

### Create Release Packages

```bash
npm run release
```

This creates ZIP files in the `releases/` folder ready for upload to browser stores.

### Chrome Web Store

1. Go to [Chrome Web Store Developer Dashboard](https://chrome.google.com/webstore/devconsole)
2. Pay one-time **$5 developer registration fee**
3. Click **New Item** → Upload `releases/slides-tracker-chrome-v*.zip`
4. Fill in store listing:
   - Name, description, screenshots
   - Category: Productivity
   - Privacy policy URL (required)
5. Submit for review (typically 1-3 business days)

### Microsoft Edge Add-ons

1. Go to [Microsoft Partner Center](https://partner.microsoft.com/dashboard/microsoftedge/)
2. Create Microsoft Partner account (free)
3. Click **Create new extension** → Upload the Chrome ZIP (same format)
4. Fill in listing details
5. Submit for review

### Firefox Add-ons (AMO)

1. Go to [Firefox Add-on Developer Hub](https://addons.mozilla.org/developers/)
2. Create Mozilla account (free)
3. Click **Submit a New Add-on**
4. Upload `releases/slides-tracker-firefox-v*.zip`
5. Choose distribution:
   - **Listed**: Published on AMO for anyone to install
   - **Self-hosted**: Sign-only, you distribute the file yourself
6. Fill in listing details
7. Submit for review (typically 1-7 days)

### Safari (Mac App Store)

1. **Requires Apple Developer Program membership** ($99/year)
2. Run `npm run build:safari` to create Xcode project
3. Open in Xcode: `open dist/safari-xcode/SlidesTracker/SlidesTracker.xcodeproj`
4. Configure signing with your Apple Developer team
5. Archive the app: Product → Archive
6. Upload to [App Store Connect](https://appstoreconnect.apple.com)
7. Submit for review

### Direct Distribution (No Store)

You can also distribute the extension files directly:

**Chrome/Edge users:**
1. Download and unzip the Chrome release
2. Go to `chrome://extensions`
3. Enable "Developer mode"
4. Click "Load unpacked" and select the unzipped folder

**Firefox users:**
1. Download the Firefox release
2. Go to `about:addons`
3. Click gear icon → "Install Add-on From File"
4. Select the ZIP file

Note: Direct distribution has limitations - Chrome will show warnings, and Firefox requires the extension to be signed.

## License

MIT
