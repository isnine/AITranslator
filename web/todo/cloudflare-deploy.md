# TLingo Web → Cloudflare Pages Deploy (Handoff)

> Owner: 接手的 AI 助手
> 状态：代码已就绪并通过本地生产构建烟测；剩余全部在 Cloudflare Dashboard 与 Supabase Dashboard 上手动完成。

## 背景

`/Users/zander/Work/AITranslator/web/` 是 Vite + TS SPA。已完成 Supabase Auth + 历史/设置同步，并已让生产构建直接调用现有 Cloudflare Worker `aitranslator`（`translator-api.zanderwang.com`，CORS 已开）。目标是把 SPA 部署到 Cloudflare Pages，绑定 `tlingo.zanderwang.com`。

构建命令本地已验证：

```bash
cd /Users/zander/Work/AITranslator/web
npm run build
# dist/index.html, dist/assets/index-*.{js,css}, dist/_redirects
```

`dist/assets/index-*.js` 已包含 `https://translator-api.zanderwang.com`，且 `_redirects` 已被自动拷贝到 `dist/`（Vite 会复制 `public/` 全部内容）。

## 已就绪的代码改动

- `web/vite.config.ts` — 生产模式下 `__CLOUD_PROXY_PREFIX__` = `https://translator-api.zanderwang.com`；可被 env `AITRANSLATOR_CLOUD_PROXY_PREFIX` 覆盖。
- `web/public/_redirects` — `/* /index.html 200`，SPA fallback。
- `web/.nvmrc` — `20`，Cloudflare Pages 自动读取。
- `web/README.md` — 增补 "Deploy to Cloudflare Pages" 小节。

## 你（接手 AI）需要做的事

### 1. 准备：先把代码 push 到 GitHub

```bash
cd /Users/zander/Work/AITranslator
git status   # 确认这些文件存在：web/vite.config.ts、web/public/_redirects、web/.nvmrc、web/README.md
git add web/vite.config.ts web/public/_redirects web/.nvmrc web/README.md web/todo/
git commit -m "[Added] Deploy web to Cloudflare Pages"
git push
```

### 2. 在 Cloudflare Dashboard 创建 Pages 项目

1. 打开 https://dash.cloudflare.com → **Workers & Pages** → **Create** → **Pages** → **Connect to Git**。
2. 授权 GitHub（如未授权），选择仓库 `zanderwang/AITranslator`（或用户实际的仓库名，先跑 `git remote -v` 确认）。
3. 项目名：`tlingo-web`（这是 Pages 内部名，会生成 `tlingo-web.pages.dev` 的预览域）。
4. Production branch：`main`。
5. **Build settings**（关键）：
   - Framework preset：`None`（或 Vite，但 None 更可控）
   - **Root directory (Advanced)**：`web`  ⚠️ 必填，否则会在仓库根找 package.json 失败
   - Build command：`npm install && npm run build`
   - Build output directory：`dist`
6. **Environment variables**（同时给 Production 与 Preview 各加一份；从仓库根 `.env` 复制值）：

   | Name | 值的来源 |
   |---|---|
   | `NODE_VERSION` | `20`（兜底，即使 `.nvmrc` 已存在也建议显式设） |
   | `VITE_SUPABASE_URL` | `.env` 中 `VITE_SUPABASE_URL` 的值，即 `https://xzhkzhwnnwgnobrrnmak.supabase.co` |
   | `VITE_SUPABASE_ANON_KEY` | `.env` 中 `VITE_SUPABASE_ANON_KEY` 的值（`sb_publishable_…` 开头） |
   | `AITRANSLATOR_CLOUD_SECRET` | `.env` 中同名字段（HMAC 密钥） |
   | `AITRANSLATOR_CLOUD_ENDPOINT` | `.env` 中同名字段（如有；可不设，默认 `https://aitranslator-japaneast.azurewebsites.net/api`） |

   ⚠️ `AITRANSLATOR_CLOUD_SECRET` 会被嵌入 JS bundle，对外可见。这是有意的临时方案；不要把它当 "Encrypted Secret"，只是当普通环境变量也行，结果一样。

7. **Save and Deploy**。等首次构建完成（约 1–2 分钟）。如果构建失败：
   - 看 build log。常见错误：Node 版本不对（确认 `.nvmrc` 在 root directory `web/` 下、`NODE_VERSION=20` 已加）。
   - `tsc` 报错：先在本地 `cd web && npx tsc --noEmit` 确认干净，再 push。

### 3. 绑定自定义域 `tlingo.zanderwang.com`

1. Pages 项目 → **Custom domains** → **Set up a custom domain** → 输入 `tlingo.zanderwang.com`。
2. 因为 `zanderwang.com` 在同账号 Cloudflare（确认：`Workers/wrangler.toml` 已经在用 `zone_name = "zanderwang.com"`），Cloudflare 会自动新增 CNAME 记录指向 `tlingo-web.pages.dev`，状态从 Pending → Active 通常 < 1 分钟。
3. 验证：
   ```bash
   curl -sI https://tlingo.zanderwang.com | head -5
   # 期望 HTTP/2 200，cf-cache-status 等 CF 头
   curl -s https://tlingo.zanderwang.com | grep -o '<title>[^<]*'
   # 期望出现 TLingo 的 title
   ```

### 4. 同步 Supabase Auth 设置

1. https://supabase.com/dashboard/project/xzhkzhwnnwgnobrrnmak/auth/url-configuration
   → **Redirect URLs** 添加 `https://tlingo.zanderwang.com/auth/callback`
   → Save
2. Google OAuth Console（如果该 Provider 已在用）→ 你之前创建的 Web OAuth client → **Authorized JavaScript origins** 加 `https://tlingo.zanderwang.com` → Save。
3. GitHub OAuth App **不需要**改（callback 仍走 Supabase 自己的 `/auth/v1/callback`）。

### 5. 端到端烟测

打开 https://tlingo.zanderwang.com：

1. 顶栏出现 "Sign in" 按钮。
2. 点 Sign in → Continue with GitHub → 完成 OAuth → 回到 `https://tlingo.zanderwang.com/auth/callback?code=...` → 自动跳回 `/` → 顶部显示首字母头像。
3. 输入文本 → Translate → 流式输出。Network 面板：
   - 请求 URL: `https://translator-api.zanderwang.com/<model>/chat/completions`
   - 响应 200，Content-Type 含 `text/event-stream`
   - 没有 CORS 报错
4. 点头像 → History → 看到刚刚的翻译。
5. Sign out → 顶部恢复 "Sign in" → 再点 Translate → 弹登录窗（AUTH_REQUIRED 门禁）。
6. 用 Google 账号也试一次。

如果第 3 步挂在 `/auth/callback`：检查 Supabase Redirect URL 是否真的存了这条；同时打开浏览器控制台看 supabase-js 是否报错（最常见是 env 没配上去——回到 Pages 项目 → Settings → Environment variables 双查）。

### 6. 收尾

- 把 `web/todo/cloudflare-deploy.md` 移到 `web/todo/done/` 或删除。
- 留下 `web/todo/cloudflare-deploy-followup.md`（HMAC secret → Worker JWT 验证迁移），改天再做。
- 如果你改动了任何文件（比如发现 README/`.nvmrc` 需要调），同步 commit & push。
- 报告给用户：生产 URL、首次部署 deployment ID（在 Pages 项目里能看到）、每次 push 后会自动构建。
