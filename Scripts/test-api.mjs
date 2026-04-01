#!/usr/bin/env node
// test-api.mjs — End-to-end API test for Azure + Cloudflare Worker endpoints
// Usage: node Scripts/test-api.mjs

import { createHmac } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// ── Config ──────────────────────────────────────────────────────────────────

const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath = resolve(__dirname, "../.env");

function loadEnv() {
  const text = readFileSync(envPath, "utf-8");
  const vars = {};
  for (const line of text.split("\n")) {
    const m = line.match(/^([A-Z_]+)=(.+)$/);
    if (m) vars[m[1]] = m[2];
  }
  return vars;
}

const env = loadEnv();
const SECRET = env.AITRANSLATOR_CLOUD_SECRET;
const AZURE_BASE = env.AITRANSLATOR_CLOUD_ENDPOINT; // https://...azurewebsites.net/api
const WORKER_BASE = "https://translator-api.zanderwang.com";
const TEST_USER_ID = "test-user-" + Date.now();

if (!SECRET) {
  console.error("ERROR: AITRANSLATOR_CLOUD_SECRET not found in .env");
  process.exit(1);
}

// ── HMAC Signing ────────────────────────────────────────────────────────────

function sign(path) {
  const timestamp = String(Math.floor(Date.now() / 1000));
  const message = `${timestamp}:${path}`;
  const signature = createHmac("sha256", Buffer.from(SECRET, "hex"))
    .update(message)
    .digest("hex");
  return { "X-Timestamp": timestamp, "X-Signature": signature };
}

// ── HTTP Helper ─────────────────────────────────────────────────────────────

async function req(base, method, path, { body, extraHeaders } = {}) {
  const url = `${base}${path}`;
  const headers = {
    Accept: "application/json",
    ...sign(path.split("?")[0]), // sign path without query string
    "X-User-ID": TEST_USER_ID,
    ...extraHeaders,
  };
  if (body) headers["Content-Type"] = "application/json";

  const res = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  let data;
  const ct = res.headers.get("content-type") || "";
  if (ct.includes("json")) {
    data = await res.json();
  } else {
    data = await res.text();
  }
  return { status: res.status, data };
}

// ── Test Runner ─────────────────────────────────────────────────────────────

let passed = 0;
let failed = 0;

function assert(name, condition, detail) {
  if (condition) {
    console.log(`  \x1b[32m✓\x1b[0m ${name}`);
    passed++;
  } else {
    console.log(`  \x1b[31m✗\x1b[0m ${name} — ${detail}`);
    failed++;
  }
}

// ── Azure Endpoint Tests ────────────────────────────────────────────────────

