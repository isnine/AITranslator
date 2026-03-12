import { app, HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import * as https from "https";

// ============================================================
// AITranslator Azure Function — mirrors Cloudflare Worker logic
// ============================================================

const TIMESTAMP_TOLERANCE_SECONDS = 120;

const ALLOWED_MODELS = [
  // Free tier
  "gpt-4o-mini", "gpt-4.1-mini", "gpt-4.1-nano", "gpt-5-nano", "gpt-5-mini",
  // Premium tier
  "gpt-5.4", "gpt-5.2-chat", "gpt-5", "gpt-4.1", "gpt-4o", "o4-mini", "o3-mini",
  // Hidden
  "model-router",
];

const PREMIUM_MODELS = new Set([
  "gpt-5.4", "gpt-5.2-chat", "gpt-5", "gpt-4.1", "gpt-4o", "o4-mini", "o3-mini",
]);

interface ModelInfo {
  id: string;
  displayName: string;
  isDefault: boolean;
  isPremium: boolean;
  supportsVision: boolean;
}

const MODELS_LIST: ModelInfo[] = [
  { id: "gpt-5-mini", displayName: "GPT-5 Mini", isDefault: false, isPremium: false, supportsVision: true },
  { id: "gpt-5-nano", displayName: "GPT-5 Nano", isDefault: false, isPremium: false, supportsVision: true },
  { id: "gpt-4.1-nano", displayName: "GPT-4.1 Nano", isDefault: true, isPremium: false, supportsVision: true },
  { id: "gpt-4.1-mini", displayName: "GPT-4.1 Mini", isDefault: false, isPremium: false, supportsVision: true },
  { id: "gpt-4o-mini", displayName: "GPT-4o Mini", isDefault: false, isPremium: false, supportsVision: true },
  { id: "gpt-5.4", displayName: "GPT-5.4", isDefault: false, isPremium: true, supportsVision: true },
  { id: "gpt-5.2-chat", displayName: "GPT-5.2 Chat", isDefault: false, isPremium: true, supportsVision: true },
  { id: "gpt-5", displayName: "GPT-5", isDefault: false, isPremium: true, supportsVision: true },
  { id: "gpt-4.1", displayName: "GPT-4.1", isDefault: false, isPremium: true, supportsVision: true },
  { id: "gpt-4o", displayName: "GPT-4o", isDefault: false, isPremium: true, supportsVision: true },
  { id: "o4-mini", displayName: "o4 Mini", isDefault: false, isPremium: true, supportsVision: true },
  { id: "o3-mini", displayName: "o3 Mini", isDefault: false, isPremium: true, supportsVision: false },
];

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "Content-Type, api-key, Authorization, Accept, Accept-Language, X-Timestamp, X-Signature, X-Premium",
  "Access-Control-Allow-Methods": "GET,HEAD,POST,PUT,DELETE,OPTIONS",
};

// ---- Env helpers ----

function getEnv(name: string): string {
  const val = process.env[name];
  if (!val) throw new Error(`Missing environment variable: ${name}`);
  return val;
}

function getEnvOptional(name: string): string | undefined {
  return process.env[name];
}

// ---- Crypto helpers ----

async function computeHmacSha256(secretHex: string, message: string): Promise<string> {
  const crypto = await import("crypto");
  const keyBuffer = Buffer.from(secretHex, "hex");
  const hmac = crypto.createHmac("sha256", keyBuffer);
  hmac.update(message);
  return hmac.digest("hex");
}

// ---- Auth ----

interface AuthResult {
  valid: boolean;
  reason?: string;
}

async function isAuthorized(request: HttpRequest, secret: string): Promise<AuthResult> {
  const timestamp = request.headers.get("x-timestamp");
  const signature = request.headers.get("x-signature");

  if (!timestamp || !signature) {
    return { valid: false, reason: "Missing timestamp or signature" };
  }

  const requestTime = parseInt(timestamp, 10);
  if (isNaN(requestTime)) {
    return { valid: false, reason: "Invalid timestamp format" };
  }

  const currentTime = Math.floor(Date.now() / 1000);
  if (Math.abs(currentTime - requestTime) > TIMESTAMP_TOLERANCE_SECONDS) {
    return { valid: false, reason: "Timestamp expired" };
  }

  // Path: Azure Functions includes the base route, we need the original path
  const url = new URL(request.url);
  const path = url.pathname.replace(/^\/api/, ""); // strip /api prefix

  const expectedSignature = await computeHmacSha256(secret, `${timestamp}:${path}`);

  if (signature.toLowerCase() !== expectedSignature.toLowerCase()) {
    return { valid: false, reason: "Invalid signature" };
  }

  return { valid: true };
}

