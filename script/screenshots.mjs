// Regenerates the README screenshots from the running HELIOS instance.
//
// Usage: HELIOS_ADMIN_PASSWORD=… bun run screenshots [url]

import { chromium } from 'playwright';
import { spawn } from 'node:child_process';

const BASE_URL = process.argv[2] ?? 'http://raspi.fritz.box:3999';
const VIEWPORT = { width: 1280, height: 800 };
const SCALE = 2;

const PAGES = [
  {
    file: 'screenshot-configuration.png',
    path: '/sensors',
    waitFor: 'text=INVERTER',
  },
  {
    file: 'screenshot-services.png',
    path: '/services',
    waitFor: 'text=Dashboard',
  },
  {
    file: 'screenshot-backup.png',
    path: '/backups',
    // The page paints an empty shell first and lazy-loads this frame.
    waitFor: 'turbo-frame#backups-content section',
  },
];

const password = process.env.HELIOS_ADMIN_PASSWORD;
if (!password) {
  console.error('HELIOS_ADMIN_PASSWORD is not set');
  process.exit(1);
}

// Playwright writes an unoptimized 24-bit PNG. Quantizing it to a 256-color
// palette halves the file size, with no visible loss on flat UI surfaces.
// Needs ImageMagick, see the Brewfile.
function writeOptimized(buffer, file) {
  return new Promise((resolve, reject) => {
    const magick = spawn(
      'magick',
      [
        'png:-',
        '-strip',
        '-colors',
        '256',
        '-define',
        'png:compression-level=9',
        `PNG8:${file}`,
      ],
      { stdio: ['pipe', 'inherit', 'inherit'] },
    );

    magick.on('error', reject);
    magick.on('close', (code) =>
      code === 0 ? resolve() : reject(new Error(`magick exited with ${code}`)),
    );

    magick.stdin.end(buffer);
  });
}

const browser = await chromium.launch();
// A fresh context carries no preferences cookie, so the locale comes from
// Accept-Language and the screenshots stay English.
const context = await browser.newContext({
  viewport: VIEWPORT,
  deviceScaleFactor: SCALE,
  locale: 'en-US',
});
const page = await context.newPage();

await page.goto(`${BASE_URL}/session/new`);
await page.fill('#password', password);
await page.click('button[type=submit]');
await page.waitForURL(/\/services/);

for (const { file, path, waitFor } of PAGES) {
  await page.goto(BASE_URL + path);
  await page.waitForSelector(waitFor);
  await page.waitForLoadState('networkidle');

  // Live values (host stats, sensor readings, container health) arrive over
  // ActionCable after the initial render.
  await page.waitForTimeout(3000);

  await writeOptimized(await page.screenshot(), file);

  console.log(`Wrote ${file}`);
}

await browser.close();
