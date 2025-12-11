#!/usr/bin/env node
// Build script for Google Slides Tracker extension
// Builds extension for Chrome, Firefox, and Safari

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIST = path.join(ROOT, 'dist');

const BROWSERS = {
  chrome: 'manifest.chrome.json',
  firefox: 'manifest.firefox.json',
  safari: 'manifest.chrome.json' // Safari uses Chrome manifest as base
};

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function copyFile(src, dest) {
  fs.copyFileSync(src, dest);
}

function copyDir(src, dest) {
  ensureDir(dest);
  const entries = fs.readdirSync(src, { withFileTypes: true });

  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);

    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      copyFile(srcPath, destPath);
    }
  }
}

function cleanDir(dir) {
  if (fs.existsSync(dir)) {
    fs.rmSync(dir, { recursive: true });
  }
}

function build(browser) {
  console.log(`\nBuilding for ${browser}...`);

  const browserDist = path.join(DIST, browser);

  // Clean previous build
  cleanDir(browserDist);
  ensureDir(browserDist);

  // Copy source files
  copyDir(path.join(ROOT, 'src'), path.join(browserDist, 'src'));
  copyDir(path.join(ROOT, 'icons'), path.join(browserDist, 'icons'));

  // Copy browser-specific manifest
  const manifestName = BROWSERS[browser];
  const manifestSrc = path.join(ROOT, 'manifests', manifestName);
  const manifestDest = path.join(browserDist, 'manifest.json');

  if (!fs.existsSync(manifestSrc)) {
    console.error(`Error: Manifest not found: ${manifestSrc}`);
    process.exit(1);
  }

  copyFile(manifestSrc, manifestDest);

  console.log(`  Built ${browser} extension in: ${browserDist}`);
  return browserDist;
}

function main() {
  const args = process.argv.slice(2);
  const targetBrowsers = args.length > 0 ? args : Object.keys(BROWSERS);

  console.log('Google Slides Tracker - Extension Builder');
  console.log('=========================================');

  for (const browser of targetBrowsers) {
    if (!BROWSERS[browser]) {
      console.error(`Unknown browser: ${browser}`);
      console.log(`Available browsers: ${Object.keys(BROWSERS).join(', ')}`);
      process.exit(1);
    }
    build(browser);
  }

  console.log('\n=========================================');
  console.log('Build complete!\n');

  console.log('Installation instructions:');
  console.log('\nChrome/Edge:');
  console.log('  1. Open chrome://extensions (or edge://extensions)');
  console.log('  2. Enable "Developer mode"');
  console.log('  3. Click "Load unpacked"');
  console.log(`  4. Select: ${path.join(DIST, 'chrome')}`);

  console.log('\nFirefox:');
  console.log('  1. Open about:debugging#/runtime/this-firefox');
  console.log('  2. Click "Load Temporary Add-on"');
  console.log(`  3. Select: ${path.join(DIST, 'firefox', 'manifest.json')}`);

  console.log('\nSafari:');
  console.log('  1. Run: npm run build:safari');
  console.log('  2. Open the Xcode project in dist/safari-xcode');
  console.log('  3. Build and run in Xcode');
  console.log('  4. Enable extension in Safari Preferences > Extensions');
}

main();
