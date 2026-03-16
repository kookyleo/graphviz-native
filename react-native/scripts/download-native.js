#!/usr/bin/env node

/**
 * Download prebuilt native libraries for React Native from GitHub Releases.
 * Runs automatically on `npm install` via postinstall hook.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const { execSync } = require('child_process');

// Read version from package.json
const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json'), 'utf-8'));
const version = pkg.version;
const tag = `v${version}`;

const GITHUB_REPO = 'nicekook/graphviz-anywhere';
const RELEASE_URL = `https://github.com/${GITHUB_REPO}/releases/download/${tag}`;

const downloads = [
  {
    name: 'graphviz-native-ios.tar.gz',
    dest: path.join(__dirname, '../ios/Frameworks'),
  },
  {
    name: 'graphviz-native-macos-universal.tar.gz',
    dest: path.join(__dirname, '../macos/Frameworks'),
  },
  {
    name: 'graphviz-native-windows-x86_64.zip',
    dest: path.join(__dirname, '../windows/Frameworks'),
  },
  {
    name: 'graphviz-native-android-arm64-v8a.tar.gz',
    dest: path.join(__dirname, '../android/libs/arm64-v8a'),
  },
  {
    name: 'graphviz-native-android-armeabi-v7a.tar.gz',
    dest: path.join(__dirname, '../android/libs/armeabi-v7a'),
  },
  {
    name: 'graphviz-native-android-x86_64.tar.gz',
    dest: path.join(__dirname, '../android/libs/x86_64'),
  },
];

async function downloadFile(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https.get(url, (response) => {
      response.pipe(file);
      file.on('finish', () => {
        file.close(resolve);
      });
    }).on('error', reject);
  });
}

async function main() {
  console.log(`📦 Downloading prebuilt libraries for v${version}...`);

  for (const { name, dest } of downloads) {
    const url = `${RELEASE_URL}/${name}`;
    const tempFile = path.join(__dirname, '../../', name);

    try {
      // Create destination directory
      fs.mkdirSync(dest, { recursive: true });

      console.log(`  ⬇️  ${name}`);

      // Download
      await downloadFile(url, tempFile);

      // Extract
      if (name.endsWith('.tar.gz')) {
        execSync(`tar -xzf "${tempFile}" -C "${dest}"`, { stdio: 'inherit' });
      } else if (name.endsWith('.zip')) {
        execSync(`unzip -o "${tempFile}" -d "${dest}"`, { stdio: 'inherit' });
      }

      // Cleanup
      fs.unlinkSync(tempFile);
      console.log(`  ✓ ${name}`);
    } catch (error) {
      console.warn(`  ⚠️  Failed to download ${name}: ${error.message}`);
      // Continue with other downloads on error
    }
  }

  console.log('✨ Done!');
}

main().catch((error) => {
  console.error('❌ Error:', error);
  process.exit(1);
});
