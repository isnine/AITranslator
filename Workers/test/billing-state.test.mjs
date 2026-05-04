import assert from "node:assert/strict";
import test from "node:test";
import {
  buildCheckoutCompletedEntitlement,
  buildSubscriptionEntitlement,
  getBillingStatus,
} from "../test-dist/billing-state.js";

const future = "2030-01-01T00:00:00.000Z";
const past = "2020-01-01T00:00:00.000Z";

test("grants premium for active lifetime entitlement", () => {
  assert.deepEqual(
    getBillingStatus({
      plan: "lifetime",
      status: "active",
      lifetime_access: true,
      current_period_end: null,
    }),
    {
      isPremium: true,
      plan: "lifetime",
      status: "active",
      currentPeriodEnd: null,
      lifetimeAccess: true,
      stripeCustomerId: null,
    }
  );
});

test("grants premium for active unexpired subscriptions only", () => {
  assert.equal(
    getBillingStatus({
      plan: "monthly",
      status: "active",
      lifetime_access: false,
      current_period_end: future,
    }).isPremium,
    true
  );
  assert.equal(
    getBillingStatus({
      plan: "monthly",
      status: "active",
      lifetime_access: false,
      current_period_end: past,
    }).isPremium,
    false
  );
  assert.equal(
    getBillingStatus({
      plan: "monthly",
      status: "past_due",
      lifetime_access: false,
      current_period_end: future,
    }).isPremium,
    false
  );
});

test("maps lifetime checkout completion to an active entitlement", () => {
  assert.deepEqual(
    buildCheckoutCompletedEntitlement({
      id: "cs_test",
      customer: "cus_test",
      payment_status: "paid",
      metadata: { plan: "lifetime", supabase_user_id: "user_123" },
    }),
    {
      user_id: "user_123",
      plan: "lifetime",
      status: "active",
      lifetime_access: true,
      current_period_end: null,
      stripe_customer_id: "cus_test",
      stripe_subscription_id: null,
      stripe_price_id: null,
      stripe_checkout_session_id: "cs_test",
    }
  );
});

test("maps subscription events to entitlement rows", () => {
  assert.deepEqual(
    buildSubscriptionEntitlement({
      id: "sub_test",
      customer: "cus_test",
      status: "active",
      current_period_end: 1893456000,
      metadata: { plan: "yearly", supabase_user_id: "user_123" },
      items: { data: [{ price: { id: "price_year" } }] },
    }),
    {
      user_id: "user_123",
      plan: "yearly",
      status: "active",
      lifetime_access: false,
      current_period_end: "2030-01-01T00:00:00.000Z",
      stripe_customer_id: "cus_test",
      stripe_subscription_id: "sub_test",
      stripe_price_id: "price_year",
    }
  );
});