async function testAzure() {
  console.log(`\n\x1b[1m═══ Azure Endpoint (${AZURE_BASE}) ═══\x1b[0m\n`);

  // 1. GET /models (no auth required)
  console.log("GET /models");
  try {
    const r = await req(AZURE_BASE, "GET", "/models");
    assert("status 200", r.status === 200, `got ${r.status}`);
    assert("returns models array", Array.isArray(r.data?.models), JSON.stringify(r.data).slice(0, 100));
    assert("has gpt-4o-mini", r.data?.models?.some(m => m.id === "gpt-4o-mini"), "model not found");

    // Verify new GPT-5.4 models exist
    assert("has gpt-5.4-mini (free)", r.data?.models?.some(m => m.id === "gpt-5.4-mini"), "model not found");
    assert("has gpt-5.4-nano (free)", r.data?.models?.some(m => m.id === "gpt-5.4-nano"), "model not found");
    assert("has model-router (premium)", r.data?.models?.some(m => m.id === "model-router"), "model not found");

    // Verify tags
    const mini54 = r.data?.models?.find(m => m.id === "gpt-5.4-mini");
    assert("gpt-5.4-mini has 'latest' tag", mini54?.tags?.includes("latest"), `tags: ${JSON.stringify(mini54?.tags)}`);
    const router = r.data?.models?.find(m => m.id === "model-router");
    assert("model-router has 'low-latency' tag", router?.tags?.includes("low-latency"), `tags: ${JSON.stringify(router?.tags)}`);

    // Verify premium filtering
    const defaultModel = r.data?.models?.find(m => m.isDefault);
    assert("has a default model", !!defaultModel, "no default model found");
  } catch (e) {
    assert("request succeeds", false, e.message);
  }

  // 2. GET /models?premium=1 (full list with premium info)
  console.log("\nGET /models?premium=1");
  try {
    const r = await req(AZURE_BASE, "GET", "/models?premium=1");
    assert("premium status 200", r.status === 200, `got ${r.status}`);
    const premiumModels = r.data?.models?.filter(m => m.isPremium);
    assert("premium models have isPremium=true", premiumModels?.length > 0, "no premium models");
    assert("model-router is premium", r.data?.models?.find(m => m.id === "model-router")?.isPremium === true, "not premium");
  } catch (e) {
    assert("request succeeds", false, e.message);
  }

  // 3. GET /models (no premium param — isPremium stripped)
  console.log("\nGET /models (free list — isPremium stripped)");
  try {
    const r = await req(AZURE_BASE, "GET", "/models");
    const hasPremiumField = r.data?.models?.some(m => "isPremium" in m);
    assert("isPremium field stripped from free list", !hasPremiumField, "isPremium still present");
  } catch (e) {
    assert("request succeeds", false, e.message);
  }

  // 4. POST /{model}/chat/completions
  console.log("\nPOST /gpt-4o-mini/chat/completions");
  try {
    const r = await req(AZURE_BASE, "POST", "/gpt-4o-mini/chat/completions", {
      body: {
        messages: [{ role: "user", content: "Say hi in 3 words" }],
        stream: false,
        max_tokens: 20,
      },
    });
    assert("status 200", r.status === 200, `got ${r.status}: ${JSON.stringify(r.data).slice(0, 200)}`);
    assert("has choices", Array.isArray(r.data?.choices), JSON.stringify(r.data).slice(0, 100));
    assert("choices[0] has message", !!r.data?.choices?.[0]?.message?.content, "no message content");
  } catch (e) {
    assert("request succeeds", false, e.message);
  }

  // 5. POST with invalid model
  console.log("\nPOST /invalid-model/chat/completions");
  try {
    const r = await req(AZURE_BASE, "POST", "/invalid-model/chat/completions", {
      body: { messages: [{ role: "user", content: "test" }], max_tokens: 5 },
    });
    assert("invalid model rejected (400)", r.status === 400, `got ${r.status}`);
  } catch (e) {
    assert("request succeeds", false, e.message);
  }

  // 6. POST premium model without X-Premium header
  console.log("\nPOST /gpt-5.4/chat/completions (no premium header)");
  try {
    const r = await req(AZURE_BASE, "POST", "/gpt-5.4/chat/completions", {
      body: { messages: [{ role: "user", content: "test" }], max_tokens: 5 },
    });
    assert("premium model rejected (403)", r.status === 403, `got ${r.status}`);
  } catch (e) {
    assert("request succeeds", false, e.message);
  }

  // 7. Auth test — request without signature
  console.log("\nPOST /gpt-4o-mini/chat/completions (no auth)");
  try {
    const noAuthRes = await fetch(`${AZURE_BASE}/gpt-4o-mini/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ messages: [{ role: "user", content: "test" }], max_tokens: 5 }),
    });
    assert("no-auth status 401", noAuthRes.status === 401, `got ${noAuthRes.status}`);
  } catch (e) {
    assert("no-auth request", false, e.message);
  }

  // 8. Auth test — expired timestamp
  console.log("\nPOST /gpt-4o-mini/chat/completions (expired timestamp)");
  try {
    const oldTimestamp = String(Math.floor(Date.now() / 1000) - 300);
    const oldSig = createHmac("sha256", Buffer.from(SECRET, "hex"))
      .update(`${oldTimestamp}:/gpt-4o-mini/chat/completions`)
      .digest("hex");
    const expiredRes = await fetch(`${AZURE_BASE}/gpt-4o-mini/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Timestamp": oldTimestamp,
        "X-Signature": oldSig,
      },
      body: JSON.stringify({ messages: [{ role: "user", content: "test" }], max_tokens: 5 }),
    });
    assert("expired timestamp rejected (401)", expiredRes.status === 401, `got ${expiredRes.status}`);
  } catch (e) {
    assert("expired timestamp test", false, e.message);
  }

  // 9. Verify marketplace route does NOT exist on Azure
  console.log("\nGET /marketplace/actions (should fail on Azure)");
  try {
    const r = await req(AZURE_BASE, "GET", "/marketplace/actions?page=1&limit=1&sort=newest");
    assert("not 200 (route doesn't exist here)", r.status !== 200, `unexpectedly got ${r.status}`);
  } catch (e) {
    assert("request fails or errors (expected)", true, "");
  }
}

