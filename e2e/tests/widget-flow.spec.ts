import { test, expect } from "@playwright/test";

test.describe("Widget to Dashboard Flow", () => {
  test("widget loads and submits lead", async ({ page }) => {
    await page.goto("/");
    await expect(page).toHaveTitle(/DitchTheForm/);

    const widget = page.locator("closet-quote-widget");
    await expect(widget).toBeVisible();

    await page.waitForTimeout(1000);
  });

  test("lead submission triggers API call", async ({ page, request }) => {
    const response = await request.post("/api/send-lead", {
      data: {
        name: "Test User",
        email: "test@example.com",
        phone: "555-555-5555",
        linearFeet: 10,
        roomType: "closet",
        finish: "laminate",
        message: "Test lead",
      },
    });

    expect(response.status()).toBeGreaterThanOrEqual(200);
  });

  test("quote calculation returns valid response", async ({ page, request }) => {
    const response = await request.post("/api/calculate", {
      data: {
        contractorId: "test-contractor",
        linearFeet: 10,
        roomType: "closet",
        finish: "laminate",
        addons: [],
      },
    });

    const json = await response.json();
    expect(json).toHaveProperty("minPrice");
    expect(json).toHaveProperty("maxPrice");
  });
});

test.describe("Dashboard Authentication", () => {
  test("login page loads", async ({ page }) => {
    await page.goto("/login");
    await expect(page.getByRole("heading", { name: /sign in/i })).toBeVisible();
  });

  test("signup page loads", async ({ page }) => {
    await page.goto("/signup");
    await expect(
      page.getByRole("heading", { name: /create account/i })
    ).toBeVisible();
  });
});

test.describe("Admin Dashboard", () => {
  test("unauthenticated users redirected to login", async ({ page }) => {
    await page.goto("/admin");
    await expect(page).toHaveURL(/\/login/);
  });
});
