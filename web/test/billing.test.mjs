import assert from "node:assert/strict";
import test from "node:test";
import { buildCheckoutEndpoint, isBillingPlan } from "../test-dist/billing.js";

test("builds the Worker checkout endpoint from a proxy prefix", () => {
  assert.equal(
    buildCheckoutEndpoint("https://translator-api.zanderwang.com/"),
    "https://translator-api.zanderwang.com/billing/checkout"
  );
});

test("accepts all supported checkout plans", () => {
  assert.equal(isBillingPlan("monthly"), true);
  assert.equal(isBillingPlan("yearly"), true);
  assert.equal(isBillingPlan("lifetime"), true);
  assert.equal(isBillingPlan("weekly"), false);
});
