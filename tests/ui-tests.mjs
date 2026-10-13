// Browser tests: the real page in headless Chromium, at desktop and phone widths.
// Makes a locked page, saves it as an image, reads that image back, damages pages in
// the lab, and checks that hostile text is shown as text.
import { chromium } from 'playwright';
import { mkdir } from 'node:fs/promises';
import { serve } from './serve.mjs';

let checks = 0;
let failures = 0;
function check(cond, label) {
  checks++;
  if (!cond) {
    failures++;
    console.log(`  FAIL ${label}`);
  }
}

const server = await serve();
const url = `http://127.0.0.1:${server.address().port}/`;
const browser = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {});
await mkdir('docs', { recursive: true });

async function fresh(viewport) {
  const context = await browser.newContext({ viewport, acceptDownloads: true });
  const page = await context.newPage();
  const problems = [];
  page.on('console', (m) => m.type() === 'error' && problems.push(m.text()));
  page.on('pageerror', (e) => problems.push(String(e)));
  page.on('request', (r) => !r.url().startsWith(url) && !r.url().startsWith('blob:') && !r.url().startsWith('data:') && problems.push(`outside request: ${r.url()}`));
  await page.goto(url);
  await page.waitForSelector('html[data-ready="true"]');
  return { context, page, problems };
}

// Sets Damage Lab sliders and waits for the lab to run again.
async function setLab(page, values) {
  await page.evaluate((v) => {
    for (const [id, value] of Object.entries(v)) document.getElementById(id).value = String(value);
    document.getElementById('lab-status').textContent = '';
    document.getElementById('rotate').dispatchEvent(new Event('input', { bubbles: true }));
  }, values);
  await page.waitForFunction(() => document.querySelector('#lab-status').textContent.length > 0);
}

async function test(name, fn) {
  const before = failures;
  try {
    await fn();
  } catch (e) {
    failures++;
    console.log(`  ERROR ${e.message.split('\n')[0]}`);
  }
  console.log(`${failures === before ? 'ok  ' : 'FAIL'}  ${name}`);
}

const SECRET = 'Bank 2FA recovery: 4F7K-9QPA-2MZX\n<b>bold?</b> <img src=x onerror="window.pwned=1">';

await test('make a locked page, save it as an image, read it back', async () => {
  const { context, page, problems } = await fresh({ width: 1280, height: 900 });
  await page.fill('#secret', SECRET);
  await page.fill('#title', '<script>pwned=1</script> Kit');
  await page.fill('#passphrase', 'K7QF-2MZD-9XWA-TR4P-H6NB');
  await page.click('#make-button');
  await page.waitForSelector('#sheet svg');
  check(await page.locator('#sheet h3').textContent() === '<script>pwned=1</script> Kit', 'title shown as text');
  check(await page.locator('#sheet script, #sheet img').count() === 0, 'no markup from the title');
  check((await page.locator('#sheet .lock').textContent()) === 'LOCKED', 'locked badge');
  await page.screenshot({ path: 'docs/make-desktop.png', fullPage: true });

  const [download] = await Promise.all([page.waitForEvent('download'), page.click('#save-image')]);
  const png = await download.path();
  await page.click('#tab-read');
  await page.setInputFiles('#photo', png);
  await page.waitForFunction(() => !['', 'Reading…'].includes(document.querySelector('#read-status').textContent));
  check(!(await page.locator('#unlock').isHidden()), `page read from the saved image: ${await page.textContent('#read-status')}`);
  await page.fill('#unlock-pass', 'wrong passphrase');
  await page.click('#unlock button');
  await page.waitForSelector('#read-error:not([hidden])');
  check((await page.textContent('#read-error')).includes('Wrong passphrase'), 'wrong passphrase refused');
  await page.fill('#unlock-pass', 'K7QF-2MZD-9XWA-TR4P-H6NB');
  await page.click('#unlock button');
  await page.waitForSelector('#result:not([hidden])');
  check((await page.textContent('#result')) === SECRET, 'secret read back exactly');
  check(await page.locator('#result b, #result img').count() === 0, 'restored text is not turned into HTML');
  check(!(await page.evaluate(() => window.pwned)), 'no script ran');
  check((await page.textContent('#health-text')).includes('Read perfectly'), 'health report');
  await page.screenshot({ path: 'docs/read-desktop.png', fullPage: true });
  await page.click('#clear');
  check(await page.locator('#result').isHidden(), 'clear hides the secret');
  check(problems.length === 0, `no console errors or outside requests: ${problems.join(' | ')}`);
  await context.close();
});