// ── Cloudflare Worker Marketplace Tests ─────────────────────────────────────

async function testMarketplace() {
  console.log(`\n\x1b[1m═══ Cloudflare Worker (${WORKER_BASE}) ═══\x1b[0m\n`);

  // -- Models endpoint on Worker --
  console.log("GET /models (Worker)");
  try {
    const r = await req(WORKER_BASE, "GET", "/models");
    assert("status 200", r.status === 200, `got ${r.status}`);
    assert("returns models array", Array.isArray(r.data?.models), JSON.stringify(r.data).slice(0, 100));
    assert("has gpt-5.4-mini", r.data?.models?.some(m => m.id === "gpt-5.4-mini"), "model not found");
    assert("has model-router", r.data?.models?.some(m => m.id === "model-router"), "model not found");
    const router = r.data?.models?.find(m => m.id === "model-router");
    assert("model-router has 'low-latency' tag", router?.tags?.includes("low-latency"), `tags: ${JSON.stringify(router?.tags)}`);
  } catch (e) {
    assert("request succeeds", false, e.message);
  }

  // -- Marketplace CRUD --
  console.log("\n--- Marketplace CRUD ---\n");

  // 1. GET /marketplace/actions — list (possibly empty)
  console.log("GET /marketplace/actions");
  let r = await req(WORKER_BASE, "GET", "/marketplace/actions?page=1&limit=5&sort=newest");
  assert("status 200", r.status === 200, `got ${r.status}: ${JSON.stringify(r.data).slice(0, 200)}`);
  assert("has actions array", Array.isArray(r.data?.actions), JSON.stringify(r.data).slice(0, 100));
  assert("has has_more field", typeof r.data?.has_more === "boolean", JSON.stringify(r.data).slice(0, 100));

  // 2. GET with search query
  console.log("\nGET /marketplace/actions?q=test");
  r = await req(WORKER_BASE, "GET", "/marketplace/actions?q=test&page=1&limit=5&sort=newest");
  assert("search status 200", r.status === 200, `got ${r.status}`);
  assert("search returns array", Array.isArray(r.data?.actions), "");

  // 3. GET with category filter
  console.log("\nGET /marketplace/actions?category=translation");
  r = await req(WORKER_BASE, "GET", "/marketplace/actions?category=translation&page=1&limit=5&sort=newest");
  assert("category filter status 200", r.status === 200, `got ${r.status}`);

  // 4. GET with sort=popular
  console.log("\nGET /marketplace/actions?sort=popular");
  r = await req(WORKER_BASE, "GET", "/marketplace/actions?page=1&limit=5&sort=popular");
  assert("sort popular status 200", r.status === 200, `got ${r.status}`);

  // 5. POST /marketplace/actions — create
  console.log("\nPOST /marketplace/actions (create)");
  const createBody = {
    name: "API Test Action",
    prompt: "Translate {text} to French",
    action_description: "Test action created by test-api.mjs",
    output_type: "plain",
    usage_scenes: 7,
    category: "translation",
    author_name: "API Tester",
  };
  r = await req(WORKER_BASE, "POST", "/marketplace/actions", { body: createBody });
  assert("create status 201", r.status === 201, `got ${r.status}: ${JSON.stringify(r.data).slice(0, 200)}`);
  assert("returns action object", r.data?.action?.id, JSON.stringify(r.data).slice(0, 200));
  assert("creator_id stripped from response", !r.data?.action?.creator_id, `creator_id leaked: ${r.data?.action?.creator_id}`);

  const createdId = r.data?.action?.id;
  if (!createdId) {
    console.log("  \x1b[33m⚠ Skipping download/delete tests — no action ID\x1b[0m");
    return;
  }

  // 6. POST /marketplace/actions/:id/download — increment count
  console.log(`\nPOST /marketplace/actions/${createdId}/download`);
  r = await req(WORKER_BASE, "POST", `/marketplace/actions/${createdId}/download`);
  assert("download status 200", r.status === 200, `got ${r.status}: ${JSON.stringify(r.data).slice(0, 200)}`);
  assert("download_count >= 1", r.data?.download_count >= 1, `got ${r.data?.download_count}`);

  // 7. DELETE /marketplace/actions/:id — without X-User-ID match (should fail)
  console.log(`\nDELETE /marketplace/actions/${createdId} (wrong user)`);
  r = await req(WORKER_BASE, "DELETE", `/marketplace/actions/${createdId}`, {
    extraHeaders: { "X-User-ID": "wrong-user-id" },
  });
  assert("delete by non-owner status 403", r.status === 403, `got ${r.status}: ${JSON.stringify(r.data).slice(0, 200)}`);

  // 8. DELETE /marketplace/actions/:id — as owner
  console.log(`\nDELETE /marketplace/actions/${createdId} (owner)`);
  r = await req(WORKER_BASE, "DELETE", `/marketplace/actions/${createdId}`);
  assert("delete by owner status 200", r.status === 200, `got ${r.status}: ${JSON.stringify(r.data).slice(0, 200)}`);
  assert("deleted: true", r.data?.deleted === true, JSON.stringify(r.data));

  // 9. DELETE again — should 404
  console.log(`\nDELETE /marketplace/actions/${createdId} (already deleted)`);
  r = await req(WORKER_BASE, "DELETE", `/marketplace/actions/${createdId}`);
  assert("delete non-existent status 404", r.status === 404, `got ${r.status}`);

  // 10. POST /marketplace/actions — validation (missing name)
  console.log("\nPOST /marketplace/actions (missing name — validation)");
  r = await req(WORKER_BASE, "POST", "/marketplace/actions", {
    body: { prompt: "test" },
  });
  assert("validation status 400", r.status === 400, `got ${r.status}: ${JSON.stringify(r.data).slice(0, 200)}`);

  // 11. Auth test — request without signature
  console.log("\nGET /marketplace/actions (no auth)");
  try {
    const noAuthRes = await fetch(`${WORKER_BASE}/marketplace/actions?page=1&limit=1`, {
      headers: { Accept: "application/json" },
    });
    assert("no-auth status 401", noAuthRes.status === 401, `got ${noAuthRes.status}`);
  } catch (e) {
    assert("no-auth request", false, e.message);
  }
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log("\x1b[1m🔧 AITranslator API Test Suite\x1b[0m");
  console.log(`Secret: ${SECRET.slice(0, 6)}...${SECRET.slice(-4)}`);
  console.log(`Test User ID: ${TEST_USER_ID}`);

  await testAzure();
  await testMarketplace();

  console.log(`\n\x1b[1m═══ Results ═══\x1b[0m`);
  console.log(`  Passed: \x1b[32m${passed}\x1b[0m`);
  console.log(`  Failed: \x1b[31m${failed}\x1b[0m`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error("Fatal:", e);
  process.exit(2);
});
