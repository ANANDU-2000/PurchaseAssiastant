import { test, expect, Page } from '@playwright/test';

const EMAIL = process.env.QA_EMAIL!;
const PASSWORD = process.env.QA_PASSWORD!;
const API = process.env.API_URL ?? 'https://my-purchases-api.onrender.com';

function collectErrors(page: Page) {
  const errors: string[] = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', e => errors.push(String(e)));
  page.on('requestfailed', r => errors.push(`FAILED ${r.url()} ${r.failure()?.errorText}`));
  page.on('response', r => { if (r.status() >= 500) errors.push(`HTTP ${r.status()} ${r.url()}`); });
  return errors;
}

test('API healthy and schema at head', async ({ request }) => {
  const r = await request.get(`${API}/health/ready`);
  expect(r.ok()).toBeTruthy();
  const j = await r.json();
  expect(JSON.stringify(j)).toContain('"schema_ok":true');
});

test('login → home, no console errors', async ({ page }, info) => {
  test.skip(!EMAIL || !PASSWORD, 'set QA_EMAIL / QA_PASSWORD');
  const errors = collectErrors(page);
  await page.goto('/login');
  // Flutter web: enable semantics so inputs are reachable
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 30_000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.dispatchEvent(new MouseEvent('click', { bubbles: true })));
  await page.getByLabel('Email', { exact: true }).fill(EMAIL);
  await page.getByLabel('Password', { exact: true }).fill(PASSWORD);
  await page.getByRole('button', { name: /sign in/i }).click();
  await expect(page).not.toHaveURL(/login/, { timeout: 45_000 });
  await expect(page.getByText(/Cannot reach|Connection problem/i)).toHaveCount(0);
  await page.screenshot({ path: `shots/home-${info.project.name}.png`, fullPage: true });
  expect(errors, errors.join('\n')).toEqual([]);
});


