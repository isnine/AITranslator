import { buildCheckoutParams } from "./billing";
import {
  buildCheckoutCompletedEntitlement,
  buildSubscriptionEntitlement,
  getBillingStatus,
  type BillingEntitlementRow,
  type BillingEntitlementUpsert,
} from "./billing-state";
import { normalizeApiPath } from "./routing";
import { verifyStripeWebhookSignature } from "./stripe-webhook";

/**
 * Cloudflare Worker that validates incoming requests with HMAC-SHA256 signature
 * before proxying them to Azure OpenAI using secrets stored in the environment.
 *
 * Security: Requests must include X-Timestamp and X-Signature headers.
 * The signature is HMAC-SHA256(secret, timestamp:path) and timestamp must be
 * within 120 seconds of current time.
 *
 * Routes:
 * - /tts - Text-to-Speech requests, proxied to TTS_ENDPOINT
 * - /{model}/chat/completions - LLM chat requests, proxied to AZURE_ENDPOINT
 */

interface Env {
  APP_SECRET: string;
  AZURE_ENDPOINT: string;
  AZURE_API_KEY: string;
  TTS_ENDPOINT: string;
  MARKETPLACE_DB: D1Database;
  ADMIN_PASSWORD: string;
  STRIPE_SECRET_KEY: string;
  STRIPE_MONTHLY_PRICE_ID?: string;
  STRIPE_YEARLY_PRICE_ID?: string;
  STRIPE_LIFETIME_PRICE_ID?: string;
  STRIPE_WEBHOOK_SECRET: string;
  CHECKOUT_SUCCESS_URL?: string;
  CHECKOUT_CANCEL_URL?: string;
  BILLING_PORTAL_RETURN_URL?: string;
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
}

interface AuthResult {
  valid: boolean;
  reason?: string;
}

const TIMESTAMP_TOLERANCE_SECONDS = 120;

// Allowed models for the built-in cloud service
const ALLOWED_MODELS = [
  // Free tier
  "gpt-4o-mini",
  "gpt-4.1-mini",
  "gpt-4.1-nano",
  "gpt-5-nano",
  "gpt-5-mini",
  "gpt-5.4-mini",
  "gpt-5.4-nano",
  // Premium tier
  "gpt-5.4",
  "gpt-5.2-chat",
  "gpt-5",
  "gpt-4.1",
  "gpt-4o",
  "o4-mini",
  "o3-mini",
  // Hidden (allowed but not listed)
  "model-router",
];

// Premium models require an active subscription
const PREMIUM_MODELS = new Set([
  "gpt-5.4",
  "gpt-5.2-chat",
  "gpt-5",
  "gpt-4.1",
  "gpt-4o",
  "o4-mini",
  "o3-mini",
  "model-router",
]);

interface ModelInfo {
  id: string;
  displayName: string;
  isDefault: boolean;
  isPremium: boolean;
  supportsVision: boolean;
  tags?: string[];
  hidden?: boolean;
}

const MODELS_LIST: ModelInfo[] = [
  // Free tier models
  { id: "gpt-5.4-mini", displayName: "GPT-5.4 Mini", isDefault: false, isPremium: false, supportsVision: true, tags: ["latest"] },
  { id: "gpt-5.4-nano", displayName: "GPT-5.4 Nano", isDefault: true, isPremium: false, supportsVision: true, tags: ["latest"] },
  { id: "gpt-5-mini", displayName: "GPT-5 Mini", isDefault: false, isPremium: false, supportsVision: true },
  { id: "gpt-5-nano", displayName: "GPT-5 Nano", isDefault: false, isPremium: false, supportsVision: true },
  { id: "gpt-4.1-nano", displayName: "GPT-4.1 Nano", isDefault: false, isPremium: false, supportsVision: true, hidden: true },
  { id: "gpt-4.1-mini", displayName: "GPT-4.1 Mini", isDefault: false, isPremium: false, supportsVision: true, hidden: true },
  { id: "gpt-4o-mini", displayName: "GPT-4o Mini", isDefault: false, isPremium: false, supportsVision: true, hidden: true },
  // Premium tier models
  { id: "gpt-5.4", displayName: "GPT-5.4", isDefault: false, isPremium: true, supportsVision: true, tags: ["latest"] },
  { id: "gpt-5.2-chat", displayName: "GPT-5.2 Chat", isDefault: false, isPremium: true, supportsVision: true },
  { id: "gpt-5", displayName: "GPT-5", isDefault: false, isPremium: true, supportsVision: true },
  { id: "gpt-4.1", displayName: "GPT-4.1", isDefault: false, isPremium: true, supportsVision: true },
  { id: "gpt-4o", displayName: "GPT-4o", isDefault: false, isPremium: true, supportsVision: true, hidden: true },
  { id: "o4-mini", displayName: "o4 Mini", isDefault: false, isPremium: true, supportsVision: true },
  { id: "o3-mini", displayName: "o3 Mini", isDefault: false, isPremium: true, supportsVision: false, hidden: true },
  { id: "model-router", displayName: "Model Router", isDefault: false, isPremium: true, supportsVision: true, tags: ["low-latency"] },
];

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "Content-Type, api-key, Authorization, Accept, Accept-Language, X-Timestamp, X-Signature, X-Premium, X-User-ID, X-Admin-Password, Stripe-Signature",
  "Access-Control-Allow-Methods": "GET,HEAD,POST,PUT,DELETE,OPTIONS",
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return buildResponse(null, 204, undefined);
    }

    const url = new URL(request.url);
    const path = normalizeApiPath(url.pathname);

    // Route: /models - Return available models list (no auth required)
    if (path === "/models") {
      return handleModelsRequest(url);
    }

    // Route: /web - Serve Marketplace Web UI (no HMAC required)
    if (path === "/web" || path === "/web/") {
      return serveWebApp();
    }

    // Public legal & support pages (no auth) — required by payment providers
    // (Creem / Stripe) so that ToS, Privacy Policy and a support email are
    // reachable from the site footer/navigation.
    if (path === "/terms" || path === "/terms/") {
      return serveStaticHtml(TERMS_HTML);
    }
    if (path === "/privacy" || path === "/privacy/") {
      return serveStaticHtml(PRIVACY_HTML);
    }
    if (path === "/support" || path === "/support/") {
      return serveStaticHtml(SUPPORT_HTML);
    }

    // Route: /web/api/* - Web API endpoints (no HMAC, direct D1 access)
    if (path.startsWith("/web/api/")) {
      return handleWebAPI(request, env, path);
    }

    // Route: /billing/webhook - Stripe webhook endpoint (Stripe signature, no HMAC)
    if (path === "/billing/webhook") {
      return handleBillingWebhook(request, env);
    }

    // Route: /billing/checkout - Create a Stripe Managed Payments Checkout Session
    if (path === "/billing/checkout") {
      return handleBillingCheckout(request, env);
    }

    if (path === "/billing/status") {
      return handleBillingStatus(request, env);
    }

    if (path === "/billing/portal") {
      return handleBillingPortal(request, env);
    }

    // Validate HMAC signature for all other routes
    const authResult = await isAuthorized(request, env.APP_SECRET, path);
    if (!authResult.valid) {
      return buildResponse(
        JSON.stringify({ error: "Unauthorized", reason: authResult.reason }),
        401,
        "application/json"
      );
    }

    // Route: /tts - Text-to-Speech
    if (path === "/tts") {
      return handleTTSRequest(request, env);
    }

    // Route: /voice-to-action - Generate ActionConfig from voice transcript
    if (path === "/voice-to-action") {
      return handleVoiceToActionRequest(request, env);
    }

    // Route: /marketplace/actions - List or create marketplace actions
    if (path === "/marketplace/actions") {
      if (request.method === "GET") {
        return handleListActions(request, env);
      }
      if (request.method === "POST") {
        return handleCreateAction(request, env);
      }
    }

    // Route: /marketplace/actions/:id/download - Increment download count
    const downloadMatch = path.match(/^\/marketplace\/actions\/([^/]+)\/download$/);
    if (downloadMatch && request.method === "POST") {
      return handleIncrementDownload(env, downloadMatch[1]);
    }

    // Route: /marketplace/actions/:id - Delete a marketplace action
    const actionIdMatch = path.match(/^\/marketplace\/actions\/([^/]+)$/);
    if (actionIdMatch && request.method === "DELETE") {
      return handleDeleteAction(request, env, actionIdMatch[1]);
    }

    // Route: /{model}/chat/completions - LLM Chat
    return handleLLMRequest(request, env);
  },
};

function handleModelsRequest(url: URL): Response {
  const includePremium = url.searchParams.get("premium") === "1";
  const models = includePremium
    ? MODELS_LIST
    : MODELS_LIST.filter((m) => !m.isPremium).map(({ isPremium, ...rest }) => rest);
  return buildResponse(
    JSON.stringify({ models }),
    200,
    "application/json"
  );
}

// MARK: - TTS Handler

