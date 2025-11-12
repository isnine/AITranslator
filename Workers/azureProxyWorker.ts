/**
 * Cloudflare Worker that validates incoming requests with a shared client token
 * before proxying them to Azure OpenAI using secrets stored in the environment.
 */
const CLIENT_HEADER = "api-key";
const CLIENT_TOKEN = "defaulttoken";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "Content-Type, api-key, Authorization, Accept, Accept-Language",
  "Access-Control-Allow-Methods": "GET,HEAD,POST,PUT,DELETE,OPTIONS",
};

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return buildResponse(null, 204);
    }

    if (!isAuthorized(request)) {
      return buildResponse(
        JSON.stringify({ error: "Unauthorized" }),
        401,
        "application/json",
      );
    }

    try {
      const targetURL = buildAzureURL(request, env.AZURE_ENDPOINT);
      const forwardHeaders = cloneHeaders(request.headers);

      forwardHeaders.set(CLIENT_HEADER, env.AZURE_API_KEY);
      forwardHeaders.set("host", targetURL.host);

      const upstreamResponse = await fetch(targetURL.toString(), {
        method: request.method,
        headers: forwardHeaders,
        body: shouldHaveBody(request.method) ? request.body : null,
        redirect: "manual",
        cf: { cacheTtl: 0 },
      });

      const responseHeaders = new Headers(upstreamResponse.headers);
      applyCors(responseHeaders);

      return new Response(upstreamResponse.body, {
        status: upstreamResponse.status,
        headers: responseHeaders,
      });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Unknown error";
      return buildResponse(
        JSON.stringify({ error: "Upstream request failed", message }),
        502,
        "application/json",
      );
    }
  },
};

function isAuthorized(request) {
  return request.headers.get(CLIENT_HEADER) === CLIENT_TOKEN;
}

function shouldHaveBody(method) {
  return !["GET", "HEAD"].includes(method.toUpperCase());
}

function buildAzureURL(request, azureEndpoint) {
  const incomingURL = new URL(request.url);
  const baseURL = new URL(azureEndpoint);

  const normalizedBasePath = baseURL.pathname.replace(/\/+$/, "");
  const incomingPath = incomingURL.pathname.replace(/^\/+/, "");

  const combinedPath = [normalizedBasePath, incomingPath]
    .filter(Boolean)
    .join("/");

  baseURL.pathname = `/${combinedPath}`.replace(/\/{2,}/g, "/");
  baseURL.search = incomingURL.search;

  return baseURL;
}

function cloneHeaders(headers) {
  const clone = new Headers();
  headers.forEach((value, key) => {
    if (!key.toLowerCase().startsWith("cf-")) {
      clone.append(key, value);
    }
  });
  return clone;
}

function applyCors(headers) {
  Object.entries(CORS_HEADERS).forEach(([key, value]) => {
    headers.set(key, value);
  });
}

function buildResponse(body, status, contentType) {
  const headers = new Headers();
  applyCors(headers);

  if (contentType) {
    headers.set("Content-Type", contentType);
  }

  return new Response(body, { status, headers });
}
