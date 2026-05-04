import assert from "node:assert/strict";
import test from "node:test";
import { normalizeApiPath } from "../test-dist/routing.js";

test("strips the /api prefix from new TLingo API paths", () => {
  assert.equal(normalizeApiPath("/api/models"), "/models");
  assert.equal(normalizeApiPath("/api/billing/checkout"), "/billing/checkout");
  assert.equal(
    normalizeApiPath("/api/gpt-5.4-nano/chat/completions"),
    "/gpt-5.4-nano/chat/completions"
  );
});

test("keeps legacy Worker API paths unchanged", () => {
  assert.equal(normalizeApiPath("/models"), "/models");
  assert.equal(
    normalizeApiPath("/gpt-5.4-nano/chat/completions"),
    "/gpt-5.4-nano/chat/completions"
  );
});

test("normalizes bare /api to the root path", () => {
  assert.equal(normalizeApiPath("/api"), "/");
  assert.equal(normalizeApiPath("/api/"), "/");
});