// ---- CORS ----

function corsHeaders(): Record<string, string> {
  return { ...CORS_HEADERS };
}

function buildResponse(body: string | null, status: number, contentType?: string): HttpResponseInit {
  const headers: Record<string, string> = { ...CORS_HEADERS };
  if (contentType) headers["Content-Type"] = contentType;
  return { status, headers, body: body ?? undefined };
}

// ---- Forward helpers ----

function cloneRequestHeaders(request: HttpRequest): Record<string, string> {
  const headers: Record<string, string> = {};
  request.headers.forEach((value, key) => {
    if (!key.toLowerCase().startsWith("cf-") && key.toLowerCase() !== "host") {
      headers[key] = value;
    }
  });
  // Remove signature headers
  delete headers["x-timestamp"];
  delete headers["x-signature"];
  return headers;
}

function buildAzureURL(requestPath: string, searchParams: string, azureEndpoint: string): URL {
  const baseURL = new URL(azureEndpoint);
  const normalizedBasePath = baseURL.pathname.replace(/\/+$/, "");
  const incomingPath = requestPath.replace(/^\/+/, "");

  const combinedPath = [normalizedBasePath, incomingPath].filter(Boolean).join("/");
  baseURL.pathname = `/${combinedPath}`.replace(/\/{2,}/g, "/");
  baseURL.search = searchParams;

  const sp = new URLSearchParams(baseURL.search);
  if (!sp.has("api-version")) {
    sp.set("api-version", "2025-01-01-preview");
  }
  baseURL.search = sp.toString();

  return baseURL;
}

// ---- HTTP request helper using Node.js https module ----
// Node fetch (undici) on Azure Functions has issues with SSE/chunked responses.
// Using native https module for reliable upstream proxying.

interface UpstreamResponse {
  statusCode: number;
  headers: Record<string, string>;
  body: Buffer;
}

function httpsRequest(
  targetURL: URL,
  method: string,
  headers: Record<string, string>,
  body?: Buffer
): Promise<UpstreamResponse> {
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: targetURL.hostname,
        port: targetURL.port || 443,
        path: targetURL.pathname + targetURL.search,
        method,
        headers,
      },
      (res) => {
        const chunks: Buffer[] = [];
        const respHeaders: Record<string, string> = {};
        for (const [key, value] of Object.entries(res.headers)) {
          if (typeof value === "string") respHeaders[key] = value;
          else if (Array.isArray(value)) respHeaders[key] = value.join(", ");
        }

        res.on("data", (chunk: Buffer) => chunks.push(chunk));
        res.on("end", () => {
          resolve({
            statusCode: res.statusCode || 500,
            headers: respHeaders,
            body: Buffer.concat(chunks),
          });
        });
        res.on("error", reject);
      }
    );

    req.on("error", reject);
    req.setTimeout(120000, () => {
      req.destroy(new Error("Request timeout"));
    });

    if (body) req.write(body);
    req.end();
  });
}

// ---- Handlers ----

function handleModels(request: HttpRequest): HttpResponseInit {
  const url = new URL(request.url);
  const includePremium = url.searchParams.get("premium") === "1";
  const models = includePremium
    ? MODELS_LIST
    : MODELS_LIST.filter((m) => !m.isPremium).map(({ isPremium: _, ...rest }) => rest);
  return buildResponse(JSON.stringify({ models }), 200, "application/json");
}

