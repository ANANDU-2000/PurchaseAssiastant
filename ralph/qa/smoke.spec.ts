import { test, expect, Page } from '@playwright/test';

const EMAIL = process.env.QA_EMAIL!;
const PASSWORD = process.env.QA_PASSWORD!;
const API = process.env.API_URL ?? 'https://my-purchases-api.onrender.com';

const NOISE = /interactive-widget|cancelled|ERR_ABORTED|GL Driver/i;
const keep = (e: string) => !NOISE.test(e);

function collectErrors(page: Page) {
  const errors: string[] = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', e => errors.push(String(e)));
  page.on('requestfailed', r => errors.push(`FAILED ${r.url()} ${r.failure()?.errorText}`));
  page.on('response', r => { if (r.status() >= 500) errors.push(`HTTP ${r.status()} ${r.url()}`); });
  return { get length() { return errors.filter(keep).length; }, list: () => errors.filter(keep) };
}

async function semanticsPoints(page: Page) {
  return page.evaluate(() => {
    const nodes = [...document.querySelectorAll('flt-semantics')].map(e => ({ role: e.getAttribute('role'), r: e.getBoundingClientRect() }));
    const rootY = nodes[0].r.y;
    const pt = (n: { r: DOMRect }) => ({ x: n.r.x + n.r.width / 2, y: n.r.y - rootY + n.r.height / 2 });
    const fields = nodes.filter(n => !n.role && n.r.width > 200 && n.r.height >= 50 && n.r.height < 70 && n.r.y > rootY);
    const btn = nodes.find(n => n.role === 'button' && n.r.width > 200);
    return { email: pt(fields[0]), password: pt(fields[1]), signIn: pt(btn!) };
  });
}
test('API healthy (schema lag is a warning)', async ({ request }) => {
  const r = await request.get(`${API}/health/ready`);
  expect(r.ok()).toBeTruthy();
  const j = await r.json();
  expect(j.db).toBe('ok');
  if (j.schema_ok !== true) {
    const behind = j.schema?.schema_behind_by ?? '?';
    const msg = `schema behind by ${behind}: db=${j.schema?.alembic_version} head=${j.expected_alembic_head}`;
    test.info().annotations.push({ type: 'WARNING', description: msg });
    console.warn(`[WARN] ${msg}`);
  }
});

test('login → home, no console errors', async ({ page }, info) => {
  test.skip(!EMAIL || !PASSWORD, 'set QA_EMAIL / QA_PASSWORD');
  const errors = collectErrors(page);
  await page.goto('/login');
  // Flutter web: enable semantics so inputs are reachable
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 30_000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.dispatchEvent(new MouseEvent('click', { bubbles: true })));
  await page.locator('flt-semantics[role=button]').first().waitFor({ state: 'attached', timeout: 30_000 });
  const pts = await semanticsPoints(page);
  await page.reload();
  await page.waitForTimeout(6000);
  await page.mouse.click(pts.email.x, pts.email.y);
  await page.keyboard.type(EMAIL);
  await page.mouse.click(pts.password.x, pts.password.y);
  await page.keyboard.type(PASSWORD);
  await page.mouse.click(pts.signIn.x, pts.signIn.y);
  await expect(page).not.toHaveURL(/login/, { timeout: 45_000 });
  await expect(page.getByText(/Cannot reach|Connection problem/i)).toHaveCount(0);
  await page.screenshot({ path: `shots/home-${info.project.name}.png`, fullPage: true });
  expect(errors.list(), errors.list().join('\n')).toEqual([]);
});

test('screens: shots + overflow + console', async ({ page }, info) => {
  test.skip(!EMAIL || !PASSWORD, 'set QA_EMAIL / QA_PASSWORD');
  test.setTimeout(240_000);
  const errors = collectErrors(page);
  await page.goto('/login');
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 30_000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.dispatchEvent(new MouseEvent('click', { bubbles: true })));
  await page.locator('flt-semantics[role=button]').first().waitFor({ state: 'attached', timeout: 30_000 });
  const pts = await semanticsPoints(page);
  await page.reload();
  await page.waitForTimeout(6000);
  await page.screenshot({ path: `shots/login-${info.project.name}.png` });
  await page.mouse.click(pts.email.x, pts.email.y);
  await page.keyboard.type(EMAIL);
  await page.mouse.click(pts.password.x, pts.password.y);
  await page.keyboard.type(PASSWORD);
  await page.mouse.click(pts.signIn.x, pts.signIn.y);
  await expect(page).not.toHaveURL(/login/, { timeout: 45_000 });
  const base = new URL(page.url()).origin;
  const overflow: string[] = [];
  for (const r of ['dashboard', 'stock', 'purchase', 'reports', 'search', 'settings']) {
    await page.goto(`${base}/${r}`);
    await page.waitForTimeout(7000);
    await page.screenshot({ path: `shots/${r}-${info.project.name}.png` });
    const w = await page.evaluate(() => [document.documentElement.scrollWidth, window.innerWidth]);
    if (w[0] > w[1]) overflow.push(`${r} ${w[0]}>${w[1]}`);
    if (/login/.test(page.url())) overflow.push(`${r} redirected to login`);
  }
  expect(overflow, overflow.join(', ')).toEqual([]);
  expect(errors.list(), errors.list().join(', ')).toEqual([]);
});
