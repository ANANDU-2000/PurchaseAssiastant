import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';

const EMAIL = process.env.QA_EMAIL!;
const PASSWORD = process.env.QA_PASSWORD!;
const NOISE = /interactive-widget|cancelled|ERR_ABORTED|GL Driver/i;

async function login(page: Page) {
  await page.goto('/login');
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 30_000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.dispatchEvent(new MouseEvent('click', { bubbles: true })));
  await page.locator('flt-semantics[role=button]').first().waitFor({ state: 'attached', timeout: 30_000 });
  const pts = await page.evaluate(() => {
    const nodes = [...document.querySelectorAll('flt-semantics')].map(e => ({ role: e.getAttribute('role'), r: e.getBoundingClientRect() }));
    const rootY = nodes[0].r.y;
    const pt = (n: { r: DOMRect }) => ({ x: n.r.x + n.r.width / 2, y: n.r.y - rootY + n.r.height / 2 });
    const f = nodes.filter(n => !n.role && n.r.width > 200 && n.r.height >= 50 && n.r.height < 70 && n.r.y > rootY);
    return { e: pt(f[0]), p: pt(f[1]), b: pt(nodes.find(n => n.role === 'button' && n.r.width > 200)!) };
  });
  await page.reload();
  await page.waitForTimeout(6000);
  await page.mouse.click(pts.e.x, pts.e.y); await page.keyboard.type(EMAIL);
  await page.mouse.click(pts.p.x, pts.p.y); await page.keyboard.type(PASSWORD);
  await page.mouse.click(pts.b.x, pts.b.y);
  await expect(page).not.toHaveURL(/login/, { timeout: 45_000 });
}

test('perf baseline iPhone16 Fast4G 4xCPU', async ({ page, context }) => {
  test.skip(!EMAIL || !PASSWORD, 'set QA_EMAIL / QA_PASSWORD');
  test.setTimeout(300_000);
  await page.setViewportSize({ width: 393, height: 852 });
  await login(page);
  const base = new URL(page.url()).origin;
  const cdp = await context.newCDPSession(page);
  await cdp.send('Network.enable');
  await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 150, downloadThroughput: 1.6 * 1024 * 1024 / 8 * 8 / 8, uploadThroughput: 750 * 1024 / 8, });
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  const out: any[] = [];
  for (const r of ['dashboard', 'stock', 'purchase', 'reports', 'search']) {
    const calls: string[] = []; const errs: string[] = []; const t0 = { v: 0 }; let firstData = -1;
    const onReq = (q: any) => { if (q.url().includes('my-purchases-api')) calls.push(`${q.method()} ${q.url().replace(/^https:\/\/[^/]+/, '').replace(/[0-9a-f-]{36}/g, ':id')}`); };
    const onRes = (s: any) => { if (firstData < 0 && s.url().includes('/v1/businesses/') && s.ok()) firstData = Date.now() - t0.v; };
    const onCons = (m: any) => { if (m.type() === 'error' && !NOISE.test(m.text())) errs.push(m.text().slice(0, 120)); };
    page.on('request', onReq); page.on('response', onRes); page.on('console', onCons);
    t0.v = Date.now();
    await page.goto(`${base}/${r}`, { waitUntil: 'commit' });
    const fcp = await page.waitForFunction(() => performance.getEntriesByName('first-contentful-paint')[0]?.startTime, null, { timeout: 60_000 }).then(h => h.jsonValue()).catch(() => -1);
    await page.waitForTimeout(12_000);
    page.off('request', onReq); page.off('response', onRes); page.off('console', onCons);
    const counts: Record<string, number> = {}; calls.forEach(c => counts[c] = (counts[c] || 0) + 1);
    const dups = Object.entries(counts).filter(([, n]) => n > 1).map(([k, n]) => `${n}x ${k.slice(0, 70)}`);
    out.push({ screen: r, fcp_ms: Math.round(Number(fcp)), first_data_ms: firstData, api_calls: calls.length, dup_calls: dups.length, dups, console_errors: errs.length });
  }
  fs.writeFileSync('shots/perf-baseline.json', JSON.stringify(out, null, 1));
  console.log(JSON.stringify(out.map(({ dups, ...x }) => x)));
});
