// End-to-end check in a real browser: plays Chapter 1 through the UI by
// pressing buttons the way a player would, and checks accessibility basics.
// Run: node tests/browser-smoke.mjs   (needs Playwright + Chromium)
// Set SHOT_DIR=/some/folder to also save screenshots.
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../www/', import.meta.url));
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };
const server = createServer(async (req, res) => {
  const path = normalize(join(root, decodeURIComponent(req.url.split('?')[0]) === '/' ? 'index.html' : req.url.split('?')[0]));
  if (!path.startsWith(root)) return res.writeHead(403).end();
  try {
    res.writeHead(200, { 'content-type': types[extname(path)] || 'application/octet-stream' });
    res.end(await readFile(path));
  } catch {
    res.writeHead(404).end();
  }
}).listen(0);
const url = `http://localhost:${server.address().port}/`;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));

const click = async (text) => {
  await page.getByRole('button', { name: text }).first().click();
  await page.waitForTimeout(60);
};
// Press Continue / End conversation until the conversation needs a real choice.
const continueAll = async () => {
  for (let i = 0; i < 10; i++) {
    const c = page.getByRole('button', { name: /^1\. (Continue|End conversation)$/ });
    if (!(await c.count())) return;
    await c.first().click();
    await page.waitForTimeout(60);
  }
};
const focusedText = () => page.evaluate(() => document.activeElement?.textContent?.slice(0, 80));

async function a11yAudit(label) {
  const issues = await page.evaluate(() => {
    const out = [];
    document.querySelectorAll('button').forEach((b) => {
      if (!b.textContent.trim() && !b.getAttribute('aria-label')) out.push('button without a name');
    });
    if (document.querySelectorAll('h1').length !== 1) out.push(`expected 1 h1, got ${document.querySelectorAll('h1').length}`);
    document.querySelectorAll('input, select').forEach((i) => {
      if (!i.id || !document.querySelector(`label[for="${i.id}"]`)) out.push(`unlabelled ${i.tagName}`);
    });
    const ids = [...document.querySelectorAll('[id]')].map((e) => e.id);
    if (new Set(ids).size !== ids.length) out.push('duplicate ids');
    return out;
  });
  if (issues.length) throw new Error(`${label}: ${issues.join(', ')}`);
}

await page.goto(url);
await page.waitForTimeout(200);
await a11yAudit('first run');
await click('I use a screen reader');
await a11yAudit('title');
await click('How to play');
await a11yAudit('help');
await click('Back');
await click('Settings');
await a11yAudit('settings');
await click('Back');
await click('New game');
await page.waitForTimeout(100);
console.log('Focused after new game:', await focusedText());
await a11yAudit('game');
if (process.env.SHOT_DIR) await page.screenshot({ path: `${process.env.SHOT_DIR}/game.png` });

await click('Police radio');
await click('Review the call notes');
await click('Back to the room');
await click('Glovebox');
await click('Open the glovebox');
await click('Back to the room');
await click('Step out into the rain');
await click('North: Main entrance');
await click('Front desk');
await click('Take the facility radio');
console.log('Focused after taking radio:', await focusedText());
await click('1. Police');
await continueAll();
await click('All right');
await continueAll();
await click('East: Security office');
await click('Emergency power panel');
await click('Pull the emergency power lever');
await click('help');
await continueAll();
// Wait for dispatch by looking around.
for (let i = 0; i < 20; i++) {
  if (await page.getByRole('heading', { name: 'Respond' }).count()) break;
  await click('Look around');
}
await click('On scene');
await continueAll();
await click('Call on the facility radio');
await click('Who are you?');
await continueAll();
await click('open the elevator');
await continueAll();
await click('Signing off');
await click('West: Reception lobby');
await click('North: Main corridor');
await click('North: Elevator');
await page.waitForTimeout(100);
const h1 = await page.locator('h1').textContent();
console.log('Heading at the end:', h1);
if (h1 !== 'End of Chapter 1') throw new Error('did not reach the chapter end');
await a11yAudit('chapter end');
if (process.env.SHOT_DIR) await page.screenshot({ path: `${process.env.SHOT_DIR}/end.png` });

await click('Continue to Chapter 2');
await page.waitForTimeout(100);
console.log('Chapter 2 heading:', await page.locator('h1').textContent());
if ((await page.locator('h1').textContent()) !== 'Sublevel 1, elevator landing') throw new Error('chapter 2 did not start');
await a11yAudit('chapter 2');
await continueAll();
await click('On my way');
await continueAll();
await click('North: Laboratory corridor');
await click('North: Preservation lab');
await click('Glowing capsule');
await click('Examine');
console.log('Emily found:', (await page.locator('#beat').textContent()).includes('She is alive'));
await click('Back to the room');
await click('Check Emily');
console.log('Monitor:', (await page.locator('#beat').textContent()).slice(0, 90));
await click('Pause menu');
await click('Quit to main menu');
await click('Quit to main menu');
await click('Continue');
console.log('After continue, heading:', await page.locator('h1').textContent());
if ((await page.locator('h1').textContent()) !== 'Preservation lab') throw new Error('continue did not restore chapter 2');
await page.keyboard.press('Escape');
console.log('After Escape, heading:', await page.locator('h1').textContent());
await click('Save game');
await click('Slot 1: empty');
await page.waitForTimeout(100);
console.log('Slot 1 now:', await page.getByRole('button', { name: /^Slot 1/ }).textContent());
await click('Back');
await click('Resume');
await click('Journal');
await a11yAudit('journal');
await click('Dispatch call notes');
console.log('Reader heading:', await page.locator('h1').textContent());
await click('Back to journal');
await click('Back');
console.log('Back in game:', await page.locator('h1').textContent());

await browser.close();
server.close();
if (errors.length) {
  console.error('Browser errors:\n' + errors.join('\n'));
  process.exit(1);
}
console.log('Browser smoke test passed.');
