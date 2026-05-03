# Follow-up: Move HMAC verification off the browser

> 触发时机：tlingo.zanderwang.com 上线一段时间，或开始看到滥用迹象。

## 现状

`AITRANSLATOR_CLOUD_SECRET` 现在被 Vite 嵌入到 `dist/assets/index-*.js`。任何人 `view-source` 后从 bundle 提取这个 secret，就可以直接用 HMAC 调 `translator-api.zanderwang.com/<model>/chat/completions`，绕过 Supabase 登录门禁。

当前缓解：浏览器路径上必须先登录 Supabase 才能触发翻译（`web/src/llm.ts` 的 AUTH_REQUIRED）。但这只挡 UI 路径，挡不住直接打 Worker。

## 目标

让 Worker 只接受带有效 Supabase JWT 的请求，前端从 bundle 移除 HMAC secret。

## 实现思路

1. **Worker 端**（`Workers/azureProxyWorker.ts`）
   - 在 `/{model}/chat/completions` 路由前增加分支：如果请求带 `Authorization: Bearer <jwt>`，且能用 Supabase 的 `JWKS` 验证通过（issuer = `https://xzhkzhwnnwgnobrrnmak.supabase.co/auth/v1`），则放行，跳过 HMAC。
   - JWKS：`https://xzhkzhwnnwgnobrrnmak.supabase.co/auth/v1/.well-known/jwks.json`。可以缓存到 Worker memory / KV。
   - 选 jose 或者直接用 Web Crypto + 自己解 JWT。Cloudflare 文档有现成示例。
   - 保留 HMAC 兼容（iOS 客户端仍用 HMAC），用 Header 区分两条路径。

2. **前端**（`web/src/llm.ts`、`web/vite.config.ts`）
   - 删 `__CLOUD_SECRET__` 与 `signCloudRequest` 调用。
   - `streamChat` 改为：`Authorization: Bearer ${session.access_token}`。
   - `vite.config.ts` 移除 `__CLOUD_SECRET__` define，从 README 删 `AITRANSLATOR_CLOUD_SECRET` 的说明。
   - Pages 项目 → Environment variables 移除 `AITRANSLATOR_CLOUD_SECRET`。

3. **Rate limit（可选）**
   - 在 Worker 里按 `sub`（用户 id）做 KV 计数，每分钟 N 次。
   - 防止单个登录账号刷量。

## 风险

- 改动同时影响 Worker 与 web 客户端，需要先在 Worker 加新分支并部署，再切前端，分两步避免破坏现有 iOS 客户端。
- iOS 客户端仍走 HMAC 路径，必须保留兼容。

## 不做的事

- 不需要把 secret 改成动态分发或代理 secret 服务，复杂度不值。直接删才是终态。
