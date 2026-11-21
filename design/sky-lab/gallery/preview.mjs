#!/usr/bin/env node
// Preview the assembled gallery as the artifact host would wrap it, and screenshot it.
//   node gallery/preview.mjs <out-dir> [--dist dist-2] [--serve]
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const here = path.dirname(fileURLToPath(import.meta.url));
const out = process.argv[2] || path.join(here, 'dist/preview');
const distAt = process.argv.indexOf('--dist');
const dist = distAt > 0 ? process.argv[distAt + 1] : 'dist';
const types = { '.webp': 'image/webp', '.html': 'text/html; charset=utf-8' };
const skeleton = (body) => `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"><style>:root{color-scheme:light}body{margin:0;font:14px system-ui}img{max-width:100%}[hidden]{display:none!important}</style></head><body>${body}</body></html>`;
const server = http.createServer((request, response) => {
  const url = new URL(request.url, 'http://x');
  if (url.pathname === '/') { response.writeHead(200, { 'content-type': types['.html'] }); response.end(skeleton(fs.readFileSync(path.join(here, dist, 'index.html'), 'utf8'))); return; }
  const file = path.join(here, decodeURIComponent(url.pathname));
  if (!file.startsWith(here) || !fs.existsSync(file)) { response.writeHead(404); response.end(); return; }
  response.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(response);
});
server.listen(process.argv.includes('--serve') ? 8378 : 0, '127.0.0.1', async () => {
  const origin = `http://127.0.0.1:${server.address().port}/`;
  if (process.argv.includes('--serve')) { console.log(origin); return; }
  const { chromium } = createRequire(import.meta.url)('playwright');
  const browser = await chromium.launch();
  fs.mkdirSync(out, { recursive: true });
  for (const [name, width, height, scheme] of [['desk-dark', 1280, 900, 'dark'], ['desk-light', 1280, 900, 'light'], ['phone-dark', 400, 800, 'dark']]) {
    const page = await browser.newPage({ viewport: { width, height }, colorScheme: scheme, deviceScaleFactor: 1 });
    const problems = [];
    page.on('console', (m) => { if (m.type() === 'error') problems.push(m.text()); });
    page.on('pageerror', (e) => problems.push(String(e)));
    await page.goto(origin, { waitUntil: 'networkidle' });
    // Walk the page so lazy images load, as a reader scrolling would.
    await page.evaluate(async () => {
      for (let y = 0; y < document.documentElement.scrollHeight; y += 500) { window.scrollTo(0, y); await new Promise((r) => setTimeout(r, 120)); }
      window.scrollTo(0, 0);
    });
    await page.waitForLoadState('networkidle');
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    await page.screenshot({ path: path.join(out, `${name}.png`), fullPage: true });
    console.log(name, 'overflow-x', overflow, problems.length ? problems.slice(0, 5) : 'no errors');
    await page.close();
  }
  await browser.close();
  server.close();
});