async function handleTTSRequest(request: Request, env: Env): Promise<Response> {
  // Get client IP from CF headers
  const clientIP = request.headers.get("CF-Connecting-IP") || "unknown";

  // Log the TTS request with IP
  console.log(`TTS Request - IP: ${clientIP}`);

  try {
    if (!env.TTS_ENDPOINT) {
      return buildResponse(
        JSON.stringify({
          error: "Configuration error",
          message: "TTS_ENDPOINT not configured",
        }),
        500,
        "application/json"
      );
    }

    const ttsURL = new URL(env.TTS_ENDPOINT);
    const forwardHeaders = cloneHeaders(request.headers);

    // Remove signature headers before forwarding
    forwardHeaders.delete("X-Timestamp");
    forwardHeaders.delete("X-Signature");

    // Set Azure API key
    forwardHeaders.set("api-key", env.AZURE_API_KEY);
    forwardHeaders.set("host", ttsURL.host);

    const upstreamResponse = await fetch(ttsURL.toString(), {
      method: request.method,
      headers: forwardHeaders,
      body: shouldHaveBody(request.method) ? request.body : null,
      redirect: "manual",
    });

    const responseHeaders = new Headers(upstreamResponse.headers);
    applyCors(responseHeaders);

    return new Response(upstreamResponse.body, {
      status: upstreamResponse.status,
      headers: responseHeaders,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return buildResponse(
      JSON.stringify({ error: "TTS request failed", message }),
      502,
      "application/json"
    );
  }
}

// MARK: - LLM Handler

async function handleLLMRequest(request: Request, env: Env): Promise<Response> {
  // Extract and validate the model from the request path
  const url = new URL(request.url);
  const pathParts = normalizeApiPath(url.pathname).split("/").filter(Boolean);
  const requestedModel = pathParts[0];

  // Get client IP from CF headers
  const clientIP = request.headers.get("CF-Connecting-IP") || "unknown";

  // Log the request with model and IP
  console.log(`LLM Request - Model: ${requestedModel}, IP: ${clientIP}`);

  if (!requestedModel || !ALLOWED_MODELS.includes(requestedModel)) {
    return buildResponse(
      JSON.stringify({
        error: "Invalid model",
        message: `Model '${requestedModel}' is not allowed. Allowed models: ${ALLOWED_MODELS.join(
          ", "
        )}`,
      }),
      400,
      "application/json"
    );
  }

  // Validate premium access for premium models
  if (PREMIUM_MODELS.has(requestedModel)) {
    const hasPremium = await hasPremiumAccess(request, env);
    if (!hasPremium) {
      return buildResponse(
        JSON.stringify({
          error: "Premium required",
          message: `Model '${requestedModel}' requires a premium subscription.`,
        }),
        403,
        "application/json"
      );
    }
  }

  try {
    if (!env.AZURE_ENDPOINT) {
      return buildResponse(
        JSON.stringify({
          error: "Configuration error",
          message: "AZURE_ENDPOINT not configured",
        }),
        500,
        "application/json"
      );
    }

    const targetURL = buildAzureURL(request, env.AZURE_ENDPOINT);
    const forwardHeaders = cloneHeaders(request.headers);

    // Remove signature headers before forwarding
    forwardHeaders.delete("X-Timestamp");
    forwardHeaders.delete("X-Signature");

    forwardHeaders.set("api-key", env.AZURE_API_KEY);
    forwardHeaders.set("host", targetURL.host);

    const upstreamStart = Date.now();
    const upstreamResponse = await fetch(targetURL.toString(), {
      method: request.method,
      headers: forwardHeaders,
      body: shouldHaveBody(request.method) ? request.body : null,
      redirect: "manual",
    });
    const upstreamTTFB = Date.now() - upstreamStart;

    const responseHeaders = new Headers(upstreamResponse.headers);
    applyCors(responseHeaders);
    responseHeaders.set("X-Upstream-TTFB", upstreamTTFB.toString());

    return new Response(upstreamResponse.body, {
      status: upstreamResponse.status,
      headers: responseHeaders,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return buildResponse(
      JSON.stringify({ error: "Upstream request failed", message }),
      502,
      "application/json"
    );
  }
}

// MARK: - Voice-to-Action Handler

async function handleVoiceToActionRequest(request: Request, env: Env): Promise<Response> {
  const clientIP = request.headers.get("CF-Connecting-IP") || "unknown";
  console.log(`Voice-to-Action Request - IP: ${clientIP}`);

  try {
    if (request.method !== "POST") {
      return buildResponse(
        JSON.stringify({ error: "Method not allowed" }),
        405,
        "application/json"
      );
    }

    const body = (await request.json()) as { transcript?: string; locale?: string };
    if (!body.transcript || body.transcript.trim().length === 0) {
      return buildResponse(
        JSON.stringify({ error: "transcript is required" }),
        400,
        "application/json"
      );
    }

    const transcript = body.transcript.trim();
    const locale = body.locale || "en";

    // Build Azure OpenAI request
    const azureURL = new URL(env.AZURE_ENDPOINT);
    const basePath = azureURL.pathname.replace(/\/+$/, "");
    azureURL.pathname = `${basePath}/gpt-4o-mini/chat/completions`;
    const searchParams = new URLSearchParams(azureURL.search);
    if (!searchParams.has("api-version")) {
      searchParams.set("api-version", "2025-01-01-preview");
    }
    azureURL.search = searchParams.toString();

    const systemPrompt = `You are an assistant that generates translation action configurations for a translation app called TLingo.

The user will describe a translation action they want in natural language. Generate 2-3 options as structured JSON.

Each option must have:
- title: Short name for the action (in the user's language: ${locale})
- description: One-line description (in the user's language)
- action_config: Object with:
  - name: Display name for the action
  - prompt: The prompt template. MUST include {text} placeholder. May include {targetLanguage} if relevant.
  - output_type: One of "plain", "diff", "sentencePairs", "grammarCheck"
  - usage_scenes: Array from ["app", "contextRead", "contextEdit"]. Default to all three.

Generate options that vary in specificity or approach. For example, one literal and one more creative interpretation.

Return ONLY valid JSON matching this schema:
{
  "options": [{ "title": "...", "description": "...", "action_config": { "name": "...", "prompt": "...", "output_type": "...", "usage_scenes": [...] } }],
  "allow_custom_input": true
}`;

    const llmPayload = {
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: transcript },
      ],
      temperature: 0.7,
      max_tokens: 1000,
      response_format: { type: "json_object" },
    };

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000);

    const llmResponse = await fetch(azureURL.toString(), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "api-key": env.AZURE_API_KEY,
      },
      body: JSON.stringify(llmPayload),
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!llmResponse.ok) {
      const errorBody = await llmResponse.text();
      console.error(`Azure OpenAI error: ${llmResponse.status} - ${errorBody}`);
      return buildResponse(
        JSON.stringify({ error: "Failed to generate options", detail: `Azure OpenAI returned ${llmResponse.status}` }),
        500,
        "application/json"
      );
    }

    const llmResult = (await llmResponse.json()) as { choices?: { message?: { content?: string } }[] };
    const content = llmResult.choices?.[0]?.message?.content;

    if (!content) {
      return buildResponse(
        JSON.stringify({ error: "Failed to generate options", detail: "Empty response from model" }),
        500,
        "application/json"
      );
    }

    // Parse and validate the JSON response
    let parsed;
    try {
      parsed = JSON.parse(content);
    } catch {
      return buildResponse(
        JSON.stringify({ error: "Failed to parse model response", detail: "Invalid JSON" }),
        500,
        "application/json"
      );
    }

    // Ensure options array exists
    if (!Array.isArray(parsed.options)) {
      parsed = { options: [], allow_custom_input: true };
    }

    const responseHeaders = new Headers();
    applyCors(responseHeaders);
    responseHeaders.set("Content-Type", "application/json");

    return new Response(JSON.stringify(parsed), {
      status: 200,
      headers: responseHeaders,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      return buildResponse(
        JSON.stringify({ error: "Request timed out" }),
        504,
        "application/json"
      );
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    return buildResponse(
      JSON.stringify({ error: "Voice-to-action request failed", message }),
      502,
      "application/json"
    );
  }
}

// MARK: - Marketplace Handlers

const VALID_CATEGORIES = new Set(["translation", "writing", "analysis", "other"]);
const VALID_OUTPUT_TYPES = new Set(["plain", "diff", "sentencePairs", "grammarCheck"]);

async function handleListActions(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const q = url.searchParams.get("q") || "";
  const category = url.searchParams.get("category");
  const sort = url.searchParams.get("sort") || "newest";
  const page = Math.max(1, parseInt(url.searchParams.get("page") || "1", 10) || 1);
  const limit = Math.min(50, Math.max(1, parseInt(url.searchParams.get("limit") || "20", 10) || 20));
  const offset = (page - 1) * limit;

  const conditions: string[] = [];
  const bindings: unknown[] = [];

  if (q) {
    conditions.push("(name LIKE ?1 OR action_description LIKE ?1 OR author_name LIKE ?1)");
    bindings.push(`%${q}%`);
  }

  if (category && VALID_CATEGORIES.has(category)) {
    bindings.push(category);
    conditions.push(`category = ?${bindings.length}`);
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
  const orderBy = sort === "popular" ? "download_count DESC" : "created_at DESC";

  try {
    const countResult = await env.MARKETPLACE_DB
      .prepare(`SELECT COUNT(*) as total FROM marketplace_actions ${where}`)
      .bind(...bindings)
      .first<{ total: number }>();

    const totalCount = countResult?.total ?? 0;
    const totalPages = Math.ceil(totalCount / limit) || 1;

    const rows = await env.MARKETPLACE_DB
      .prepare(`SELECT * FROM marketplace_actions ${where} ORDER BY ${orderBy} LIMIT ?${bindings.length + 1} OFFSET ?${bindings.length + 2}`)
      .bind(...bindings, limit, offset)
      .all();

    // Strip creator_id from public responses to prevent impersonation
    const sanitizedActions = rows.results.map(({ creator_id, ...rest }) => rest);

    return buildResponse(
      JSON.stringify({
        actions: sanitizedActions,
        page,
        total_pages: totalPages,
        total_count: totalCount,
        has_more: page < totalPages,
      }),
      200,
      "application/json"
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return buildResponse(
      JSON.stringify({ error: "Database query failed", message }),
      500,
      "application/json"
    );
  }
}

async function handleCreateAction(request: Request, env: Env): Promise<Response> {
  try {
    const body = (await request.json()) as Record<string, unknown>;

    const name = body.name as string;
    const prompt = body.prompt as string;
    if (!name || !prompt) {
      return buildResponse(
        JSON.stringify({ error: "name and prompt are required" }),
        400,
        "application/json"
      );
    }

    const actionDescription = (body.action_description as string) || "";
    const outputType = VALID_OUTPUT_TYPES.has(body.output_type as string) ? (body.output_type as string) : "plain";
    const usageScenes = typeof body.usage_scenes === "number" ? body.usage_scenes : 7;
    const category = VALID_CATEGORIES.has(body.category as string) ? (body.category as string) : "other";
    const authorName = (body.author_name as string) || "Anonymous";
    const creatorId = request.headers.get("X-User-ID") || null;

    const result = await env.MARKETPLACE_DB
      .prepare(
        `INSERT INTO marketplace_actions (name, prompt, action_description, output_type, usage_scenes, category, author_name, creator_id)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
         RETURNING *`
      )
      .bind(name, prompt, actionDescription, outputType, usageScenes, category, authorName, creatorId)
      .first();

    if (!result) {
      return buildResponse(
        JSON.stringify({ error: "Failed to create action" }),
        500,
        "application/json"
      );
    }

    // Strip creator_id from response
    const { creator_id, ...publicAction } = result as Record<string, unknown>;

    return buildResponse(
      JSON.stringify({ action: publicAction }),
      201,
      "application/json"
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return buildResponse(
      JSON.stringify({ error: "Failed to create action", message }),
      500,
      "application/json"
    );
  }
}

async function handleDeleteAction(request: Request, env: Env, actionId: string): Promise<Response> {
  const userId = request.headers.get("X-User-ID");
  if (!userId) {
    return buildResponse(
      JSON.stringify({ error: "X-User-ID header required" }),
      400,
      "application/json"
    );
  }

  try {
    const row = await env.MARKETPLACE_DB
      .prepare("SELECT creator_id FROM marketplace_actions WHERE id = ?1")
      .bind(actionId)
      .first<{ creator_id: string | null }>();

    if (!row) {
      return buildResponse(
        JSON.stringify({ error: "Action not found" }),
        404,
        "application/json"
      );
    }

    if (row.creator_id !== userId) {
      return buildResponse(
        JSON.stringify({ error: "Not the owner of this action" }),
        403,
        "application/json"
      );
    }

    await env.MARKETPLACE_DB
      .prepare("DELETE FROM marketplace_actions WHERE id = ?1")
      .bind(actionId)
      .run();

    return buildResponse(
      JSON.stringify({ deleted: true }),
      200,
      "application/json"
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return buildResponse(
      JSON.stringify({ error: "Failed to delete action", message }),
      500,
      "application/json"
    );
  }
}

async function handleIncrementDownload(env: Env, actionId: string): Promise<Response> {
  try {
    const result = await env.MARKETPLACE_DB
      .prepare(
        "UPDATE marketplace_actions SET download_count = download_count + 1 WHERE id = ?1 RETURNING download_count"
      )
      .bind(actionId)
      .first<{ download_count: number }>();

    if (!result) {
      return buildResponse(
        JSON.stringify({ error: "Action not found" }),
        404,
        "application/json"
      );
    }

    return buildResponse(
      JSON.stringify({ download_count: result.download_count }),
      200,
      "application/json"
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return buildResponse(
      JSON.stringify({ error: "Failed to increment download count", message }),
      500,
      "application/json"
    );
  }
}

async function isAuthorized(
  request: Request,
  secret: string,
  path: string
): Promise<AuthResult> {
  const timestamp = request.headers.get("X-Timestamp");
  const signature = request.headers.get("X-Signature");

  if (!timestamp || !signature) {
    return { valid: false, reason: "Missing timestamp or signature" };
  }

  // Validate timestamp is within tolerance
  const requestTime = parseInt(timestamp, 10);
  if (isNaN(requestTime)) {
    return { valid: false, reason: "Invalid timestamp format" };
  }

  const currentTime = Math.floor(Date.now() / 1000);
  const timeDiff = Math.abs(currentTime - requestTime);

  if (timeDiff > TIMESTAMP_TOLERANCE_SECONDS) {
    return { valid: false, reason: "Timestamp expired" };
  }

  // Compute expected signature: HMAC-SHA256(secret, timestamp:path)
  const message = `${timestamp}:${path}`;
  const expectedSignature = await computeHmacSha256(secret, message);

  // Constant-time comparison
  if (signature.toLowerCase() !== expectedSignature.toLowerCase()) {
    return { valid: false, reason: "Invalid signature" };
  }

  return { valid: true };
}

async function computeHmacSha256(
  secretHex: string,
  message: string
): Promise<string> {
  // Convert hex string to ArrayBuffer
  const keyBuffer = hexToArrayBuffer(secretHex);
  const key = await crypto.subtle.importKey(
    "raw",
    keyBuffer,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const messageBytes = new TextEncoder().encode(message);
  const signatureBuffer = await crypto.subtle.sign("HMAC", key, messageBytes);

  return bytesToHex(new Uint8Array(signatureBuffer));
}

function hexToArrayBuffer(hex: string): ArrayBuffer {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
  }
  return bytes.buffer as ArrayBuffer;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b: number) => b.toString(16).padStart(2, "0"))
    .join("");
}

function shouldHaveBody(method: string): boolean {
  return !["GET", "HEAD"].includes(method.toUpperCase());
}

function buildAzureURL(request: Request, azureEndpoint: string): URL {
  const incomingURL = new URL(request.url);
  const baseURL = new URL(azureEndpoint);

  const normalizedBasePath = baseURL.pathname.replace(/\/+$/, "");
  const incomingPath = normalizeApiPath(incomingURL.pathname).replace(/^\/+/, "");

  const combinedPath = [normalizedBasePath, incomingPath]
    .filter(Boolean)
    .join("/");

  baseURL.pathname = `/${combinedPath}`.replace(/\/{2,}/g, "/");
  baseURL.search = incomingURL.search;

  // Add api-version if not present
  const searchParams = new URLSearchParams(baseURL.search);
  if (!searchParams.has("api-version")) {
    searchParams.set("api-version", "2025-01-01-preview");
  }
  baseURL.search = searchParams.toString();

  return baseURL;
}

function cloneHeaders(headers: Headers): Headers {
  const clone = new Headers();
  headers.forEach((value: string, key: string) => {
    if (!key.toLowerCase().startsWith("cf-")) {
      clone.append(key, value);
    }
  });
  return clone;
}

function applyCors(headers: Headers): void {
  Object.entries(CORS_HEADERS).forEach(([key, value]) => {
    headers.set(key, value);
  });
}

function buildResponse(
  body: string | null,
  status: number,
  contentType: string | undefined
): Response {
  const headers = new Headers();
  applyCors(headers);

  if (contentType) {
    headers.set("Content-Type", contentType);
  }

  return new Response(body, { status, headers });
}

interface SupabaseUser {
  id: string;
  email?: string;
}

function getBearerToken(request: Request): string | null {
  const header = request.headers.get("Authorization");
  const match = header?.match(/^Bearer\s+(.+)$/i);
  return match?.[1] ?? null;
}

function requireSupabaseConfig(env: Env): Response | null {
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY || !env.SUPABASE_SERVICE_ROLE_KEY) {
    return buildResponse(
      JSON.stringify({ error: "Supabase is not configured" }),
      500,
      "application/json"
    );
  }
  return null;
}

async function validateSupabaseUser(request: Request, env: Env): Promise<SupabaseUser | Response> {
  const configError = requireSupabaseConfig(env);
  if (configError) return configError;
  const token = getBearerToken(request);
  if (!token) {
    return buildResponse(JSON.stringify({ error: "Authentication required" }), 401, "application/json");
  }

  const response = await fetch(`${env.SUPABASE_URL.replace(/\/+$/, "")}/auth/v1/user`, {
    headers: {
      apikey: env.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${token}`,
    },
  });

  if (!response.ok) {
    return buildResponse(JSON.stringify({ error: "Invalid session" }), 401, "application/json");
  }

  const user = (await response.json().catch(() => null)) as { id?: string; email?: string } | null;
  if (!user?.id) {
    return buildResponse(JSON.stringify({ error: "Invalid session" }), 401, "application/json");
  }
  return { id: user.id, email: user.email };
}

function supabaseRestURL(env: Env, table: string, query = ""): string {
  const base = env.SUPABASE_URL.replace(/\/+$/, "");
  return `${base}/rest/v1/${table}${query}`;
}

function supabaseServiceHeaders(env: Env): HeadersInit {
  return {
    apikey: env.SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
    "Content-Type": "application/json",
  };
}

async function getEntitlementByUser(
  env: Env,
  userId: string
): Promise<BillingEntitlementRow | null> {
  const query = `?select=*&user_id=eq.${encodeURIComponent(userId)}&limit=1`;
  const response = await fetch(supabaseRestURL(env, "billing_entitlements", query), {
    headers: supabaseServiceHeaders(env),
  });
  if (!response.ok) throw new Error(`Supabase entitlement lookup failed: ${response.status}`);
  const rows = (await response.json().catch(() => [])) as BillingEntitlementRow[];
  return rows[0] ?? null;
}

async function upsertEntitlement(env: Env, row: BillingEntitlementUpsert): Promise<void> {
  const response = await fetch(
    supabaseRestURL(env, "billing_entitlements", "?on_conflict=user_id"),
    {
      method: "POST",
      headers: {
        ...supabaseServiceHeaders(env),
        Prefer: "resolution=merge-duplicates",
      },
      body: JSON.stringify({ ...row, updated_at: new Date().toISOString() }),
    }
  );
  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    throw new Error(`Supabase entitlement upsert failed: ${response.status} ${detail}`);
  }
}

async function hasPremiumAccess(request: Request, env: Env): Promise<boolean> {
  const token = getBearerToken(request);

  if (token) {
    if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY || !env.SUPABASE_SERVICE_ROLE_KEY) {
      return false;
    }
    const user = await validateSupabaseUser(request, env);
    if (user instanceof Response) {
      return false;
    }
    const entitlement = await getEntitlementByUser(env, user.id);
    return getBillingStatus(entitlement).isPremium;
  }

  // Legacy iOS path: HMAC-signed requests without a Supabase session.
  // Trusted only because route-level HMAC verification (see request handler)
  // already proved the request originates from a real client build.
  // Remove once the iOS app sends Supabase Bearer tokens.
  return request.headers.get("X-Premium") === "true";
}

async function handleBillingCheckout(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") {
    return buildResponse(JSON.stringify({ error: "Method not allowed" }), 405, "application/json");
  }

  const user = await validateSupabaseUser(request, env);
  if (user instanceof Response) return user;

  if (!env.STRIPE_SECRET_KEY) {
    return buildResponse(
      JSON.stringify({ error: "Stripe is not configured" }),
      500,
      "application/json"
    );
  }

  let params: URLSearchParams;
  try {
    const body = (await request.json()) as { plan?: unknown };
    const entitlement = await getEntitlementByUser(env, user.id);
    params = buildCheckoutParams(
      {
        plan: body.plan,
        customerEmail: entitlement?.stripe_customer_id ? undefined : user.email,
        userId: user.id,
      },
      {
        monthlyPriceId: env.STRIPE_MONTHLY_PRICE_ID,
        yearlyPriceId: env.STRIPE_YEARLY_PRICE_ID,
        lifetimePriceId: env.STRIPE_LIFETIME_PRICE_ID,
        successUrl: env.CHECKOUT_SUCCESS_URL,
        cancelUrl: env.CHECKOUT_CANCEL_URL,
      }
    );
    if (entitlement?.stripe_customer_id) {
      params.set("customer", entitlement.stripe_customer_id);
      params.delete("customer_email");
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "Invalid request";
    return buildResponse(JSON.stringify({ error: message }), 400, "application/json");
  }

  const stripeResponse = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
      "Stripe-Version": "2026-02-25.preview",
    },
    body: params,
  });

  const stripeBody = (await stripeResponse.json().catch(() => null)) as
    | { url?: string; id?: string; error?: { message?: string } }
    | null;

  if (!stripeResponse.ok || !stripeBody?.url) {
    const message = stripeBody?.error?.message || "Failed to create Checkout Session";
    return buildResponse(
      JSON.stringify({ error: message }),
      stripeResponse.ok ? 502 : stripeResponse.status,
      "application/json"
    );
  }

  return buildResponse(
    JSON.stringify({ url: stripeBody.url, sessionId: stripeBody.id }),
    200,
    "application/json"
  );
}

async function handleBillingStatus(request: Request, env: Env): Promise<Response> {
  if (request.method !== "GET") {
    return buildResponse(JSON.stringify({ error: "Method not allowed" }), 405, "application/json");
  }
  const user = await validateSupabaseUser(request, env);
  if (user instanceof Response) return user;
  const entitlement = await getEntitlementByUser(env, user.id);
  return buildResponse(JSON.stringify(getBillingStatus(entitlement)), 200, "application/json");
}

async function handleBillingPortal(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") {
    return buildResponse(JSON.stringify({ error: "Method not allowed" }), 405, "application/json");
  }
  const user = await validateSupabaseUser(request, env);
  if (user instanceof Response) return user;
  const entitlement = await getEntitlementByUser(env, user.id);
  if (!entitlement?.stripe_customer_id) {
    return buildResponse(JSON.stringify({ error: "No Stripe customer found" }), 404, "application/json");
  }

  const params = new URLSearchParams();
  params.set("customer", entitlement.stripe_customer_id);
  params.set("return_url", env.BILLING_PORTAL_RETURN_URL || "https://tlingo.zanderwang.com/");

  const stripeResponse = await fetch("https://api.stripe.com/v1/billing_portal/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
      "Stripe-Version": "2026-02-25.preview",
    },
    body: params,
  });
  const stripeBody = (await stripeResponse.json().catch(() => null)) as
    | { url?: string; error?: { message?: string } }
    | null;
  if (!stripeResponse.ok || !stripeBody?.url) {
    return buildResponse(
      JSON.stringify({ error: stripeBody?.error?.message || "Failed to create billing portal session" }),
      stripeResponse.ok ? 502 : stripeResponse.status,
      "application/json"
    );
  }
  return buildResponse(JSON.stringify({ url: stripeBody.url }), 200, "application/json");
}

async function handleBillingWebhook(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") {
    return buildResponse(JSON.stringify({ error: "Method not allowed" }), 405, "application/json");
  }
  if (!env.STRIPE_WEBHOOK_SECRET) {
    return buildResponse(JSON.stringify({ error: "Stripe webhook is not configured" }), 500, "application/json");
  }
  const payload = await request.text();
  const signature = request.headers.get("Stripe-Signature");
  if (!signature || !(await verifyStripeWebhookSignature(payload, signature, env.STRIPE_WEBHOOK_SECRET))) {
    return buildResponse(JSON.stringify({ error: "Invalid Stripe signature" }), 400, "application/json");
  }

  const event = JSON.parse(payload) as { id: string; type: string; data: { object: unknown } };
  let entitlement: BillingEntitlementUpsert | null = null;
  if (event.type === "checkout.session.completed" || event.type === "checkout.session.async_payment_succeeded") {
    entitlement = buildCheckoutCompletedEntitlement(event.data.object as never);
  } else if (
    event.type === "customer.subscription.created" ||
    event.type === "customer.subscription.updated" ||
    event.type === "customer.subscription.deleted"
  ) {
    entitlement = buildSubscriptionEntitlement(event.data.object as never);
  } else if (event.type === "invoice.payment_succeeded") {
    const invoice = event.data.object as { subscription?: string | { id?: string } | null };
    const subscriptionId =
      typeof invoice.subscription === "string" ? invoice.subscription : invoice.subscription?.id;
    if (subscriptionId) {
      const subscription = await retrieveStripeSubscription(env, subscriptionId);
      entitlement = buildSubscriptionEntitlement(subscription as never);
    }
  }
  if (entitlement) {
    await upsertEntitlement(env, { ...entitlement, last_event_id: event.id });
  }
  return buildResponse(JSON.stringify({ received: true }), 200, "application/json");
}

async function retrieveStripeSubscription(env: Env, subscriptionId: string): Promise<unknown> {
  const response = await fetch(`https://api.stripe.com/v1/subscriptions/${subscriptionId}`, {
    headers: {
      Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      "Stripe-Version": "2026-02-25.preview",
    },
  });
  if (!response.ok) throw new Error(`Failed to retrieve Stripe subscription: ${response.status}`);
  return response.json();
}

// MARK: - Web Marketplace UI

function isAdminAuthorized(request: Request, env: Env): boolean {
  const password = request.headers.get("X-Admin-Password");
  if (!password || !env.ADMIN_PASSWORD) return false;
  return password === env.ADMIN_PASSWORD;
}

async function handleWebAPI(request: Request, env: Env, path: string): Promise<Response> {
  // POST /web/api/admin/verify
  if (path === "/web/api/admin/verify" && request.method === "POST") {
    return handleAdminVerify(request, env);
  }

  // GET /web/api/actions — list actions
  if (path === "/web/api/actions" && request.method === "GET") {
    return handleWebListActions(request, env);
  }

  // POST /web/api/actions — create action
  if (path === "/web/api/actions" && request.method === "POST") {
    return handleWebCreateAction(request, env);
  }

  // PUT /web/api/actions/:id or DELETE /web/api/actions/:id — admin only
  const actionIdMatch = path.match(/^\/web\/api\/actions\/([^/]+)$/);
  if (actionIdMatch) {
    if (!isAdminAuthorized(request, env)) {
      return buildResponse(JSON.stringify({ error: "Admin password required" }), 403, "application/json");
    }
    if (request.method === "PUT") {
      return handleWebUpdateAction(request, env, actionIdMatch[1]);
    }
    if (request.method === "DELETE") {
      return handleWebDeleteAction(env, actionIdMatch[1]);
    }
  }

  return buildResponse(JSON.stringify({ error: "Not found" }), 404, "application/json");
}

async function handleAdminVerify(request: Request, env: Env): Promise<Response> {
  try {
    const body = (await request.json()) as { password?: string };
    if (!body.password || !env.ADMIN_PASSWORD) {
      return buildResponse(JSON.stringify({ valid: false }), 200, "application/json");
    }
    const valid = body.password === env.ADMIN_PASSWORD;
    return buildResponse(JSON.stringify({ valid }), 200, "application/json");
  } catch {
    return buildResponse(JSON.stringify({ valid: false }), 200, "application/json");
  }
}

async function handleWebListActions(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const q = url.searchParams.get("q") || "";
  const category = url.searchParams.get("category");
  const sort = url.searchParams.get("sort") || "newest";
  const page = Math.max(1, parseInt(url.searchParams.get("page") || "1", 10) || 1);
  const limit = Math.min(50, Math.max(1, parseInt(url.searchParams.get("limit") || "20", 10) || 20));
  const offset = (page - 1) * limit;

  const conditions: string[] = [];
  const bindings: unknown[] = [];

  if (q) {
    conditions.push("(name LIKE ?1 OR action_description LIKE ?1 OR author_name LIKE ?1)");
    bindings.push(`%${q}%`);
  }

  if (category && VALID_CATEGORIES.has(category)) {
    bindings.push(category);
    conditions.push(`category = ?${bindings.length}`);
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
  const orderBy = sort === "popular" ? "download_count DESC" : "created_at DESC";

  try {
    const countResult = await env.MARKETPLACE_DB
      .prepare(`SELECT COUNT(*) as total FROM marketplace_actions ${where}`)
      .bind(...bindings)
      .first<{ total: number }>();

    const totalCount = countResult?.total ?? 0;
    const totalPages = Math.ceil(totalCount / limit) || 1;

    const rows = await env.MARKETPLACE_DB
      .prepare(`SELECT * FROM marketplace_actions ${where} ORDER BY ${orderBy} LIMIT ?${bindings.length + 1} OFFSET ?${bindings.length + 2}`)
      .bind(...bindings, limit, offset)
      .all();

    const actions = rows.results.map(({ creator_id, ...rest }) => rest);

    return buildResponse(
      JSON.stringify({ actions, page, total_pages: totalPages, total_count: totalCount, has_more: page < totalPages }),
      200,
      "application/json"
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return buildResponse(JSON.stringify({ error: "Database query failed", message }), 500, "application/json");
  }
}

async function handleWebCreateAction(request: Request, env: Env): Promise<Response> {
  try {
    const body = (await request.json()) as Record<string, unknown>;

    const name = body.name as string;
    const prompt = body.prompt as string;
    if (!name || !prompt) {
      return buildResponse(JSON.stringify({ error: "name and prompt are required" }), 400, "application/json");
    }

    const actionDescription = (body.action_description as string) || "";
    const outputType = VALID_OUTPUT_TYPES.has(body.output_type as string) ? (body.output_type as string) : "plain";
    const usageScenes = typeof body.usage_scenes === "number" ? body.usage_scenes : 7;
    const category = VALID_CATEGORIES.has(body.category as string) ? (body.category as string) : "other";
    const authorName = (body.author_name as string) || "Anonymous";

    const result = await env.MARKETPLACE_DB
      .prepare(
        `INSERT INTO marketplace_actions (name, prompt, action_description, output_type, usage_scenes, category, author_name)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
         RETURNING *`
      )
      .bind(name, prompt, actionDescription, outputType, usageScenes, category, authorName)
      .first();

    if (!result) {
      return buildResponse(JSON.stringify({ error: "Failed to create action" }), 500, "application/json");
    }

    const { creator_id, ...publicAction } = result as Record<string, unknown>;
    return buildResponse(JSON.stringify({ action: publicAction }), 201, "application/json");
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return buildResponse(JSON.stringify({ error: "Failed to create action", message }), 500, "application/json");
  }
}

async function handleWebUpdateAction(request: Request, env: Env, actionId: string): Promise<Response> {
  try {
    const body = (await request.json()) as Record<string, unknown>;

    const sets: string[] = [];
    const bindings: unknown[] = [];
    let idx = 1;

    if (typeof body.name === "string" && body.name) {
      sets.push(`name = ?${idx}`);
      bindings.push(body.name);
      idx++;
    }
    if (typeof body.prompt === "string" && body.prompt) {
      sets.push(`prompt = ?${idx}`);
      bindings.push(body.prompt);
      idx++;
    }
    if (typeof body.action_description === "string") {
      sets.push(`action_description = ?${idx}`);
      bindings.push(body.action_description);
      idx++;
    }
    if (typeof body.output_type === "string" && VALID_OUTPUT_TYPES.has(body.output_type)) {
      sets.push(`output_type = ?${idx}`);
      bindings.push(body.output_type);
      idx++;
    }
    if (typeof body.usage_scenes === "number") {
      sets.push(`usage_scenes = ?${idx}`);
      bindings.push(body.usage_scenes);
      idx++;
    }
    if (typeof body.category === "string" && VALID_CATEGORIES.has(body.category)) {
      sets.push(`category = ?${idx}`);
      bindings.push(body.category);
      idx++;
    }
    if (typeof body.author_name === "string") {
      sets.push(`author_name = ?${idx}`);
      bindings.push(body.author_name);
      idx++;
    }

    if (sets.length === 0) {
      return buildResponse(JSON.stringify({ error: "No fields to update" }), 400, "application/json");
    }

    bindings.push(actionId);
    const result = await env.MARKETPLACE_DB
      .prepare(`UPDATE marketplace_actions SET ${sets.join(", ")} WHERE id = ?${idx} RETURNING *`)
      .bind(...bindings)
      .first();

    if (!result) {
      return buildResponse(JSON.stringify({ error: "Action not found" }), 404, "application/json");
    }

    const { creator_id, ...publicAction } = result as Record<string, unknown>;
    return buildResponse(JSON.stringify({ action: publicAction }), 200, "application/json");
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return buildResponse(JSON.stringify({ error: "Failed to update action", message }), 500, "application/json");
  }
}

async function handleWebDeleteAction(env: Env, actionId: string): Promise<Response> {
  try {
    const row = await env.MARKETPLACE_DB
      .prepare("SELECT id FROM marketplace_actions WHERE id = ?1")
      .bind(actionId)
      .first();

    if (!row) {
      return buildResponse(JSON.stringify({ error: "Action not found" }), 404, "application/json");
    }

    await env.MARKETPLACE_DB
      .prepare("DELETE FROM marketplace_actions WHERE id = ?1")
      .bind(actionId)
      .run();

    return buildResponse(JSON.stringify({ deleted: true }), 200, "application/json");
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return buildResponse(JSON.stringify({ error: "Failed to delete action", message }), 500, "application/json");
  }
}

function serveWebApp(): Response {
  const html = MARKETPLACE_WEB_HTML;
  const headers = new Headers();
  applyCors(headers);
  headers.set("Content-Type", "text/html; charset=utf-8");
  headers.set("Cache-Control", "no-cache");
  return new Response(html, { status: 200, headers });
}

const MARKETPLACE_WEB_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>TLingo Marketplace</title>
<script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
<link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
<style>
  :root {
    --bg: #f6f6fa; --card: #ffffff; --accent: #e86228;
    --text1: #1c1c22; --text2: rgba(0,0,0,0.6);
    --chip-off: rgba(0,0,0,0.05); --chip-off-text: rgba(0,0,0,0.7);
    --divider: rgba(0,0,0,0.06); --input-bg: #ffffff;
    --error: #cf4a4a; --success: #2aa05a;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #111118; --card: #18181f; --accent: #e86228;
      --text1: #ffffff; --text2: rgba(255,255,255,0.65);
      --chip-off: rgba(255,255,255,0.25); --chip-off-text: #ffffff;
      --divider: rgba(255,255,255,0.08); --input-bg: #26262c;
      --error: #ee6e73; --success: #40c181;
    }
  }
  * { box-sizing: border-box; }
  body { background: var(--bg); color: var(--text1); font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; min-height: 100vh; }
  .card { background: var(--card); border-radius: 12px; border: 1px solid var(--divider); }
  .chip { padding: 6px 14px; border-radius: 20px; font-size: 13px; cursor: pointer; transition: all 0.15s; white-space: nowrap; }
  .chip-on { background: var(--accent); color: #fff; }
  .chip-off { background: var(--chip-off); color: var(--chip-off-text); }
  .chip:hover { opacity: 0.85; }
  .btn { background: var(--accent); color: #fff; border: none; padding: 10px 20px; border-radius: 10px; font-size: 14px; font-weight: 600; cursor: pointer; transition: opacity 0.15s; }
  .btn:hover { opacity: 0.9; }
  .btn:disabled { opacity: 0.5; cursor: not-allowed; }
  .btn-outline { background: transparent; color: var(--accent); border: 1.5px solid var(--accent); }
  .btn-danger { background: var(--error); }
  .input { background: var(--input-bg); color: var(--text1); border: 1.5px solid var(--divider); border-radius: 10px; padding: 10px 14px; font-size: 14px; width: 100%; outline: none; transition: border-color 0.15s; }
  .input:focus { border-color: var(--accent); }
  textarea.input { resize: vertical; min-height: 100px; font-family: 'SF Mono', 'Fira Code', monospace; }
  .text2 { color: var(--text2); }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 6px; font-size: 11px; font-weight: 600; }
  .toast { position: fixed; top: 20px; right: 20px; padding: 12px 20px; border-radius: 10px; color: #fff; font-size: 14px; font-weight: 500; z-index: 100; animation: slideIn 0.3s ease; }
  @keyframes slideIn { from { transform: translateX(100%); opacity: 0; } to { transform: translateX(0); opacity: 1; } }
  .prompt-block { background: var(--input-bg); border: 1px solid var(--divider); border-radius: 8px; padding: 12px 16px; font-family: 'SF Mono', 'Fira Code', monospace; font-size: 13px; white-space: pre-wrap; word-break: break-word; line-height: 1.6; }
  .grid-cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 16px; }
  @media (max-width: 640px) { .grid-cards { grid-template-columns: 1fr; } }
  .skeleton { background: linear-gradient(90deg, var(--chip-off) 25%, transparent 50%, var(--chip-off) 75%); background-size: 200% 100%; animation: shimmer 1.5s infinite; border-radius: 8px; }
  @keyframes shimmer { 0% { background-position: 200% 0; } 100% { background-position: -200% 0; } }
</style>
</head>
<body>
<div x-data="marketplace()" x-init="init()" class="max-w-5xl mx-auto px-4 py-8">

  <!-- Toast -->
  <template x-if="toast.show">
    <div class="toast" :style="'background:' + (toast.type === 'error' ? 'var(--error)' : 'var(--success)')"
         x-text="toast.message" x-init="setTimeout(() => toast.show = false, 3000)"></div>
  </template>

  <!-- Header -->
  <div class="flex items-center justify-between mb-6">
    <div class="flex items-center gap-3">
      <template x-if="view !== 'list'">
        <button @click="goBack()" class="text2" style="font-size:20px;cursor:pointer;background:none;border:none;color:var(--text2);">&larr;</button>
      </template>
      <h1 class="text-2xl font-bold" x-text="viewTitle"></h1>
    </div>
    <div class="flex items-center gap-2">
      <template x-if="view === 'list'">
        <button class="btn" @click="showPublish()">+ Publish</button>
      </template>
      <template x-if="!isAdmin">
        <button class="btn btn-outline" style="font-size:12px;padding:8px 12px;" @click="showAdminLogin = true">Admin</button>
      </template>
      <template x-if="isAdmin">
        <button class="btn btn-outline" style="font-size:12px;padding:8px 12px;border-color:var(--success);color:var(--success);" @click="logout()">Admin \u2713</button>
      </template>
    </div>
  </div>

  <!-- Admin Login Modal -->
  <template x-if="showAdminLogin">
    <div style="position:fixed;inset:0;background:rgba(0,0,0,0.5);z-index:50;display:flex;align-items:center;justify-content:center;" @click.self="showAdminLogin = false">
      <div class="card" style="padding:24px;width:340px;">
        <h3 class="text-lg font-semibold mb-4">Enter Admin Password</h3>
        <input type="password" class="input mb-3" placeholder="Password" x-model="adminPasswordInput" @keydown.enter="verifyAdmin()">
        <div class="flex gap-2">
          <button class="btn" style="flex:1;" @click="verifyAdmin()" :disabled="!adminPasswordInput">Verify</button>
          <button class="btn btn-outline" style="flex:1;" @click="showAdminLogin = false">Cancel</button>
        </div>
      </div>
    </div>
  </template>

  <!-- LIST VIEW -->
  <template x-if="view === 'list'">
    <div>
      <!-- Search -->
      <input type="text" class="input mb-4" placeholder="Search actions..." x-model="searchText"
             @input.debounce.300ms="search()">

      <!-- Filters -->
      <div class="flex flex-wrap gap-2 mb-4">
        <span class="chip" :class="category === '' ? 'chip-on' : 'chip-off'" @click="setCategory('')">All</span>
        <span class="chip" :class="category === 'translation' ? 'chip-on' : 'chip-off'" @click="setCategory('translation')">Translation</span>
        <span class="chip" :class="category === 'writing' ? 'chip-on' : 'chip-off'" @click="setCategory('writing')">Writing</span>
        <span class="chip" :class="category === 'analysis' ? 'chip-on' : 'chip-off'" @click="setCategory('analysis')">Analysis</span>
        <span class="chip" :class="category === 'other' ? 'chip-on' : 'chip-off'" @click="setCategory('other')">Other</span>
        <div style="flex:1;"></div>
        <span class="chip" :class="sortBy === 'newest' ? 'chip-on' : 'chip-off'" @click="setSort('newest')">Newest</span>
        <span class="chip" :class="sortBy === 'popular' ? 'chip-on' : 'chip-off'" @click="setSort('popular')">Popular</span>
      </div>

      <!-- Loading skeleton -->
      <template x-if="loading && actions.length === 0">
        <div class="grid-cards">
          <template x-for="i in 6"><div class="skeleton" style="height:120px;"></div></template>
        </div>
      </template>

      <!-- Empty state -->
      <template x-if="!loading && actions.length === 0">
        <div class="card" style="padding:40px;text-align:center;">
          <p class="text2">No actions found</p>
        </div>
      </template>

      <!-- Action cards -->
      <div class="grid-cards">
        <template x-for="action in actions" :key="action.id">
          <div class="card" style="padding:16px;cursor:pointer;transition:transform 0.1s;"
               @click="showDetail(action)"
               @mouseenter="$el.style.transform='translateY(-2px)'"
               @mouseleave="$el.style.transform='none'">
            <div class="flex items-start justify-between mb-2">
              <h3 class="font-semibold" style="font-size:15px;" x-text="action.name"></h3>
              <span class="badge" style="background:var(--chip-off);color:var(--chip-off-text);" x-text="action.category"></span>
            </div>
            <p class="text2" style="font-size:13px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;" x-text="action.action_description || 'No description'"></p>
            <div class="flex items-center gap-3 mt-3 text2" style="font-size:12px;">
              <span x-text="action.author_name"></span>
              <span>\u00b7</span>
              <span x-text="action.download_count + ' downloads'"></span>
              <span>\u00b7</span>
              <span x-text="formatDate(action.created_at)"></span>
            </div>
          </div>
        </template>
      </div>

      <!-- Load more -->
      <template x-if="hasMore">
        <div style="text-align:center;margin-top:20px;">
          <button class="btn btn-outline" @click="loadMore()" :disabled="loading" x-text="loading ? 'Loading...' : 'Load More'"></button>
        </div>
      </template>

      <!-- Total count -->
      <template x-if="totalCount > 0">
        <p class="text2" style="text-align:center;margin-top:12px;font-size:13px;" x-text="totalCount + ' actions total'"></p>
      </template>
    </div>
  </template>

  <!-- DETAIL VIEW -->
  <template x-if="view === 'detail' && selectedAction">
    <div>
      <div class="card" style="padding:24px;">
        <div class="flex items-start justify-between mb-1">
          <h2 class="text-xl font-bold" x-text="selectedAction.name"></h2>
          <span class="badge" style="background:var(--chip-off);color:var(--chip-off-text);" x-text="selectedAction.category"></span>
        </div>
        <p class="text2 mb-4" style="font-size:13px;">
          by <span x-text="selectedAction.author_name"></span>
          &bull; <span x-text="selectedAction.download_count + ' downloads'"></span>
          &bull; <span x-text="formatDate(selectedAction.created_at)"></span>
        </p>

        <template x-if="selectedAction.action_description">
          <div class="mb-4">
            <h4 class="font-semibold text2 mb-1" style="font-size:12px;text-transform:uppercase;letter-spacing:0.5px;">Description</h4>
            <p style="font-size:14px;line-height:1.6;" x-text="selectedAction.action_description"></p>
          </div>
        </template>

        <div class="mb-4">
          <h4 class="font-semibold text2 mb-1" style="font-size:12px;text-transform:uppercase;letter-spacing:0.5px;">Prompt</h4>
          <div class="prompt-block" x-text="selectedAction.prompt"></div>
        </div>

        <div class="flex flex-wrap gap-4 mb-4" style="font-size:13px;">
          <div>
            <span class="text2">Output Type:</span>
            <span class="font-medium" x-text="outputTypeLabel(selectedAction.output_type)"></span>
          </div>
          <div>
            <span class="text2">Usage:</span>
            <span class="font-medium" x-text="usageScenesLabel(selectedAction.usage_scenes)"></span>
          </div>
        </div>

        <!-- Admin actions -->
        <template x-if="isAdmin">
          <div style="border-top:1px solid var(--divider);padding-top:16px;margin-top:16px;" class="flex gap-2">
            <button class="btn" @click="showEdit(selectedAction)">Edit</button>
            <button class="btn btn-danger" @click="confirmDelete(selectedAction)">Delete</button>
          </div>
        </template>
      </div>
    </div>
  </template>

  <!-- PUBLISH VIEW -->
  <template x-if="view === 'publish'">
    <div class="card" style="padding:24px;">
      <div class="mb-4">
        <label class="block text2 mb-1" style="font-size:13px;">Name *</label>
        <input type="text" class="input" placeholder="Action name" x-model="form.name">
      </div>
      <div class="mb-4">
        <label class="block text2 mb-1" style="font-size:13px;">Prompt *</label>
        <textarea class="input" placeholder="Enter prompt template... Use {text} for input and {targetLanguage} for target language." x-model="form.prompt" rows="6"></textarea>
      </div>
      <div class="mb-4">
        <label class="block text2 mb-1" style="font-size:13px;">Description</label>
        <textarea class="input" placeholder="Brief description of what this action does" x-model="form.description" rows="3" style="min-height:60px;font-family:inherit;"></textarea>
      </div>
      <div class="mb-4">
        <label class="block text2 mb-1" style="font-size:13px;">Category</label>
        <div class="flex flex-wrap gap-2">
          <template x-for="cat in ['translation','writing','analysis','other']">
            <span class="chip" :class="form.category === cat ? 'chip-on' : 'chip-off'" @click="form.category = cat" x-text="cat.charAt(0).toUpperCase() + cat.slice(1)"></span>
          </template>
        </div>
      </div>
      <div class="mb-4">
        <label class="block text2 mb-1" style="font-size:13px;">Output Type</label>
        <div class="flex flex-wrap gap-2">
          <template x-for="t in outputTypes">
            <span class="chip" :class="form.outputType === t.value ? 'chip-on' : 'chip-off'" @click="form.outputType = t.value" x-text="t.label"></span>
          </template>
        </div>
      </div>
      <div class="mb-4">
        <label class="block text2 mb-1" style="font-size:13px;">Usage Scenes</label>
        <div class="flex flex-wrap gap-2">
          <template x-for="s in usageSceneOptions">
            <span class="chip" :class="(form.usageScenes & s.value) ? 'chip-on' : 'chip-off'" @click="form.usageScenes ^= s.value" x-text="s.label"></span>
          </template>
        </div>
      </div>
      <div class="mb-6">
        <label class="block text2 mb-1" style="font-size:13px;">Author Name</label>
        <input type="text" class="input" placeholder="Anonymous" x-model="form.authorName">
      </div>
      <button class="btn" style="width:100%;" @click="submitForm()" :disabled="!form.name || !form.prompt || submitting"
              x-text="submitting ? 'Publishing...' : 'Publish Action'"></button>
    </div>
  </template>

  <!-- EDIT VIEW -->
  <template x-if="view === 'edit'">
    <div class="card" style="padding:24px;">
      <div class="mb-4">
        <label class="block text2 mb-1" style="font-size:13px;">Name *</label>
        <input type="text" class="input" x-model="form.name">
      </div>
      <div class="mb-4">
        <label class="block text2 mb-1" style="font-size:13px;">Prompt *</label>
        <textarea class="input" x-model="form.prompt" rows="6"></textarea>
      </div>
      <div class="mb-4">
        <label class="block text2 mb-1" style="font-size:13px;">Description</label>
        <textarea class="input" x-model="form.description" rows="3" style="min-height:60px;font-family:inherit;"></textarea>
      </div>
      <div class="mb-4">
        <label class="block text2 mb-1" style="font-size:13px;">Category</label>
        <div class="flex flex-wrap gap-2">
          <template x-for="cat in ['translation','writing','analysis','other']">
            <span class="chip" :class="form.category === cat ? 'chip-on' : 'chip-off'" @click="form.category = cat" x-text="cat.charAt(0).toUpperCase() + cat.slice(1)"></span>
          </template>
        </div>
      </div>
      <div class="mb-4">
        <label class="block text2 mb-1" style="font-size:13px;">Output Type</label>
        <div class="flex flex-wrap gap-2">
          <template x-for="t in outputTypes">
            <span class="chip" :class="form.outputType === t.value ? 'chip-on' : 'chip-off'" @click="form.outputType = t.value" x-text="t.label"></span>
          </template>
        </div>
      </div>
      <div class="mb-4">
        <label class="block text2 mb-1" style="font-size:13px;">Usage Scenes</label>
        <div class="flex flex-wrap gap-2">
          <template x-for="s in usageSceneOptions">
            <span class="chip" :class="(form.usageScenes & s.value) ? 'chip-on' : 'chip-off'" @click="form.usageScenes ^= s.value" x-text="s.label"></span>
          </template>
        </div>
      </div>
      <div class="mb-6">
        <label class="block text2 mb-1" style="font-size:13px;">Author Name</label>
        <input type="text" class="input" x-model="form.authorName">
      </div>
      <button class="btn" style="width:100%;" @click="submitEdit()" :disabled="!form.name || !form.prompt || submitting"
              x-text="submitting ? 'Saving...' : 'Save Changes'"></button>
    </div>
  </template>

  <!-- Delete confirmation modal -->
  <template x-if="showDeleteConfirm">
    <div style="position:fixed;inset:0;background:rgba(0,0,0,0.5);z-index:50;display:flex;align-items:center;justify-content:center;" @click.self="showDeleteConfirm = false">
      <div class="card" style="padding:24px;width:340px;">
        <h3 class="text-lg font-semibold mb-2">Delete Action</h3>
        <p class="text2 mb-4">Are you sure? This cannot be undone.</p>
        <div class="flex gap-2">
          <button class="btn btn-danger" style="flex:1;" @click="doDelete()">Delete</button>
          <button class="btn btn-outline" style="flex:1;" @click="showDeleteConfirm = false">Cancel</button>
        </div>
      </div>
    </div>
  </template>

  <!-- Footer (required: ToS, Privacy Policy, support email) -->
  <footer style="margin-top:48px;padding:24px 0;border-top:1px solid var(--divider);text-align:center;font-size:13px;line-height:1.7;" class="text2">
    <div>
      <a href="/terms" style="color:var(--accent);text-decoration:none;margin:0 8px;">Terms of Service</a>
      <span style="opacity:0.4;">|</span>
      <a href="/privacy" style="color:var(--accent);text-decoration:none;margin:0 8px;">Privacy Policy</a>
      <span style="opacity:0.4;">|</span>
      <a href="/support" style="color:var(--accent);text-decoration:none;margin:0 8px;">Support</a>
    </div>
    <div style="margin-top:8px;">
      Support: <a href="mailto:tlingo@zanderwang.com" style="color:var(--accent);text-decoration:none;">tlingo@zanderwang.com</a>
    </div>
    <div style="margin-top:8px;opacity:0.7;">&copy; Zander Wang &middot; TLingo</div>
  </footer>

</div>

<script>
function marketplace() {
  const API = '/web/api';
  return {
    view: 'list', actions: [], searchText: '', category: '', sortBy: 'newest',
    page: 1, hasMore: false, totalCount: 0, loading: false,
    selectedAction: null, editingId: null,
    isAdmin: false, adminPassword: '', adminPasswordInput: '', showAdminLogin: false,
    form: { name: '', prompt: '', description: '', outputType: 'plain', category: 'other', authorName: '', usageScenes: 7 },
    submitting: false, showDeleteConfirm: false, deleteTarget: null,
    toast: { show: false, message: '', type: 'success' },
    outputTypes: [
      { value: 'plain', label: 'Plain Text' },
      { value: 'diff', label: 'Diff' },
      { value: 'sentencePairs', label: 'Sentence Pairs' },
      { value: 'grammarCheck', label: 'Grammar Check' }
    ],
    usageSceneOptions: [
      { value: 1, label: 'App' },
      { value: 2, label: 'Context Read' },
      { value: 4, label: 'Context Edit' }
    ],

    get viewTitle() {
      return { list: 'Marketplace', detail: 'Action Detail', publish: 'Publish Action', edit: 'Edit Action' }[this.view] || '';
    },

    async init() {
      this.adminPassword = localStorage.getItem('admin_password') || '';
      if (this.adminPassword) {
        try {
          const r = await fetch(API + '/admin/verify', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ password: this.adminPassword }) });
          const d = await r.json();
          this.isAdmin = d.valid;
          if (!d.valid) { this.adminPassword = ''; localStorage.removeItem('admin_password'); }
        } catch { this.adminPassword = ''; }
      }
      this.fetchActions();
    },

    async fetchActions() {
      this.loading = true;
      try {
        const params = new URLSearchParams({ page: this.page, limit: 20, sort: this.sortBy });
        if (this.searchText) params.set('q', this.searchText);
        if (this.category) params.set('category', this.category);
        const r = await fetch(API + '/actions?' + params);
        const d = await r.json();
        if (this.page === 1) this.actions = d.actions;
        else this.actions = [...this.actions, ...d.actions];
        this.hasMore = d.has_more;
        this.totalCount = d.total_count;
      } catch (e) { this.showToast('Failed to load actions', 'error'); }
      this.loading = false;
    },

    search() { this.page = 1; this.fetchActions(); },
    setCategory(c) { this.category = c; this.page = 1; this.fetchActions(); },
    setSort(s) { this.sortBy = s; this.page = 1; this.fetchActions(); },
    loadMore() { this.page++; this.fetchActions(); },

    showDetail(action) { this.selectedAction = action; this.view = 'detail'; },
    showPublish() {
      this.form = { name: '', prompt: '', description: '', outputType: 'plain', category: 'other', authorName: '', usageScenes: 7 };
      this.view = 'publish';
    },
    showEdit(action) {
      this.editingId = action.id;
      this.form = {
        name: action.name, prompt: action.prompt, description: action.action_description || '',
        outputType: action.output_type, category: action.category, authorName: action.author_name,
        usageScenes: action.usage_scenes
      };
      this.view = 'edit';
    },

    goBack() {
      if (this.view === 'edit') { this.view = 'detail'; }
      else { this.view = 'list'; this.selectedAction = null; }
    },

    async submitForm() {
      this.submitting = true;
      try {
        const r = await fetch(API + '/actions', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            name: this.form.name, prompt: this.form.prompt, action_description: this.form.description,
            output_type: this.form.outputType, category: this.form.category,
            author_name: this.form.authorName || 'Anonymous', usage_scenes: this.form.usageScenes
          })
        });
        if (!r.ok) { const e = await r.json(); throw new Error(e.error); }
        this.showToast('Action published!', 'success');
        this.view = 'list'; this.page = 1; this.fetchActions();
      } catch (e) { this.showToast(e.message || 'Failed to publish', 'error'); }
      this.submitting = false;
    },

    async submitEdit() {
      this.submitting = true;
      try {
        const r = await fetch(API + '/actions/' + this.editingId, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json', 'X-Admin-Password': this.adminPassword },
          body: JSON.stringify({
            name: this.form.name, prompt: this.form.prompt, action_description: this.form.description,
            output_type: this.form.outputType, category: this.form.category,
            author_name: this.form.authorName, usage_scenes: this.form.usageScenes
          })
        });
        if (!r.ok) { const e = await r.json(); throw new Error(e.error); }
        const d = await r.json();
        this.selectedAction = d.action;
        const idx = this.actions.findIndex(a => a.id === this.editingId);
        if (idx >= 0) this.actions[idx] = d.action;
        this.showToast('Action updated!', 'success');
        this.view = 'detail';
      } catch (e) { this.showToast(e.message || 'Failed to update', 'error'); }
      this.submitting = false;
    },

    confirmDelete(action) { this.deleteTarget = action; this.showDeleteConfirm = true; },

    async doDelete() {
      try {
        const r = await fetch(API + '/actions/' + this.deleteTarget.id, {
          method: 'DELETE', headers: { 'X-Admin-Password': this.adminPassword }
        });
        if (!r.ok) { const e = await r.json(); throw new Error(e.error); }
        this.actions = this.actions.filter(a => a.id !== this.deleteTarget.id);
        this.showToast('Action deleted', 'success');
        this.showDeleteConfirm = false;
        this.view = 'list'; this.selectedAction = null;
      } catch (e) { this.showToast(e.message || 'Failed to delete', 'error'); }
    },

    async verifyAdmin() {
      try {
        const r = await fetch(API + '/admin/verify', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ password: this.adminPasswordInput })
        });
        const d = await r.json();
        if (d.valid) {
          this.isAdmin = true; this.adminPassword = this.adminPasswordInput;
          localStorage.setItem('admin_password', this.adminPassword);
          this.showAdminLogin = false; this.adminPasswordInput = '';
          this.showToast('Admin mode enabled', 'success');
        } else { this.showToast('Invalid password', 'error'); }
      } catch { this.showToast('Verification failed', 'error'); }
    },

    logout() {
      this.isAdmin = false; this.adminPassword = '';
      localStorage.removeItem('admin_password');
      this.showToast('Logged out', 'success');
    },

    formatDate(d) {
      if (!d) return '';
      const date = new Date(d);
      return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
    },

    outputTypeLabel(t) {
      return { plain: 'Plain Text', diff: 'Diff', sentencePairs: 'Sentence Pairs', grammarCheck: 'Grammar Check' }[t] || t;
    },

    usageScenesLabel(v) {
      const labels = [];
      if (v & 1) labels.push('App');
      if (v & 2) labels.push('Context Read');
      if (v & 4) labels.push('Context Edit');
      return labels.join(', ') || 'None';
    },

    showToast(message, type) {
      this.toast = { show: true, message, type };
      setTimeout(() => this.toast.show = false, 3000);
    }
  };
}
</script>
</body>
</html>`;

// ---------------------------------------------------------------------------
// Public legal & support pages
// ---------------------------------------------------------------------------

const SUPPORT_EMAIL = "tlingo@zanderwang.com";

function serveStaticHtml(html: string): Response {
  const headers = new Headers();
  applyCors(headers);
  headers.set("Content-Type", "text/html; charset=utf-8");
  headers.set("Cache-Control", "public, max-age=3600");
  return new Response(html, { status: 200, headers });
}

function legalPage(title: string, bodyHtml: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${title} — TLingo</title>
<style>
  :root { --bg:#f6f6fa; --card:#fff; --accent:#e86228; --text1:#1c1c22; --text2:rgba(0,0,0,0.6); --divider:rgba(0,0,0,0.08); }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#111118; --card:#18181f; --text1:#fff; --text2:rgba(255,255,255,0.65); --divider:rgba(255,255,255,0.08); }
  }
  * { box-sizing:border-box; }
  body { background:var(--bg); color:var(--text1); font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif; margin:0; line-height:1.65; }
  .wrap { max-width:780px; margin:0 auto; padding:48px 24px; }
  nav { font-size:14px; margin-bottom:24px; }
  nav a { color:var(--accent); text-decoration:none; margin-right:16px; }
  article { background:var(--card); border:1px solid var(--divider); border-radius:12px; padding:32px 36px; }
  h1 { margin-top:0; font-size:28px; }
  h2 { margin-top:32px; font-size:20px; }
  h3 { margin-top:24px; font-size:16px; }
  h4 { margin-top:18px; font-size:14px; }
  a { color:var(--accent); }
  p, li { font-size:15px; }
  hr { border:none; border-top:1px solid var(--divider); margin:32px 0; }
  footer { margin-top:32px; text-align:center; font-size:13px; color:var(--text2); }
  footer a { color:var(--accent); text-decoration:none; margin:0 8px; }
</style>
</head>
<body>
<div class="wrap">
  <nav>
    <a href="/web">&larr; TLingo Marketplace</a>
  </nav>
  <article>
${bodyHtml}
  </article>
  <footer>
    <div>
      <a href="/terms">Terms of Service</a>|
      <a href="/privacy">Privacy Policy</a>|
      <a href="/support">Support</a>
    </div>
    <div style="margin-top:8px;">Support: <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a></div>
    <div style="margin-top:8px;opacity:0.7;">&copy; Zander Wang &middot; TLingo</div>
  </footer>
</div>
</body>
</html>`;
}

