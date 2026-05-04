# TLingo Web

A minimal, Apple-style web frontend for TLingo, the AI translator. Built with **Vite + TypeScript**, no UI framework.

## Features

Five actions, mirroring the iOS client:

- **Translate** — fast, fluent translation
- **Sentence Translate** — sentence-by-sentence pairs
- **Grammar Check** — polished text + diff + explanation
- **Polish** — natural phrasing in the same language, with diff
- **Sentence Analysis** — grammar & collocations breakdown

Other niceties: streaming output (SSE), `⌘/Ctrl+Enter` to run, copy to clipboard, dark theme, GitHub/Google sign-in with per-user history and cross-device settings sync.

## Setup

### 1. Backend secret

The web client signs requests with the same HMAC secret as the iOS app. The secret is read from the repo-root `.env` (already populated for development):

```
AITRANSLATOR_CLOUD_SECRET=…
```

### 2. Supabase (auth + history)

Create a Supabase project, then add to repo-root `.env`:

```
VITE_SUPABASE_URL=https://<ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<anon-key>
```

Apply the schema in `supabase/migrations/000_init.sql` (via the Supabase dashboard SQL editor or `supabase db push`).

Configure OAuth providers in **Auth → Providers**:

- **GitHub** — create an OAuth app at https://github.com/settings/developers; callback `https://<ref>.supabase.co/auth/v1/callback`.
- **Google** — create an OAuth client (Web application) in Google Cloud Console; authorized redirect `https://<ref>.supabase.co/auth/v1/callback`; scopes include `openid`.

In **Auth → URL Configuration → Redirect URLs**, add `http://localhost:5173/auth/callback` and your production URL.

### 3. Run

```bash
npm install
npm run dev
```

## Build

```bash
npm run build      # outputs dist/
npm run preview    # serve the production build
```

## Deploy to Cloudflare Pages

Production target: https://tlingo.zanderwang.com

Pages project settings:

- **Root directory**: `web`
- **Build command**: `npm install && npm run build`
- **Build output**: `dist`
- **Node**: pinned to 20 via `web/.nvmrc`

Required environment variables (Production **and** Preview):

| Var | Notes |
|---|---|
| `VITE_SUPABASE_URL` | `https://<ref>.supabase.co` |
| `VITE_SUPABASE_ANON_KEY` | Publishable key from Supabase dashboard |
| `AITRANSLATOR_CLOUD_SECRET` | HMAC secret shared with the Worker |
| `AITRANSLATOR_CLOUD_ENDPOINT` | Optional. Default Azure endpoint baked into `vite.config.ts`. |
| `AITRANSLATOR_CLOUD_PROXY_PREFIX` | Optional. Defaults to `/api` in production. |

The production bundle calls the `aitranslator` Worker through the same-origin `/api` route on `tlingo.zanderwang.com`. The legacy `translator-api.zanderwang.com` Worker route remains available for existing app clients. The dev server still proxies `/cloud` locally to bypass CORS.

Billing requires the Worker secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `STRIPE_SECRET_KEY`, and `STRIPE_WEBHOOK_SECRET`. Configure the Stripe webhook endpoint as `https://tlingo.zanderwang.com/api/billing/webhook`.

`public/_redirects` provides SPA fallback so OAuth callback paths (`/auth/callback?code=...`) resolve to `index.html`.

After the first deploy, in the Supabase dashboard add `https://tlingo.zanderwang.com/auth/callback` to **Auth → URL Configuration → Redirect URLs**, and add `https://tlingo.zanderwang.com` to the Google OAuth client's Authorized JavaScript origins.
