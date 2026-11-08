import { Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const allow: RegExp[] = JSON.parse(fs.readFileSync(path.join(__dirname, 'console-allowlist.json'), 'utf-8'))
  .patterns.map((p: { regex: string }) => new RegExp(p.regex, 'i'));
export const keep = (e: string) => !allow.some(r => r.test(e));

/** Collects real problems only: uncaught errors, console errors, failed requests, 5xx. */
export function collectErrors(page: Page) {
  const errors: string[] = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', e => errors.push(String(e)));
  page.on('requestfailed', r => errors.push(`FAILED ${r.url()} ${r.failure()?.errorText}`));
  page.on('response', r => { if (r.status() >= 500) errors.push(`HTTP ${r.status()} ${r.url()}`); });
  return { get length() { return errors.filter(keep).length; }, list: () => errors.filter(keep) };
}
