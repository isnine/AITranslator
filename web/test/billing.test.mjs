import assert from "node:assert/strict";
import test from "node:test";
import {
  buildBillingPortalEndpoint,
  buildBillingStatusEndpoint,
  buildCheckoutEndpoint,
  createCheckoutRequest,
  isBillingPlan,
  parseBillingStatus,
} from "../test-dist/billing.js";

test("builds the Worker checkout endpoint from a proxy prefix", () => {
  assert.equal(
    buildCheckoutEndpoint("/api"),
    "/api/billing/checkout"
  );
});

test("still supports absolute legacy Worker prefixes", () => {
  assert.equal(
    buildCheckoutEndpoint("https://translator-api.zanderwang.com/"),
    "https://translator-api.zanderwang.com/billing/checkout"
  );
});

test("builds billing status and portal endpoints", () => {
  assert.equal(buildBillingStatusEndpoint("/api"), "/api/billing/status");
  assert.equal(buildBillingPortalEndpoint("/api"), "/api/billing/portal");
});

test("creates authenticated checkout requests", () => {
  assert.deepEqual(createCheckoutRequest("monthly", "token_123"), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer token_123",
    },
    body: JSON.stringify({ plan: "monthly" }),
  });
});

test("parses billing status with safe defaults", () => {
  assert.deepEqual(parseBillingStatus(null), {
    isPremium: false,
    plan: null,
    status: null,
    currentPeriodEnd: null,
    lifetimeAccess: false,
    stripeCustomerId: null,
  });
  assert.deepEqual(parseBillingStatus({ isPremium: true, plan: "lifetime" }), {
    isPremium: true,
    plan: "lifetime",
    status: null,
    currentPeriodEnd: null,
    lifetimeAccess: false,
    stripeCustomerId: null,
  });
});

test("accepts all supported checkout plans", () => {
  assert.equal(isBillingPlan("monthly"), true);
  assert.equal(isBillingPlan("yearly"), true);
  assert.equal(isBillingPlan("lifetime"), true);
  assert.equal(isBillingPlan("weekly"), false);
});
