import { defineConfig, devices } from '@playwright/test';
export default defineConfig({
  testDir: '.',
  timeout: 90_000,
  retries: 1,
  reporter: [['line']],
  use: {
    baseURL: process.env.APP_URL ?? 'https://purchase-assiastant.vercel.app',
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [
    { name: 'desktop', use: { viewport: { width: 1440, height: 900 } } },
    { name: 'tablet', use: { ...devices['iPad (gen 7)'] } },
    { name: 'mobile', use: { ...devices['iPhone 13'] } },
  ],
});
