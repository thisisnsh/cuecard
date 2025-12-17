#!/usr/bin/env node
// Release script - builds and packages CueCard extension for distribution

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const DIST = path.join(ROOT, 'dist');
const RELEASES = path.join(ROOT, 'releases');

// Read version from package.json
const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));
const VERSION = pkg.version;

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function createZip(sourceDir, outputPath) {
  // Remove existing zip if present
  if (fs.existsSync(outputPath)) {
    fs.unlinkSync(outputPath);
  }

  // Create zip using system command
  execSync(`cd "${sourceDir}" && zip -r "${outputPath}" . -x "*.DS_Store"`, {
    stdio: 'inherit'
  });
}

function main() {
  console.log(`\nCueCard Extension - Release Builder v${VERSION}`);
  console.log('='.repeat(50));

  // Build all extensions first
  console.log('\n1. Building extensions...');
  execSync('node scripts/build.js', { cwd: ROOT, stdio: 'inherit' });

  // Create releases directory
  ensureDir(RELEASES);

  // Package Chrome extension
  console.log('\n2. Packaging Chrome extension...');
  const chromeZip = path.join(RELEASES, `cuecard-extension-chrome-v${VERSION}.zip`);
  createZip(path.join(DIST, 'chrome'), chromeZip);
  console.log(`   Created: ${chromeZip}`);

  // Package Firefox extension
  console.log('\n3. Packaging Firefox extension...');
  const firefoxZip = path.join(RELEASES, `cuecard-extension-firefox-v${VERSION}.zip`);
  createZip(path.join(DIST, 'firefox'), firefoxZip);
  console.log(`   Created: ${firefoxZip}`);

  // Safari note
  console.log('\n4. Safari packaging...');
  console.log('   Safari requires Xcode to build the app.');
  console.log('   Run: npm run build:safari');
  console.log('   Then build in Xcode and export the app.');

  // Summary
  console.log('\n' + '='.repeat(50));
  console.log('Release packages created in: ' + RELEASES);
  console.log('\nFiles:');

  const files = fs.readdirSync(RELEASES).filter(f => f.endsWith('.zip'));
  files.forEach(f => {
    const stats = fs.statSync(path.join(RELEASES, f));
    const size = (stats.size / 1024).toFixed(1);
    console.log(`  - ${f} (${size} KB)`);
  });

  console.log('\n' + '='.repeat(50));
  console.log('PUBLISHING INSTRUCTIONS:');
  console.log('='.repeat(50));

  console.log('\nCHROME WEB STORE:');
  console.log('  1. Go to: https://chrome.google.com/webstore/devconsole');
  console.log('  2. Pay one-time $5 developer fee (if not already)');
  console.log('  3. Click "New Item" and upload the Chrome ZIP');
  console.log('  4. Fill in store listing details');
  console.log('  5. Submit for review (takes 1-3 days)');

  console.log('\nEDGE ADD-ONS:');
  console.log('  1. Go to: https://partner.microsoft.com/dashboard/microsoftedge/');
  console.log('  2. Create Microsoft Partner account (free)');
  console.log('  3. Upload the Chrome ZIP (Edge uses same format)');
  console.log('  4. Submit for review');

  console.log('\nFIREFOX ADD-ONS:');
  console.log('  1. Go to: https://addons.mozilla.org/developers/');
  console.log('  2. Create Mozilla Developer account (free)');
  console.log('  3. Click "Submit a New Add-on" and upload the Firefox ZIP');
  console.log('  4. Fill in add-on details');
  console.log('  5. Submit for review (takes 1-5 days)');

  console.log('\nSAFARI APP STORE:');
  console.log('  1. Requires Apple Developer account ($99/year)');
  console.log('  2. Build the app in Xcode');
  console.log('  3. Archive and upload to App Store Connect');
  console.log('  4. Submit for review');

  console.log('\nDIRECT DISTRIBUTION (no store):');
  console.log('  Users can install directly:');
  console.log('  - Chrome: Unzip and load unpacked in developer mode');
  console.log('  - Firefox: Load temporary add-on via about:debugging');
  console.log('');
}

main();
