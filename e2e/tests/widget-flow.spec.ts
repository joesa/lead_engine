import { test, expect } from "@playwright/test";

test.describe("Widget to Dashboard Flow", () => {
  test("landing page renders the embedded quote widget", async ({ page }) => {
    await page.goto("/");
    await expect(page).toHaveTitle(/DitchTheForm/);

    // <closet-quote-widget> is server-rendered as an empty, zero-height custom
    // element; it only gets a box once public/widget.js upgrades it and mounts
    // its shadow root. Waiting on the upgrade is the real readiness signal —
    // asserting visibility first just races the bundle.
    await page.waitForFunction(
      () => customElements.get("closet-quote-widget") !== undefined
    );
    await expect(page.locator("closet-quote-widget")).toBeVisible();
  });

  // /api/send-lead emails the contractor and can text them via Twilio, so an
  // e2e run must not drive it to success. Its rejection path is the part worth
  // pinning: contractorId became mandatory to close an open-relay hole, and a
  // regression there is silent from the outside.
  test("lead submission rejects a payload with no contractor", async ({ request }) => {
    const response = await request.post("/api/send-lead", {
      data: {
        customerName: "Test User",
        customerEmail: "test@example.com",
        customerPhone: "555-555-5555",
        range: { low: 1000, high: 2000 },
      },
    });

    expect(response.status()).toBe(400);
    expect(await response.json()).toMatchObject({
      error: expect.stringContaining("contractorId"),
    });
  });

  test("quote calculation rejects a payload with no contractor", async ({ request }) => {
    const response = await request.post("/api/calculate", {
      data: { unitQuantity: 10, roomType: "Walk-In Closet", finishType: "standard" },
    });

    expect(response.status()).toBe(400);
    expect(await response.json()).toMatchObject({
      error: expect.stringContaining("contractorId"),
    });
  });

  // The entitlement gate runs ahead of the contractor lookup, so an id that was
  // never provisioned is refused as unsubscribed (402) rather than 404.
  test("quote calculation gates an unentitled contractor", async ({ request }) => {
    const response = await request.post("/api/calculate", {
      data: {
        contractorId: "test-contractor",
        unitQuantity: 10,
        roomType: "Walk-In Closet",
        finishType: "standard",
        selectedAddOns: [],
      },
    });

    expect(response.status()).toBe(402);
    expect(await response.json()).toMatchObject({
      error: "subscription_required",
      disabled: true,
    });
  });
});

test.describe("Dashboard Authentication", () => {
  test("login page loads", async ({ page }) => {
    await page.goto("/login");
    await expect(
      page.getByRole("heading", { name: /welcome back/i })
    ).toBeVisible();
  });

  test("signup page loads", async ({ page }) => {
    await page.goto("/signup");
    await expect(
      page.getByRole("heading", { name: /create your account/i })
    ).toBeVisible();
  });
});

test.describe("Admin Dashboard", () => {
  test("unauthenticated users redirected to login", async ({ page }) => {
    await page.goto("/admin");
    await expect(page).toHaveURL(/\/login/);
  });
});
