import { defineConfig, loadEnv } from "vite";
import { resolve } from "node:path";

export default defineConfig(({ mode }) => {
  // Read .env from the repo root (one level up). Loads both AITRANSLATOR_*
  // (HMAC secret, upstream endpoint) and VITE_* (Supabase URL/anon key).
  const env = loadEnv(mode, resolve(__dirname, ".."), ["AITRANSLATOR_", "VITE_"]);

  const cloudEndpoint =
    env.AITRANSLATOR_CLOUD_ENDPOINT ?? "https://aitranslator-japaneast.azurewebsites.net/api";
  const cloudSecret = env.AITRANSLATOR_CLOUD_SECRET ?? "";

  const upstream = new URL(cloudEndpoint);
  const upstreamOrigin = `${upstream.protocol}//${upstream.host}`;
  const upstreamBasePath = upstream.pathname.replace(/\/+$/, ""); // e.g. "/api"

  // Dev: route through Vite proxy at "/cloud" to bypass CORS.
  // Prod: hit the public Worker directly (CORS is open on the Worker).
  const proxyPrefix =
    env.AITRANSLATOR_CLOUD_PROXY_PREFIX ??
    (mode === "production" ? "/api" : "/cloud");

  return {
    envDir: resolve(__dirname, ".."),
    define: {
      // Inject at build/dev time — bundled into the client. Acceptable here
      // because the user is testing locally and explicitly opted in.
      __CLOUD_SECRET__: JSON.stringify(cloudSecret),
      __CLOUD_PROXY_PREFIX__: JSON.stringify(proxyPrefix),
      __CLOUD_UPSTREAM_BASE__: JSON.stringify(upstreamBasePath),
    },
    server: {
      proxy: {
        // Dev-only proxy → bypasses browser CORS by routing through Vite.
        "/cloud": {
          target: upstreamOrigin,
          changeOrigin: true,
          secure: true,
          rewrite: (p) => p.replace(/^\/cloud/, upstreamBasePath),
        },
      },
    },
  };
});
