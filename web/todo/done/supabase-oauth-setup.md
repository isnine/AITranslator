# TLingo Web — Supabase OAuth Setup (Handoff)

> Owner: 接手的 AI 助手
> 状态: 数据库已就绪，等待 OAuth Provider 与 Redirect URL 配置

## 背景

TLingo Web 是 `/Users/zander/Work/AITranslator/web/` 下的 Vite + TypeScript SPA，作为 iOS TLingo 翻译 app 的网页客户端。已完成 Supabase Auth 集成代码（GitHub / Google 登录、按用户云端同步设置、保存翻译历史，未登录用户被门禁拦截）。

数据库部分已经做完：表结构、RLS 策略、Advisor 检查、`.env` 写入。**剩下只有 Supabase Dashboard 上的 OAuth Provider 配置和最终烟测。**

## Supabase 项目信息

- **Project Ref**: `xzhkzhwnnwgnobrrnmak`
- **Project URL**: `https://xzhkzhwnnwgnobrrnmak.supabase.co`
- **Dashboard**: https://supabase.com/dashboard/project/xzhkzhwnnwgnobrrnmak
- **Auth callback (Supabase 侧固定值)**: `https://xzhkzhwnnwgnobrrnmak.supabase.co/auth/v1/callback`
- 用户已在本地通过 `supabase login` 完成 CLI 鉴权，并已 `supabase link --project-ref xzhkzhwnnwgnobrrnmak`

`.env`（位于仓库根 `/Users/zander/Work/AITranslator/.env`）已写入：

```
VITE_SUPABASE_URL=https://xzhkzhwnnwgnobrrnmak.supabase.co
VITE_SUPABASE_ANON_KEY=sb_publishable_4y-Ihi78RtXFNcuCc6P_uA_SwsMsFCg
```

> 注意：变量名仍叫 `_ANON_KEY`，但值用的是新版 publishable key（Supabase 推荐浏览器使用，与 anon 等效，可被 RLS 限制）。

## 已完成的代码改动

| 类型 | 文件 |
|---|---|
| 新增 | `web/src/supabase.ts` — supabase-js 客户端单例 |
| 新增 | `web/src/auth-session.ts` — `signInWith` / `signOut` / `onAuthChange` / `consumeOAuthCallbackIfPresent` |
| 新增 | `web/src/cloud-storage.ts` — `loadCloudSettings` / `saveCloudSettings` / `appendHistory` / `listHistory` / `deleteHistoryEntry` |
| 新增 | `web/supabase/migrations/000_init.sql` — 表 + RLS（已应用到远端） |
| 修改 | `web/src/llm.ts` — 未登录时抛 `AUTH_REQUIRED` |
| 修改 | `web/src/main.ts` — 账号槽（Sign in / 头像 + popover）、登录弹窗（GitHub / Google）、历史弹窗、`onAuthChange` 订阅、OAuth 回调清洗、`AUTH_REQUIRED` 拦截、`appendHistory` 写入、`persistSettings`（本地 + 云双写）、登录后 `loadCloudSettings` 合并 |
| 修改 | `web/src/style.css` — avatar / oauth-btn / popover / history 列表样式 |
| 修改 | `web/vite.config.ts`、`web/src/env.d.ts` — 注入 `VITE_SUPABASE_*` |
| 修改 | `web/src/types.ts` — `TranslationHistoryEntry` |
| 修改 | `web/README.md` — Supabase 设置步骤 |

`npx tsc --noEmit` ✅ 通过。

## 已应用的数据库 schema（远端 + advisor 全绿）

```
public.user_settings  (user_id PK → auth.users, model, target_language, updated_at)  + RLS
public.translations   (id, user_id → auth.users, created_at, action_id,
                       source_lang, target_lang, input, output)                     + RLS
                       index: translations_user_created_idx (user_id, created_at desc)
```

策略（用 `(select auth.uid())` 包装以满足 advisor 性能建议）：

- `user_settings`: own row read / insert / update
- `translations`: own rows read / insert / delete

未登录访问 Data API 已验证返回 `[]`。

---

## 你（接手 AI）需要做的事

### 1. GitHub OAuth Provider

1. 让用户去 https://github.com/settings/developers → **New OAuth App**：
   - Application name: `TLingo Web`
   - Homepage URL: `http://localhost:5173`（生产域名后续再加一个 OAuth App）
   - **Authorization callback URL**: `https://xzhkzhwnnwgnobrrnmak.supabase.co/auth/v1/callback`
