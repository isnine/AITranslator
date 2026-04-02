# Marketplace Web API

Base URL: `translator-api.zanderwang.com`

Web UI: `translator-api.zanderwang.com/web`

## Overview

The Marketplace has two API layers:

| Layer | Path prefix | Auth | Consumers |
|-------|------------|------|-----------|
| **Native API** | `/marketplace/` | HMAC-SHA256 (X-Timestamp + X-Signature) | iOS / macOS app |
| **Web API** | `/web/api/` | None (admin ops require X-Admin-Password) | Web browser |

Both layers query the same D1 database directly.

## Web API Endpoints

### List Actions

```
GET /web/api/actions
```

**Query Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `q` | string | `""` | Search across name, description, author |
| `category` | string | — | Filter: `translation`, `writing`, `analysis`, `other` |
| `sort` | string | `newest` | Sort: `newest` or `popular` |
| `page` | int | `1` | Page number |
| `limit` | int | `20` | Items per page (max 50) |

**Response** `200`:

```json
{
  "actions": [
    {
      "id": "a1b2c3...",
      "name": "Translate to English",
      "prompt": "Translate the following text to English:\n{text}",
      "action_description": "Simple translation action",
      "output_type": "plain",
      "usage_scenes": 7,
      "category": "translation",
      "author_name": "Zander",
      "download_count": 42,
      "created_at": "2026-03-15T10:30:00Z"
    }
  ],
  "page": 1,
  "total_pages": 3,
  "total_count": 52,
  "has_more": true
}
```

### Create Action

```
POST /web/api/actions
Content-Type: application/json
```

**Body:**

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | yes | — | Action name |
| `prompt` | string | yes | — | Prompt template (use `{text}`, `{targetLanguage}`) |
| `action_description` | string | no | `""` | Description |
| `output_type` | string | no | `plain` | `plain`, `diff`, `sentencePairs`, `grammarCheck` |
| `usage_scenes` | int | no | `7` | Bitmask: 1=App, 2=ContextRead, 4=ContextEdit |
| `category` | string | no | `other` | `translation`, `writing`, `analysis`, `other` |
| `author_name` | string | no | `Anonymous` | Author display name |

**Response** `201`:

```json
{
  "action": { ...action fields }
}
```

### Update Action (Admin)

```
PUT /web/api/actions/:id
Content-Type: application/json
X-Admin-Password: <password>
```

**Body:** Same fields as Create (all optional — only provided fields are updated).

**Response** `200`:

```json
{
  "action": { ...updated action fields }
}
```

**Errors:** `403` if admin password missing/invalid, `404` if action not found.

### Delete Action (Admin)

```
DELETE /web/api/actions/:id
X-Admin-Password: <password>
```

**Response** `200`:

```json
{
  "deleted": true
}
```

**Errors:** `403` if admin password missing/invalid, `404` if action not found.

### Verify Admin Password

```
POST /web/api/admin/verify
Content-Type: application/json
```

**Body:**

```json
{
  "password": "your-admin-password"
}
```

**Response** `200`:

```json
{
  "valid": true
}
```

## Native API Endpoints (HMAC-authenticated)

All requests require headers:
- `X-Timestamp`: Unix timestamp (seconds)
- `X-Signature`: HMAC-SHA256(APP_SECRET, `"{timestamp}:{path}"`)

Timestamp must be within 120 seconds of server time.

### List Actions

```
GET /marketplace/actions?q=&category=&sort=newest&page=1&limit=20
```

Same response format as Web API.

### Create Action

```
POST /marketplace/actions
X-User-ID: <device-uuid>
```

Same body/response as Web API. `X-User-ID` stored as `creator_id` for ownership tracking.

### Delete Action (Owner Only)

```
DELETE /marketplace/actions/:id
X-User-ID: <device-uuid>
```

Only the original creator (matched by `creator_id`) can delete. Returns `403` if not owner.

### Increment Download Count

```
POST /marketplace/actions/:id/download
```

**Response** `200`:

```json
{
  "download_count": 43
}
```

## Data Model

### MarketplaceAction

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | 16-byte hex (auto-generated) |
| `name` | string | Action name |
| `prompt` | string | LLM prompt template |
| `action_description` | string | User-facing description |
| `output_type` | string | `plain` / `diff` / `sentencePairs` / `grammarCheck` |
| `usage_scenes` | int | Bitmask: 1=App, 2=ContextRead, 4=ContextEdit |
| `category` | string | `translation` / `writing` / `analysis` / `other` |
| `author_name` | string | Display name |
| `download_count` | int | Download counter |
| `created_at` | string | ISO 8601 UTC |
| `creator_id` | string | Device UUID (stripped from API responses) |

### Usage Scenes Bitmask

| Bit | Value | Scene |
|-----|-------|-------|
| 0 | 1 | App (main translation UI) |
| 1 | 2 | Context Read (selected text, read-only) |
| 2 | 4 | Context Edit (text editor context) |

Default: `7` (all scenes enabled).

## Deployment

```bash
cd Workers

# Set admin password (first time only)
npx wrangler secret put ADMIN_PASSWORD

# Deploy
npx wrangler deploy
```

Worker secrets (set via `wrangler secret put`):
- `APP_SECRET` — HMAC shared secret for native API
- `AZURE_API_KEY` — Azure OpenAI key
- `AZURE_ENDPOINT` — Azure OpenAI endpoint
- `TTS_ENDPOINT` — Text-to-speech endpoint
- `ADMIN_PASSWORD` — Web admin password

D1 Database: `aitranslator-marketplace` (ID: `7f192cb7-8165-43e5-9ac6-035c7bf194e7`)
