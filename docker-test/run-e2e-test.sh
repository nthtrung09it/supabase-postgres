#!/usr/bin/env bash
#
# run-e2e-test.sh -- Run Playwright E2E tests for Supabase Studio + PG 18
#
# Prerequisites:
#   - The Supabase stack must be running (docker compose up)
#   - Node.js / npm must be installed
#
# Usage:
#   ./run-e2e-test.sh            # Run all tests
#   ./run-e2e-test.sh --headed   # Run with browser visible
#   ./run-e2e-test.sh --debug    # Run in debug mode
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ------------------------------------------------------------------
# 1. Check for Node.js
# ------------------------------------------------------------------
if ! command -v node &>/dev/null; then
  echo "ERROR: Node.js is not installed. Please install Node.js >= 18."
  exit 1
fi

echo "Node.js version: $(node --version)"

# ------------------------------------------------------------------
# 2. Install dependencies if needed
# ------------------------------------------------------------------
if [ ! -d "node_modules/@playwright/test" ]; then
  echo "Installing @playwright/test ..."
  npm install --save-dev @playwright/test
fi

# Install Playwright browsers if not already present
if ! npx playwright install --dry-run chromium &>/dev/null 2>&1; then
  echo "Installing Playwright Chromium browser ..."
  npx playwright install chromium
fi

# ------------------------------------------------------------------
# 3. Wait for Studio to be ready
# ------------------------------------------------------------------
echo "Checking if Supabase Studio is reachable at http://localhost:8000 ..."
MAX_WAIT=120
WAITED=0
until curl -sf -o /dev/null -u "supabase:this_password_is_insecure_and_should_be_updated" "http://localhost:8000/"; do
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "ERROR: Studio did not become reachable within ${MAX_WAIT}s."
    echo "Make sure the Supabase stack is running: docker compose up -d"
    exit 1
  fi
  sleep 2
  WAITED=$((WAITED + 2))
  echo "  Waiting for Studio ... (${WAITED}s / ${MAX_WAIT}s)"
done
echo "Studio is reachable."

# ------------------------------------------------------------------
# 4. Run the Playwright tests
# ------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  Running PG 18 E2E Tests"
echo "=========================================="
echo ""

npx playwright test --config=playwright.config.ts "$@"
EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
  echo "=========================================="
  echo "  All PG 18 E2E tests PASSED"
  echo "=========================================="
else
  echo "=========================================="
  echo "  Some tests FAILED (exit code: $EXIT_CODE)"
  echo "=========================================="
  echo ""
  echo "To view the HTML report: npx playwright show-report"
fi

exit $EXIT_CODE
