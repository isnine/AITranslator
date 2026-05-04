import assert from "node:assert/strict";
import test from "node:test";
import {
  buildCheckoutParams,
  selectBillingPrice,
  TLINGO_MONTHLY_PRICE_ID,
  TLINGO_YEARLY_PRICE_ID,
} from "../test-dist/billing.js";

test("selects the TLingo monthly Stripe price", () => {
  assert.deepEqual(selectBillingPrice("monthly"), {
    plan: "monthly",
    priceId: TLINGO_MONTHLY_PRICE_ID,
  });
});

test("selects the TLingo yearly Stripe price", () => {
  assert.deepEqual(selectBillingPrice("yearly"), {
    plan: "yearly",
    priceId: TLINGO_YEARLY_PRICE_ID,
  });
});

test("rejects unknown billing plans", () => {
  assert.throws(() => selectBillingPrice("weekly"), /plan must be monthly or yearly/);
});

test("builds a Managed Payments Checkout Session payload", () => {
  const params = buildCheckoutParams({
    plan: "monthly",
    customerEmail: "buyer@example.com",
  });

  assert.equal(params.get("mode"), "subscription");
  assert.equal(params.get("line_items[0][price]"), TLINGO_MONTHLY_PRICE_ID);
  assert.equal(params.get("line_items[0][quantity]"), "1");
  assert.equal(params.get("managed_payments[enabled]"), "true");
  assert.equal(params.get("allow_promotion_codes"), "true");
  assert.equal(params.get("customer_email"), "buyer@example.com");
  assert.equal(params.get("success_url"), "https://tlingo.zanderwang.com/?checkout=success");
  assert.equal(params.get("cancel_url"), "https://tlingo.zanderwang.com/?checkout=cancelled");
});
