# AITranslator

一款基于 Swift/SwiftUI 的 iOS/macOS 翻译应用，集成系统翻译框架，支持多 LLM 服务商（Azure OpenAI、自定义 OpenAI 兼容 API），具备并发请求和流式响应能力。

A Swift/SwiftUI iOS/macOS translation app with system translation integration. Supports multiple LLM providers with concurrent requests and streaming responses.

## Features

- **System Translation Extension** - 系统级翻译扩展，可在任意 App 中划词翻译
- **Multiple LLM Providers** - 支持 Azure OpenAI、自建服务等多种后端
- **Streaming Responses** - SSE 流式响应，翻译结果实时显示
- **Text-to-Speech** - 内置 TTS 朗读功能
- **macOS Menu Bar** - macOS 菜单栏常驻 + 全局快捷键
- **Diff View** - 基于 LCS 算法的翻译差异对比

## Screenshots

<!-- TODO: Add screenshots here -->

## Requirements

- iOS 18.4+ / macOS 15.4+
- Xcode 16+
- Swift 6.0+

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/isnine/AITranslator.git
cd AITranslator
git config core.hooksPath .githooks

# 2. Deploy Worker (需要 Azure OpenAI API Key)
cd Workers
npm install -g wrangler && wrangler login
wrangler secret put APP_SECRET      # openssl rand -hex 32
wrangler secret put AZURE_API_KEY
wrangler secret put AZURE_ENDPOINT
wrangler secret put TTS_ENDPOINT
wrangler deploy
cd ..

# 3. Configure App
cp Secrets.plist.example Secrets.plist
# 编辑 Secrets.plist，填入与 APP_SECRET 相同的值
# 将 Secrets.plist 添加到 Xcode 项目

# 4. Build
open AITranslator.xcodeproj
```

> 详细配置说明见 [Workers/README.md](Workers/README.md)

---

## Project Structure

```
AITranslator/
├── AITranslator/              # 主 App（UI 层，MVVM 架构）
│   ├── Resources/             # 资源文件、默认配置
│   └── UI/                    # SwiftUI 视图
├── ShareCore/                 # 共享 Framework（业务逻辑、网络层）
│   ├── Configuration/         # 配置管理、密钥加载
│   ├── Networking/            # LLM/TTS 服务、SSE 解析
│   └── UI/                    # 共享 UI 组件
├── TranslationUI/             # iOS 系统翻译扩展
├── Workers/                   # Cloudflare Worker 代理
│   ├── azureProxyWorker.ts    # Worker 源码
│   └── wrangler.toml          # Wrangler 配置
├── Secrets.plist.example      # 密钥配置模板
└── .githooks/                 # Git hooks（secret 检测）
```

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   iOS/macOS     │────▶│ Cloudflare Worker│────▶│  Azure OpenAI   │
│   App           │ SSE │  (HMAC Auth)     │     │  API            │
└─────────────────┘     └──────────────────┘     └─────────────────┘
        │
        ▼
┌─────────────────┐
│ Translation     │
│ Extension       │
└─────────────────┘
```

- **HMAC Authentication**: 请求使用 `X-Timestamp` + `X-Signature` 头进行签名验证
- **SSE Streaming**: 流式响应，支持 JSON Schema 结构化输出
- **App Groups**: `group.com.zanderwang.AITranslator` 用于 App 与 Extension 共享数据

---

## Development

### Code Style

```bash
# Format code
swiftformat .

# Lint code  
swiftlint
```

### Pre-commit Hook

项目包含 pre-commit hook 用于检测意外提交的密钥：

```bash
# 新 clone 后需要启用
git config core.hooksPath .githooks
```

### Local Worker Development

```bash
cd Workers
wrangler dev  # 启动本地开发服务器
```

---

## Contributing

欢迎贡献代码！请遵循以下步骤：

### 1. Fork & Clone

```bash
git clone https://github.com/YOUR_USERNAME/AITranslator.git
cd AITranslator
git config core.hooksPath .githooks
```

### 2. Create a Branch

```bash
git checkout -b feature/your-feature-name
```

### 3. Make Changes

- 遵循现有代码风格
- 添加必要的注释
- 确保不提交任何密钥或敏感信息

### 4. Test

- 在 iOS Simulator 和真机上测试
- 测试 Translation Extension 功能
- 如修改 Worker，在本地用 `wrangler dev` 测试

### 5. Commit

```bash
git add .
git commit -m "[Added/Fixed/Changed] Your commit message"
```

Commit message 格式：
- `[Added]` - 新功能
- `[Fixed]` - Bug 修复
- `[Changed]` - 重构或改进
- `[Developer]` - 开发相关（构建、配置等）

### 6. Push & Create PR

```bash
git push origin feature/your-feature-name
```

然后在 GitHub 上创建 Pull Request。

### Issues & Discussions

- **Bug 报告**: 请使用 Issue 模板，提供复现步骤
- **功能建议**: 欢迎在 Discussions 中讨论

---

## Security

- 密钥通过 `Secrets.plist` 或环境变量加载，**不存储在代码中**
- Pre-commit hook 自动检测意外提交的密钥
- `.gitignore` 已配置排除敏感文件

如果发现安全问题，请通过 Issue 私密报告或发送邮件。

---

## License

MIT License - 详见 [LICENSE](LICENSE) 文件

---

## Acknowledgments

- [Azure OpenAI Service](https://azure.microsoft.com/en-us/products/cognitive-services/openai-service/)
- [Cloudflare Workers](https://workers.cloudflare.com/)
- [SwiftUI](https://developer.apple.com/xcode/swiftui/)
