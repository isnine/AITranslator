import assert from "node:assert/strict";
import test from "node:test";
import {
  computeStripeWebhookSignature,
  verifyStripeWebhookSignature,
} from "../test-dist/stripe-webhook.js";

test("verifies Stripe webhook signatures", async () => {
  const payload = JSON.stringify({ id: "evt_test" });
  const timestamp = "1893456000";
  const signature = await computeStripeWebhookSignature(payload, timestamp, "whsec_test");

  assert.equal(
    await verifyStripeWebhookSignature(
      payload,
      `t=${timestamp},v1=${signature}`,
      "whsec_test"
    ),
    true
  );
  assert.equal(
    await verifyStripeWebhookSignature(
      payload,
      `t=${timestamp},v1=${signature}`,
      "wrong_secret"
    ),
    false
  );
});
