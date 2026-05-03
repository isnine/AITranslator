import assert from "node:assert/strict";
import { test } from "node:test";

import { createGoogleNonce, sha256Hex } from "../test-dist/google-onetap-crypto.js";

test("createGoogleNonce returns a random URL-safe nonce", () => {
  const first = createGoogleNonce();
  const second = createGoogleNonce();

  assert.match(first, /^[A-Za-z0-9_-]{32,}$/);
  assert.notEqual(first, second);
});

test("sha256Hex returns a SHA-256 digest for the Google nonce", async () => {
  const digest = await sha256Hex("TLingo Web");

  assert.equal(digest, "f46bae11ef4a713ae77f000995bea1fbdc73f42963867db25285f8e91f8163f2");
});
