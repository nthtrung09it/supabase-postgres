import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  testMatch: 'e2e-test.ts',
  timeout: 120_000,
  expect: {
    timeout: 30_000,
  },
  retries: 1,
  use: {
    baseURL: 'http://localhost:8000',
    httpCredentials: {
      username: 'supabase',
      password: 'this_password_is_insecure_and_should_be_updated',
    },
    // Studio can be slow to load
    navigationTimeout: 60_000,
    actionTimeout: 30_000,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  reporter: [['list'], ['html', { open: 'never' }]],
});
