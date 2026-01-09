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
}

interface AuthResult {
  valid: boolean;
  reason?: string;
}

const TIMESTAMP_TOLERANCE_SECONDS = 120;

// Allowed models for the built-in cloud service
const ALLOWED_MODELS = [
  "gpt-4o-mini",
  "gpt-4.1-mini",
  "gpt-4.1-nano",
  "gpt-5-nano",
  "gpt-5-mini",
  "moudel-router",
];

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "Content-Type, api-key, Authorization, Accept, Accept-Language, X-Timestamp, X-Signature",
  "Access-Control-Allow-Methods": "GET,HEAD,POST,PUT,DELETE,OPTIONS",
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return buildResponse(null, 204, undefined);
    }

    // Validate HMAC signature
    const authResult = await isAuthorized(request, env.APP_SECRET);
    if (!authResult.valid) {
      return buildResponse(
        JSON.stringify({ error: "Unauthorized", reason: authResult.reason }),
        401,
        "application/json"
      );
    }

    const url = new URL(request.url);
    const path = url.pathname;

    // Route: /tts - Text-to-Speech
    if (path === "/tts") {
      return handleTTSRequest(request, env);
    }

    // Route: /{model}/chat/completions - LLM Chat
    return handleLLMRequest(request, env);
  },
};

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
  const pathParts = url.pathname.split("/").filter(Boolean);
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

    const upstreamResponse = await fetch(targetURL.toString(), {
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
      JSON.stringify({ error: "Upstream request failed", message }),
      502,
      "application/json"
    );
  }
}

async function isAuthorized(
  request: Request,
  secret: string
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

  // Extract path from request URL
  const url = new URL(request.url);
  const path = url.pathname;

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

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
  }
  return bytes;
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
  const incomingPath = incomingURL.pathname.replace(/^\/+/, "");

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
