import assert from "node:assert/strict";
import test from "node:test";
import { buildCheckoutEndpoint } from "../test-dist/billing.js";

test("builds the Worker checkout endpoint from a proxy prefix", () => {
  assert.equal(
    buildCheckoutEndpoint("https://translator-api.zanderwang.com/"),
    "https://translator-api.zanderwang.com/billing/checkout"
  );
});
