// Renders Tuk's still images and the app icon from LIFTR/Resources/Tuk/tuk.html.
// The app shows these while the animated rig loads, for small avatars, and with Reduce Motion on.
//
// Run from the repo root after changing tuk.html (needs Node and Playwright with Chromium):
//   npm install --no-save playwright && npx playwright install chromium
//   node tools/render-tuk-stills.js

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const page = 'file://' + path.join(root, 'LIFTR/Resources/Tuk/tuk.html');
const catalog = path.join(root, 'LIFTR/Assets.xcassets');

function imageSet(name, file) {
  const dir = path.join(catalog, `${name}.imageset`);
  fs.mkdirSync(dir, { recursive: true });
  const contents = { images: [{ filename: file, idiom: 'universal', scale: '3x' }], info: { author: 'xcode', version: 1 } };
  fs.writeFileSync(path.join(dir, 'Contents.json'), JSON.stringify(contents, null, 2) + '\n');
  return path.join(dir, file);
}

(async () => {
  const browser = await chromium.launch();
  async function shot(query, size, scale, file, background) {
    const tab = await browser.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: scale });
    await tab.goto(`${page}?${query}&static=1`);
    if (background) await tab.addStyleTag({ content: `html,body{background:${background}!important}` });
    await tab.waitForTimeout(400);
    await tab.screenshot({ path: file, omitBackground: !background });
    await tab.close();
  }
  for (let stage = 1; stage <= 5; stage++) {
    await shot(`stage=${stage}&mode=loop`, 240, 3, imageSet(`Tuk${stage}`, `tuk${stage}.png`));
    await shot(`stage=${stage}&mode=head`, 64, 3, imageSet(`TukHead${stage}`, `tuk-head${stage}.png`));
  }
  // App icons must be opaque, so this one gets the avatar background.
  await shot('stage=2&mode=head', 1024, 1, path.join(catalog, 'AppIcon.appiconset/AppIcon.png'), '#E9EFE3');
  await browser.close();
})();
