// Renders the EventLens brand images from tool/brand/brand.html.
// Run from the repo root: NODE_PATH=$(npm root -g) node tool/brand/render.mjs
// then: dart run flutter_launcher_icons
// Needs Playwright with Chromium. Fonts are in tool/brand/fonts.
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// Loaded with require so a global Playwright install (NODE_PATH) works too.
const { chromium } = createRequire(import.meta.url)('playwright');

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');

// [element id, output file, scale, transparent background]
const outputs = [
  ['icon-square', 'assets/icon/icon.png', 2.56, false],
  ['icon-background', 'assets/icon/icon_background.png', 2.56, false],
  ['icon-foreground', 'assets/icon/icon_foreground.png', 2.56, true],
  ['icon-square', 'store/play_icon_512.png', 1.28, false],
  ['feature-graphic', 'store/feature_graphic_1024x500.png', 1, false],
  ['lockup-stacked', 'assets/brand/title_lockup.png', 3, true],
  ['icon-rounded', 'docs/brand/eventlens_icon_1024.png', 2.56, true],
  ['lockup-horizontal', 'docs/brand/eventlens_lockup_banner.png', 3, true],
  ['lockup-stacked', 'docs/brand/eventlens_lockup_stacked.png', 3, true],
  ['symbol-healing-heart', 'docs/brand/symbol_healing_heart.png', 4, true],
  ['symbol-banner', 'docs/brand/symbol_core_memory_banner.png', 4, true],
  ['title-screen', 'docs/brand/eventlens_title_screen.png', 3, false],
];

const browser = await chromium.launch();
for (const scale of [...new Set(outputs.map((o) => o[2]))]) {
  const page = await browser.newPage({ deviceScaleFactor: scale, viewport: { width: 1400, height: 1000 } });
  await page.goto('file://' + path.join(here, 'brand.html'));
  await page.waitForLoadState('networkidle');
  await page.evaluate(async () => {
    await document.fonts.load("400 34px 'Permanent Marker'");
    await document.fonts.load("700 18px 'Archivo Narrow'");
    await document.fonts.ready;
  });
  for (const [id, file, s, transparent] of outputs) {
    if (s !== scale) continue;
    await page.locator('#' + id).screenshot({ path: path.join(root, file), omitBackground: transparent });
    console.log('wrote', file);
  }
  await page.close();
}
// The one-page brand sheet shows the images above, so it comes last.
const sheet = await browser.newPage({ deviceScaleFactor: 1.5, viewport: { width: 1600, height: 1000 } });
await sheet.goto('file://' + path.join(here, 'sheet.html'));
await sheet.waitForLoadState('networkidle');
await sheet.evaluate(() => document.fonts.ready);
await sheet.locator('#sheet').screenshot({ path: path.join(root, 'docs/brand/eventlens_brand_sheet.png') });
console.log('wrote docs/brand/eventlens_brand_sheet.png');
await browser.close();
