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

# 2. Configure Secrets
make setup
# Edit .env file with your API credentials, then:
make secrets

# 3. Configure Xcode (one-time setup)
# See "Xcode Configuration" section below

# 4. Build
open AITranslator.xcodeproj
# Or: make build
```

> For Cloudflare Worker deployment, see [Workers/README.md](Workers/README.md)

---

## Configuration

### Environment Variables

The app uses environment variables for configuration, supporting three build environments:

| Environment | Use Case | How to Configure |
|-------------|----------|------------------|
| **App Store** | Xcode Cloud builds | Set environment variables in App Store Connect |
| **Development** | Your local machine | Use `.env` file + `make secrets` |
| **Contributor** | Other developers | Use `.env` file or run with defaults |

### Required Variables

| Variable | Description |
|----------|-------------|
| `AITRANSLATOR_CLOUD_SECRET` | HMAC signing secret for cloud API authentication |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AITRANSLATOR_CLOUD_TOKEN` | Authentication token for cloud API | (empty) |
| `AITRANSLATOR_CLOUD_ENDPOINT` | Cloud service endpoint URL | `https://translator-api.zanderwang.com` |
| `AITRANSLATOR_BUILD_ENVIRONMENT` | Build environment type | `contributor` |

### Local Development Setup

```bash
# 1. Copy the example environment file
cp .env.example .env

# 2. Edit .env with your credentials
nano .env

# 3. Generate Secrets.xcconfig
make secrets

# 4. Build the app
make build
```

### Xcode Cloud Setup

1. Go to **App Store Connect** > **Xcode Cloud** > **Workflows**
2. Edit your workflow and go to **Environment** tab
3. Add environment variables:
   - `AITRANSLATOR_CLOUD_SECRET` (mark as **Secret**)
   - `AITRANSLATOR_CLOUD_TOKEN` (optional, mark as **Secret**)
4. The `ci_scripts/ci_post_clone.sh` script will automatically inject these into the build

### Xcode Project Configuration (One-Time Setup)

To enable xcconfig-based configuration, you need to configure Xcode to use the configuration files:

1. Open `AITranslator.xcodeproj` in Xcode
2. Select the **project** (not a target) in the navigator
3. Go to the **Info** tab
4. Under **Configurations**, expand **Debug** and **Release**
5. For each target, set the configuration file:
   - Debug: `Configuration/Debug.xcconfig`
   - Release: `Configuration/Release.xcconfig`

Alternatively, you can set the configurations at the project level, and they will apply to all targets.

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
├── Configuration/             # Xcode build configuration
│   ├── Base.xcconfig          # Base settings (shared)
│   ├── Debug.xcconfig         # Debug build settings
│   ├── Release.xcconfig       # Release build settings
│   └── Secrets.xcconfig       # Generated secrets (git-ignored)
├── Scripts/                   # Development scripts
│   └── inject-secrets.sh      # Secrets injection script
├── ci_scripts/                # Xcode Cloud CI scripts
│   └── ci_post_clone.sh       # Post-clone hook for CI
├── Makefile                   # Development commands
├── .env.example               # Environment template
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

### Make Commands

```bash
make help           # Show all available commands
make setup          # First-time setup for new developers
make secrets        # Inject secrets from .env into xcconfig
make secrets-check  # Verify secrets are configured
make build          # Build for iOS Simulator
make clean          # Clean build products
```

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

### 3. Setup Development Environment

```bash
make setup
# Edit .env with your credentials (or leave empty to use defaults)
make secrets
```

### 4. Make Changes

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

- Secrets are loaded from environment variables or `.env` file, **never stored in code**
- `Secrets.xcconfig` is auto-generated and git-ignored
- Pre-commit hook automatically detects accidentally committed secrets
- `.gitignore` is configured to exclude sensitive files (`.env`, `Secrets.plist`, `Secrets.xcconfig`)

如果发现安全问题，请通过 Issue 私密报告或发送邮件。

---

## License

MIT License - 详见 [LICENSE](LICENSE) 文件

---

## Acknowledgments

- [Azure OpenAI Service](https://azure.microsoft.com/en-us/products/cognitive-services/openai-service/)
- [Cloudflare Workers](https://workers.cloudflare.com/)
- [SwiftUI](https://developer.apple.com/xcode/swiftui/)