async function handleTTS(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  const clientIP = request.headers.get("x-forwarded-for") || "unknown";
  context.log(`TTS Request - IP: ${clientIP}`);

  const ttsEndpoint = getEnvOptional("TTS_ENDPOINT");
  if (!ttsEndpoint) {
    return buildResponse(
      JSON.stringify({ error: "Configuration error", message: "TTS_ENDPOINT not configured" }),
      500, "application/json"
    );
  }

  try {
    const ttsURL = new URL(ttsEndpoint);
    const headers = cloneRequestHeaders(request);
    headers["api-key"] = getEnv("AZURE_API_KEY");
    headers["host"] = ttsURL.host;

    const body = request.method !== "GET" && request.method !== "HEAD"
      ? Buffer.from(await request.arrayBuffer())
      : undefined;

    const upstream = await httpsRequest(ttsURL, request.method, headers, body);

    const respHeaders: Record<string, string> = { ...upstream.headers };
    delete respHeaders["transfer-encoding"];
    delete respHeaders["connection"];
    delete respHeaders["content-length"];
    Object.assign(respHeaders, CORS_HEADERS);

    return { status: upstream.statusCode, headers: respHeaders, body: upstream.body };
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return buildResponse(
      JSON.stringify({ error: "TTS request failed", message }),
      502, "application/json"
    );
  }
}

async function handleLLM(
  request: HttpRequest,
  requestPath: string,
  context: InvocationContext
): Promise<HttpResponseInit> {
  const pathParts = requestPath.split("/").filter(Boolean);
  const requestedModel = pathParts[0];
  const clientIP = request.headers.get("x-forwarded-for") || "unknown";

  context.log(`LLM Request - Model: ${requestedModel}, IP: ${clientIP}`);

  if (!requestedModel || !ALLOWED_MODELS.includes(requestedModel)) {
    return buildResponse(
      JSON.stringify({
        error: "Invalid model",
        message: `Model '${requestedModel}' is not allowed. Allowed models: ${ALLOWED_MODELS.join(", ")}`,
      }),
      400, "application/json"
    );
  }

  if (PREMIUM_MODELS.has(requestedModel)) {
    const premiumHeader = request.headers.get("x-premium");
    if (premiumHeader !== "true") {
      return buildResponse(
        JSON.stringify({
          error: "Premium required",
          message: `Model '${requestedModel}' requires a premium subscription.`,
        }),
        403, "application/json"
      );
    }
  }

  const azureEndpoint = getEnvOptional("AZURE_ENDPOINT");
  if (!azureEndpoint) {
    return buildResponse(
      JSON.stringify({ error: "Configuration error", message: "AZURE_ENDPOINT not configured" }),
      500, "application/json"
    );
  }

  try {
    const url = new URL(request.url);
    const targetURL = buildAzureURL(requestPath, url.search, azureEndpoint);
    const headers = cloneRequestHeaders(request);
    headers["api-key"] = getEnv("AZURE_API_KEY");
    headers["host"] = targetURL.host;

    const reqBody = request.method !== "GET" && request.method !== "HEAD"
      ? Buffer.from(await request.arrayBuffer())
      : undefined;

    const upstreamStart = Date.now();
    const upstream = await httpsRequest(targetURL, request.method, headers, reqBody);
    const upstreamTTFB = Date.now() - upstreamStart;

    const respHeaders: Record<string, string> = { ...upstream.headers };
    // Remove headers that could conflict with Azure Functions response handling
    delete respHeaders["transfer-encoding"];
    delete respHeaders["connection"];
    delete respHeaders["content-length"]; // let Azure Functions compute it
    Object.assign(respHeaders, CORS_HEADERS);
    respHeaders["X-Upstream-TTFB"] = upstreamTTFB.toString();

    return { status: upstream.statusCode, headers: respHeaders, body: upstream.body };
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return buildResponse(
      JSON.stringify({ error: "Upstream request failed", message }),
      502, "application/json"
    );
  }
}

// ---- Main catch-all route ----
// Maps: /api/{*path} → handles /models, /tts, /{model}/chat/completions

app.http("proxy", {
  methods: ["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS"],
  authLevel: "anonymous",
  route: "{*restOfPath}",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    // CORS preflight
    if (request.method === "OPTIONS") {
      return { status: 204, headers: corsHeaders() };
    }

    const url = new URL(request.url);
    // Strip /api prefix that Azure Functions adds
    const path = url.pathname.replace(/^\/api/, "") || "/";

    // /models — no auth required
    if (path === "/models") {
      return handleModels(request);
    }

    // All other routes require HMAC auth
    const authResult = await isAuthorized(request, getEnv("APP_SECRET"));
    if (!authResult.valid) {
      return buildResponse(
        JSON.stringify({ error: "Unauthorized", reason: authResult.reason }),
        401, "application/json"
      );
    }

    // /tts
    if (path === "/tts") {
      return handleTTS(request, context);
    }

    // /{model}/chat/completions
    return handleLLM(request, path, context);
  },
});
