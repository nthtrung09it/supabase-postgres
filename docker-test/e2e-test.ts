import { test, expect, Page } from '@playwright/test';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Service role key from .env -- needed for direct SQL via PostgREST RPC or pg-meta */
const SERVICE_ROLE_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q';

const BASE_URL = 'http://localhost:8000';

/**
 * Execute a SQL query through the pg-meta service exposed by Kong.
 * This bypasses the Studio UI and calls pg-meta's /query endpoint directly,
 * which is more reliable for programmatic assertions.
 */
async function executeSql(page: Page, sql: string): Promise<any> {
  const context = page.context();
  const response = await context.request.post(`${BASE_URL}/pg/query`, {
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
    },
    data: JSON.stringify({ query: sql }),
  });
  expect(response.ok(), `SQL query failed (${response.status()}): ${sql}`).toBeTruthy();
  return response.json();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test.describe('PG 18 Supabase Studio E2E', () => {
  test.describe.configure({ mode: 'serial' });

  test('Studio dashboard loads successfully', async ({ page }) => {
    // Kong protects Studio with Basic Auth (configured in playwright.config.ts
    // via httpCredentials). Navigate to the root URL.
    await page.goto('/');

    // Studio should render. Look for the project page or a recognisable
    // heading. The exact text depends on the Studio version, so we look for
    // common markers.
    await expect(
      page.locator('text=/Default Project|Welcome|Table Editor|SQL Editor|Home/i').first()
    ).toBeVisible({ timeout: 60_000 });
  });

  test('PostgreSQL 18 version is reported', async ({ page }) => {
    const rows = await executeSql(page, 'SELECT version();');
    const version: string = rows[0]?.version ?? rows[0]?.Version ?? JSON.stringify(rows[0]);
    expect(version).toContain('PostgreSQL 18');
  });

  test('Create pg18_smoke_test table with pgvector column', async ({ page }) => {
    // Ensure pgvector extension is available
    await executeSql(page, 'CREATE EXTENSION IF NOT EXISTS vector;');

    // Create the test table
    await executeSql(page, `
      CREATE TABLE IF NOT EXISTS public.pg18_smoke_test (
        id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        name text,
        embedding vector(3),
        created_at timestamptz DEFAULT now()
      );
    `);

    // Verify the table exists
    const rows = await executeSql(
      page,
      `SELECT table_name FROM information_schema.tables
       WHERE table_schema = 'public' AND table_name = 'pg18_smoke_test';`
    );
    expect(rows).toHaveLength(1);
    expect(rows[0].table_name).toBe('pg18_smoke_test');
  });

  test('Insert test data with vector embeddings', async ({ page }) => {
    await executeSql(page, `
      INSERT INTO public.pg18_smoke_test (name, embedding) VALUES
        ('test1', '[1,2,3]'),
        ('test2', '[4,5,6]');
    `);

    const rows = await executeSql(
      page,
      `SELECT name, embedding::text FROM public.pg18_smoke_test ORDER BY name;`
    );
    expect(rows).toHaveLength(2);
    expect(rows[0].name).toBe('test1');
    expect(rows[1].name).toBe('test2');
  });

  test('Vector similarity search works', async ({ page }) => {
    const rows = await executeSql(page, `
      SELECT name, embedding <-> '[1,2,3]' AS distance
      FROM public.pg18_smoke_test
      ORDER BY embedding <-> '[1,2,3]';
    `);

    expect(rows).toHaveLength(2);
    // 'test1' has embedding [1,2,3] so distance to [1,2,3] should be 0
    expect(rows[0].name).toBe('test1');
    expect(parseFloat(rows[0].distance)).toBeCloseTo(0, 5);
    // 'test2' should have a non-zero distance
    expect(parseFloat(rows[1].distance)).toBeGreaterThan(0);
  });

  test('Key extensions are installed', async ({ page }) => {
    const rows = await executeSql(page, `
      SELECT extname, extversion
      FROM pg_extension
      WHERE extname IN ('vector', 'pgsodium', 'supabase_vault', 'pg_graphql')
      ORDER BY extname;
    `);

    const extNames = rows.map((r: any) => r.extname);

    // vector was created in an earlier test
    expect(extNames).toContain('vector');
    // pgsodium is loaded by default in Supabase Postgres
    expect(extNames).toContain('pgsodium');

    // Log all found extensions for debugging
    for (const row of rows) {
      console.log(`  Extension: ${row.extname} v${row.extversion}`);
    }
  });

  test('Additional PG 18 extensions smoke test', async ({ page }) => {
    // Test that a few more critical extensions can be loaded
    const extensions = ['pg_stat_statements', 'pgcrypto', 'uuid-ossp'];

    for (const ext of extensions) {
      await executeSql(page, `CREATE EXTENSION IF NOT EXISTS "${ext}";`);
    }

    const rows = await executeSql(page, `
      SELECT extname FROM pg_extension
      WHERE extname IN ('pg_stat_statements', 'pgcrypto', 'uuid-ossp')
      ORDER BY extname;
    `);

    const extNames = rows.map((r: any) => r.extname);
    for (const ext of extensions) {
      expect(extNames, `Extension "${ext}" should be installed`).toContain(ext);
    }
  });

  test('SQL Editor UI is accessible', async ({ page }) => {
    // Navigate to the SQL Editor page through Studio
    await page.goto('/project/default/sql/new');

    // The SQL Editor should load -- look for the Monaco editor or
    // a recognisable element.
    await expect(
      page.locator('[class*="monaco"], [class*="sql"], [role="textbox"], textarea').first()
    ).toBeVisible({ timeout: 60_000 });
  });

  test('Table Editor UI is accessible', async ({ page }) => {
    await page.goto('/project/default/editor');

    // The table editor should show our smoke test table or at least load.
    await expect(
      page.locator('text=/pg18_smoke_test|Table Editor|Tables|No tables/i').first()
    ).toBeVisible({ timeout: 60_000 });
  });

  test('Cleanup: drop pg18_smoke_test table', async ({ page }) => {
    await executeSql(page, 'DROP TABLE IF EXISTS public.pg18_smoke_test;');

    // Verify it is gone
    const rows = await executeSql(
      page,
      `SELECT table_name FROM information_schema.tables
       WHERE table_schema = 'public' AND table_name = 'pg18_smoke_test';`
    );
    expect(rows).toHaveLength(0);
  });
});
