import { defineConfig, devices } from "@playwright/test";
import path from "path";

// The dashboard owns every route these tests touch (/, /login, /signup,
// /admin, /api/*). dev-servers.ps1 pins it to 3001 and leaves 3000 for the
// site renderer, so the E2E base URL has to match that split.
const PORT = Number(process.env.E2E_PORT || 3001);
const BASE_URL = process.env.E2E_BASE_URL || `http://localhost:${PORT}`;
const REPO_ROOT = path.join(__dirname, "..");

export default defineConfig({
  testDir: path.join(__dirname, "tests"),
  testMatch: "**/*.spec.ts",
  outputDir: path.join(__dirname, "test-results"),
  // `next dev` compiles each route on first hit, which routinely costs 15s+ on
  // a cold server. Playwright's 30s/5s defaults turn that into flake, so both
  // budgets are raised to sit clear of a first-hit compile.
  timeout: 90_000,
  expect: { timeout: 20_000 },
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ["html", { outputFolder: path.join(__dirname, "playwright-report"), open: "never" }],
    ["list"],
  ],
  use: {
    baseURL: BASE_URL,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: process.env.CI
    ? undefined
    : {
        // Run from the repo root so the workspace flag resolves, and pass the
        // port through to `next dev` so it cannot drift onto 3000.
        command: `npm run dev -w closet-dashboard -- -p ${PORT}`,
        cwd: REPO_ROOT,
        url: BASE_URL,
        reuseExistingServer: !process.env.CI,
        timeout: 180000,
        stdout: "pipe",
        stderr: "pipe",
      },
});