await test('the damage lab reads a battered page, and admits defeat when it should', async () => {
  const { context, page, problems } = await fresh({ width: 1280, height: 900 });
  await page.click('#tab-lab');
  await page.waitForFunction(() => document.querySelector('#lab-status').textContent.length > 0);
  check((await page.textContent('#lab-status')).startsWith('Read back'), 'default damage is read');
  await page.screenshot({ path: 'docs/lab-desktop.png', fullPage: true });
  await setLab(page, { rotate: -150, tilt: 0.2, stains: 4, noise: 30, blur: 0 });
  check((await page.textContent('#lab-status')).startsWith('Read back'), 'upside down, tilted and stained is still read');
  await setLab(page, { blot: 0.25, tear: 0.3 });
  check(!(await page.textContent('#lab-status')).startsWith('Read back'), 'too much damage is reported, not misread');
  check(problems.length === 0, `no console errors: ${problems.join(' | ')}`);
  await context.close();
});

await test('the printed layout reads back', async () => {
  const { context, page } = await fresh({ width: 794, height: 1123 }); // A4 at 96 dpi
  await page.fill('#secret', 'Printed and read: 7 Elm St, spare key under the blue pot');
  await page.click('#make-button');
  await page.waitForSelector('#sheet svg');
  await page.emulateMedia({ media: 'print' });
  check(await page.locator('form#make-form').isHidden(), 'form not printed');
  check(await page.locator('.masthead').isHidden(), 'header not printed');
  await page.screenshot({ path: 'docs/print-preview.png', fullPage: true });
  const pdf = await page.pdf({ format: 'A4' });
  check(pdf.length > 1000, 'prints to a PDF');
  await page.emulateMedia({ media: 'screen' });
  await page.click('#tab-read');
  await page.setInputFiles('#photo', 'docs/print-preview.png');
  await page.waitForFunction(() => !['', 'Reading…'].includes(document.querySelector('#read-status').textContent));
  await page.waitForSelector('#result:not([hidden])', { timeout: 5000 }).catch(() => {});
  check((await page.textContent('#result')) === 'Printed and read: 7 Elm St, spare key under the blue pot',
    `print layout decodes: ${await page.textContent('#read-status')}`);
  await context.close();
});

await test('a page too big for one sheet is refused politely', async () => {
  const { context, page } = await fresh({ width: 1280, height: 900 });
  let seed = 1;
  const random = Array.from({ length: 1500 }, () => {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return String.fromCharCode(33 + (seed >> 16) % 90);
  }).join('');
  await page.fill('#secret', random);
  await page.click('#make-button');
  await page.waitForSelector('#make-error:not([hidden])');
  check((await page.textContent('#make-error')).includes('one page holds'), 'size error');
  await page.fill('#secret', '');
  await page.click('#make-button');
  check((await page.textContent('#make-error')).includes('Type something'), 'empty refused');
  await context.close();
});

await test('works at phone width with no sideways scrolling', async () => {
  const { context, page, problems } = await fresh({ width: 390, height: 844 });
  await page.fill('#secret', 'Wi-Fi: Hogwarts-5G / alohomora-2026');
  await page.click('#make-button');
  await page.waitForSelector('#sheet svg');
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  check(overflow <= 0, `no horizontal scroll on Make (${overflow}px)`);
  await page.screenshot({ path: 'docs/make-phone.png', fullPage: true });
  for (const tab of ['read', 'lab']) {
    await page.click(`#tab-${tab}`);
    await page.waitForTimeout(300);
    const o = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    check(o <= 0, `no horizontal scroll on ${tab} (${o}px)`);
  }
  await page.screenshot({ path: 'docs/lab-phone.png', fullPage: true });
  check(problems.length === 0, `no console errors: ${problems.join(' | ')}`);
  await context.close();
});

await test('security headers in the page', async () => {
  const { context, page } = await fresh({ width: 1000, height: 800 });
  const csp = await page.getAttribute('meta[http-equiv="Content-Security-Policy"]', 'content');
  check(csp.includes("default-src 'none'") && csp.includes("script-src 'self' 'wasm-unsafe-eval'"), 'strict CSP');
  check(!csp.includes('unsafe-inline') && !csp.includes("'unsafe-eval'"), 'no unsafe-inline or unsafe-eval');
  // An inline script injected at run time is blocked by the policy.
  const ran = await page.evaluate(() => {
    const s = document.createElement('script');
    s.textContent = 'window.inlineRan = true';
    document.body.append(s);
    return window.inlineRan === true;
  });
  check(!ran, 'inline scripts are blocked');
  await context.close();
});

await browser.close();
server.close();
console.log(`${checks} checks, ${failures} failed`);
process.exit(failures ? 1 : 0);