2. 拿到 Client ID / Client Secret。
3. 在 https://supabase.com/dashboard/project/xzhkzhwnnwgnobrrnmak/auth/providers → **GitHub** → 开启 → 粘贴 → Save。

### 2. Google OAuth Provider

1. 让用户去 https://console.cloud.google.com → APIs & Services → Credentials → **Create Credentials → OAuth client ID**：
   - Application type: **Web application**
   - Name: `TLingo Web`
   - Authorized JavaScript origins: `http://localhost:5173`（生产域名后续再加）
   - **Authorized redirect URI**: `https://xzhkzhwnnwgnobrrnmak.supabase.co/auth/v1/callback`
2. 如果项目还没 OAuth consent screen，先按提示创建（External、scopes 至少包含 `openid`、`email`、`profile`）。
3. 拿到 Client ID / Client Secret。
4. 在 https://supabase.com/dashboard/project/xzhkzhwnnwgnobrrnmak/auth/providers → **Google** → 开启 → 粘贴 Client ID/Secret → 在 **Authorized Client IDs** 也填一遍 → Save。

### 3. Redirect URLs 白名单

在 https://supabase.com/dashboard/project/xzhkzhwnnwgnobrrnmak/auth/url-configuration 添加：

- `http://localhost:5173/auth/callback`
- 生产域名的 `/auth/callback`（如已知；现在可以先不加）

### 4. 烟测

```bash
cd /Users/zander/Work/AITranslator/web
npm install   # 确保 @supabase/supabase-js 已装
npm run dev
```

打开 http://localhost:5173，按以下顺序验证：

1. 顶部右侧显示 **Sign in** 按钮。
2. 点击 → 弹出登录窗 → **Continue with GitHub** → 走完 OAuth → 回到 `/auth/callback?code=...` → app 自动清掉 query → 顶部出现首字母头像。
3. Supabase Dashboard → Authentication → Users 出现一行新用户。
4. 在网页里改一下目标语言（如改成 ja），刷新页面：目标语言保持。在另一个浏览器里登录同账号：目标语言同步过来（云端 settings sync）。
5. 输入文本点 Translate，等流式输出完毕。点头像 → History → 看到刚才那一条（action / 语言 / 输入 / 输出）。
6. 点 Delete → 该条消失。
7. 点头像 → Sign out → 顶部恢复 Sign in。点 Translate → 弹出登录窗（AUTH_REQUIRED 门禁）。
8. 跑 `npx tsc --noEmit` 确认仍干净。

### 5. 验收 SQL 检查（可选）

```bash
cd /Users/zander/Work/AITranslator/web
supabase db query --linked --agent=no \
  "select count(*) as user_settings_rows from public.user_settings;
   select count(*) as translation_rows from public.translations;"
supabase db advisors --linked --agent=no   # 应输出 "No issues found"
```

## 排错指南

- **"redirect_uri_mismatch"**：Google/GitHub 那边登记的回调和 `https://xzhkzhwnnwgnobrrnmak.supabase.co/auth/v1/callback` 不一致。
- **登录回来停在 `/auth/callback?code=...` 不跳转**：检查浏览器控制台 → 大概率是 supabase-js 客户端没拿到 env（`VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` 没注入），重启 `npm run dev`。
- **登录后 history 一直空**：检查 `cloud-storage.ts` 里 `appendHistory` 是否报 RLS 错（401/403）。Advisor 已验证策略正确，多半是 session 还没建立就调用——确认 `streamChat` 之前 `getCurrentSession()` 已返回有效 session。
- **Provider 设置完登录失败**：去 Supabase Dashboard → **Logs → Auth** 看具体错误。
- **新表的 Data API 不可访问**：检查 https://supabase.com/dashboard/project/xzhkzhwnnwgnobrrnmak/integrations/data_api/settings → `public` schema 是否暴露；如未暴露需要在那里勾选，或显式 `grant select, insert, update, delete on public.<table> to anon, authenticated;`。

## 完成后

- 把 `web/todo/supabase-oauth-setup.md` 移到 `web/todo/done/` 或直接删除。
- 如果配置过程中改动了 SQL，记得同步更新 `web/supabase/migrations/000_init.sql`。
- 让用户做一次 `git status`，确认 `.env` 没被误提交（应在 `.gitignore`）。
