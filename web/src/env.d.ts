/// <reference types="vite/client" />

declare const __CLOUD_SECRET__: string;
declare const __CLOUD_PROXY_PREFIX__: string;
declare const __CLOUD_UPSTREAM_BASE__: string;

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL: string;
  readonly VITE_SUPABASE_ANON_KEY: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