// Minimal markdown -> HTML for our static legal docs (headings, paragraphs,
// bullet lists, links, bold). Intentionally tiny — the input is fully
// trusted (compiled-in constants), so no sanitization is required.
function mdToHtml(md: string): string {
  const escape = (s: string) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const inline = (s: string) =>
    escape(s)
      .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>')
      .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");

  const lines = md.split(/\r?\n/);
  const out: string[] = [];
  let inList = false;
  const closeList = () => { if (inList) { out.push("</ul>"); inList = false; } };

  for (const raw of lines) {
    const line = raw.trimEnd();
    if (!line.trim()) { closeList(); continue; }
    const h = line.match(/^(#{1,4})\s+(.*)$/);
    if (h) {
      closeList();
      out.push(`<h${h[1].length}>${inline(h[2])}</h${h[1].length}>`);
      continue;
    }
    const li = line.match(/^[-*]\s+(.*)$/);
    if (li) {
      if (!inList) { out.push("<ul>"); inList = true; }
      out.push(`<li>${inline(li[1])}</li>`);
      continue;
    }
    closeList();
    out.push(`<p>${inline(line)}</p>`);
  }
  closeList();
  return out.join("\n");
}

// Inlined verbatim from docs/TermsOfUse.md and docs/PrivacyPolicy.md.
// Keep in sync when the markdown sources change.
const TERMS_MD = `# Terms of Service (EULA)

**Last Updated: February 11, 2026**

Please read these Terms of Service ("Terms" or "EULA") carefully before using the TLingo application and website ("Service") operated by Zander Wang ("we," "our," or "us").

By downloading, installing, accessing, or using TLingo, you agree to be bound by these Terms. If you do not agree to these Terms, do not use the Service.

## 1. License Grant

Subject to your compliance with these Terms, we grant you a limited, non-exclusive, non-transferable, revocable license to download, install, and use the App on devices that you own or control, solely for your personal, non-commercial use.

## 2. Subscription Services

### 2.1 TLingo Premium

TLingo offers auto-renewable subscription plans ("TLingo Premium") that provide access to premium features, including additional AI translation models and enhanced capabilities.

The following subscription plans are available:

- **Monthly Subscription** — Billed monthly
- **Annual Subscription** — Billed annually

Current subscription prices are displayed within the App at the time of purchase. Prices may vary by region and are subject to change.

### 2.2 Billing and Payment

- Payment is charged to your account at confirmation of purchase.
- Payments may be processed by Apple through the App Store or by our payment processor (Creem / Stripe) on the web.
- Prices are displayed in your local currency where supported.

### 2.3 Auto-Renewal

- Subscriptions automatically renew unless auto-renewal is turned off at least 24 hours before the end of the current subscription period.
- Your account will be charged for renewal within 24 hours prior to the end of the current period at the same price as the original subscription.
- You can manage your subscriptions and turn off auto-renewal in your Apple ID Account Settings, or via the customer portal link in your purchase confirmation email.

### 2.4 Free Trial

- If a free trial is offered, it will be clearly indicated at the time of subscription.
- Any unused portion of a free trial period will be forfeited when you purchase a subscription.

### 2.5 Cancellation

- You may cancel your subscription at any time.
- Cancellation takes effect at the end of the current billing period. You will continue to have access to premium features until the end of the period you have already paid for.
- No refunds are provided for partial subscription periods.

### 2.6 Refunds

For App Store purchases, refund requests must be directed to Apple via [Apple's Report a Problem](https://reportaproblem.apple.com/) page. For web purchases processed by our payment provider, please contact us at ${SUPPORT_EMAIL}.

## 3. User Conduct

You agree not to:

- Use the Service for any unlawful, harmful, or fraudulent purpose
- Attempt to reverse-engineer, decompile, or disassemble the App
- Use the Service to generate content that is illegal, harmful, threatening, abusive, defamatory, or otherwise objectionable
- Interfere with or disrupt the Service or its servers
- Attempt to gain unauthorized access to any part of the Service or its systems
- Use the Service in a manner that could overburden or impair it
- Resell, sublicense, or redistribute the App or its content

## 4. Translation Service

### 4.1 Accuracy

TLingo uses AI-powered language models to provide translations. While we strive for accuracy, translations are generated by artificial intelligence and may contain errors, inaccuracies, or omissions. We do not guarantee the accuracy, completeness, or reliability of any translation.

### 4.2 No Professional Substitute

Translations provided by TLingo should not be used as a substitute for professional human translation in contexts where accuracy is critical, including but not limited to legal, medical, financial, or official documents.

### 4.3 Third-Party API Services

TLingo may use third-party LLM API services to process translations. These services are subject to their own terms and conditions. You are responsible for reviewing and complying with the terms of any third-party API services you configure within the App.

## 5. Intellectual Property

### 5.1 Our Rights

The Service, including its design, code, features, and content (excluding user-generated content), is owned by Zander Wang and is protected by copyright, trademark, and other intellectual property laws.

### 5.2 Your Content

You retain ownership of the text you submit for translation. By using the Service, you grant us a limited, non-exclusive license to process your text solely for the purpose of providing the translation service.

## 6. Privacy

Your use of TLingo is also governed by our [Privacy Policy](/privacy). Please review it to understand how we collect, use, and protect your information.

## 7. Disclaimers

THE SERVICE IS PROVIDED ON AN "AS IS" AND "AS AVAILABLE" BASIS WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.

We do not guarantee that the Service will be available at all times, uninterrupted, or error-free. We reserve the right to modify, suspend, or discontinue the Service or any part thereof at any time without prior notice.

We are not responsible for the availability, accuracy, or performance of third-party services (including LLM API providers and payment processors) used by the Service.

## 8. Limitation of Liability

TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL ZANDER WANG BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS, DATA, OR GOODWILL, ARISING OUT OF OR IN CONNECTION WITH YOUR USE OF THE SERVICE.

OUR TOTAL LIABILITY FOR ANY CLAIMS ARISING FROM OR RELATED TO THE SERVICE SHALL NOT EXCEED THE AMOUNT YOU PAID FOR THE APP OR SUBSCRIPTION IN THE TWELVE (12) MONTHS PRECEDING THE CLAIM.

## 9. Indemnification

You agree to indemnify, defend, and hold harmless Zander Wang from any claims, damages, losses, liabilities, and expenses (including reasonable attorneys' fees) arising from your use of the Service or violation of these Terms.

## 10. Modifications to Terms

We reserve the right to modify these Terms at any time. We will notify you of material changes by updating the "Last Updated" date. Your continued use of the Service after such modifications constitutes your acceptance of the updated Terms.

## 11. Termination

We may terminate or suspend your access to the Service at any time, without prior notice or liability, for any reason, including if you breach these Terms.

## 12. Governing Law

These Terms shall be governed by and construed in accordance with the laws of the People's Republic of China, without regard to its conflict of law provisions.

## 13. Severability

If any provision of these Terms is found to be invalid or unenforceable, the remaining provisions will continue in full force and effect.

## 14. Contact Us

If you have any questions about these Terms, please contact us at:

- **Email**: ${SUPPORT_EMAIL}
- **Support page**: [/support](/support)
`;

const PRIVACY_MD = `# Privacy Policy

**Last Updated: February 13, 2026**

Zander Wang ("we," "our," or "us") operates the TLingo application and website (the "Service"). This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our Service, including any auto-renewable subscription services offered within it.

By using TLingo, you agree to the collection and use of information in accordance with this policy.

## 1. Information We Collect

### 1.1 Translation Content

When you use TLingo to translate text, the following data is sent to a third-party AI service for processing:

- **Text you input** for translation
- **Source and target language** selections
- **Images you attach** (if using vision-capable models)
- **Translation instructions** (system prompts configured in the app)

This data is sent to **Microsoft Azure OpenAI Service** ("Azure OpenAI"), operated by Microsoft Corporation, to generate translations. We do not permanently store the content of your translations on our servers. Translation requests are processed in real time via streaming and are not retained after the response is delivered.

### 1.2 Subscription Information

When you subscribe to TLingo Premium, payment is processed by Apple through the App Store or by our payment processor (Creem / Stripe) on the web. We do not collect, store, or have access to your full payment card information. We receive confirmation of your subscription status and the minimal information needed to provide premium features and customer support (such as a customer ID and the email you provided at checkout).

### 1.3 Device and Usage Data

We may collect limited, non-personally identifiable information such as:

- Device type and operating system version
- App version
- General usage analytics (e.g., feature usage frequency)

We do not collect personally identifiable information unless you voluntarily provide it (e.g., contacting support).

### 1.4 Configuration Data

TLingo stores your app preferences, custom API configurations, and settings locally on your device and within the App Group container. This data is used solely to provide and improve your experience and is not transmitted to us.

## 2. How We Use Your Information

We use the information we collect to:

- Provide, maintain, and improve the translation service
- Process and manage your subscription
- Respond to customer support inquiries
- Monitor and analyze usage trends to improve the Service
- Ensure the security and integrity of our services

## 3. Third-Party Services

### 3.1 LLM API Providers

TLingo's built-in cloud translation service uses **Microsoft Azure OpenAI Service** to process your translation requests. Microsoft processes this data in accordance with [Microsoft's Privacy Statement](https://privacy.microsoft.com/privacystatement) and [Azure OpenAI Data Privacy](https://learn.microsoft.com/legal/cognitive-services/openai/data-privacy). Microsoft Azure OpenAI does not use customer data to train or improve its models.

When requests are routed through our proxy server, they are authenticated using HMAC-SHA256 signatures. Our proxy server does not log or store your translation content.

### 3.2 Payment Processors

Web subscription payments are processed by Creem and/or Stripe. They receive the information required to process your payment (email, billing details, payment method). Their handling of your data is governed by their respective privacy policies.

### 3.3 Apple Services

TLingo uses Apple's StoreKit 2 framework to manage in-app subscriptions. All in-app payment processing is handled by Apple and is subject to [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).

### 3.4 System Translation Extension

TLingo includes a system translation extension that integrates with iOS/macOS system-level translation features. The extension shares data with the main app only through the secure App Group container.

## 4. Data Sharing and Disclosure

We do not sell, trade, or rent your personal information to third parties. We may disclose information only in the following circumstances:

- **Translation processing**: Your input text and related data are sent to Microsoft Azure OpenAI Service to perform translations, with your explicit consent
- **Payment processing**: Billing information is shared with our payment processor to complete a transaction
- **Legal requirements**: If required by law, regulation, or legal process
- **Protection of rights**: To protect our rights, privacy, safety, or property
- **With your consent**: When you have given explicit permission

## 5. Data Security

We implement reasonable technical and organizational measures to protect your information, including:

- HMAC-SHA256 authentication for cloud API requests
- TLS encryption in transit
- Local storage of sensitive configuration data on-device
- No server-side retention of translation content

However, no method of electronic transmission or storage is 100% secure, and we cannot guarantee absolute security.

## 6. Data Retention

- **Translation content**: Not retained; processed in real time and discarded
- **Subscription status**: Cached locally on your device; refreshed from Apple's servers or our payment processor as needed
- **App preferences**: Stored locally on your device until you delete the App

## 7. Children's Privacy

TLingo is not directed to children under the age of 13. We do not knowingly collect personal information from children under 13. If you believe we have inadvertently collected such information, please contact us so we can promptly delete it.

## 8. Your Rights

Depending on your jurisdiction, you may have the right to:

- Access the personal data we hold about you
- Request correction or deletion of your data
- Object to or restrict certain processing of your data
- Data portability

To exercise any of these rights, contact us at ${SUPPORT_EMAIL}.

## 9. Changes to This Privacy Policy

We may update this Privacy Policy from time to time. We will notify you of any changes by updating the "Last Updated" date at the top of this policy.

## 10. Contact Us

If you have any questions or concerns about this Privacy Policy, please contact us at:

- **Email**: ${SUPPORT_EMAIL}
- **Terms of Service**: [/terms](/terms)
`;

const SUPPORT_MD = `# Support

Need help with TLingo? We're happy to help.

## Contact

- **Email**: [${SUPPORT_EMAIL}](mailto:${SUPPORT_EMAIL})

We typically respond within 1–2 business days.

## Common topics

- **Subscriptions & billing**: For App Store purchases, manage and request refunds via [Apple's Report a Problem](https://reportaproblem.apple.com/). For web purchases, email us at ${SUPPORT_EMAIL} with your order ID.
- **Bug reports & feature requests**: Email ${SUPPORT_EMAIL} with a description, your device/OS, and the app version.
- **Privacy & data requests**: See our [Privacy Policy](/privacy) or email ${SUPPORT_EMAIL}.
- **Terms of Service**: See [Terms of Service](/terms).
`;

const TERMS_HTML = legalPage("Terms of Service", mdToHtml(TERMS_MD));
const PRIVACY_HTML = legalPage("Privacy Policy", mdToHtml(PRIVACY_MD));
const SUPPORT_HTML = legalPage("Support", mdToHtml(SUPPORT_MD));
