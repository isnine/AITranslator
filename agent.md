# TLingo

> **AI Agent 开发指南**：本文档专为 AI Agent 理解项目结构和代码逻辑而编写。修改代码前请先阅读相关章节。

## 快速定位

| 需求                        | 关键文件                                                                   |
| --------------------------- | -------------------------------------------------------------------------- |
| 添加/修改动作               | `ShareCore/Configuration/ActionConfig.swift`, `DefaultConfiguration.json`  |
| 添加/修改提供商             | `ShareCore/Configuration/ProviderConfig.swift`, `ProviderCategory.swift`   |
| 修改 LLM 请求逻辑           | `ShareCore/Networking/LLMService.swift`                                    |
| 修改 UI 状态管理            | `ShareCore/UI/HomeViewModel.swift`                                         |
| 修改配置持久化              | `ShareCore/Configuration/AppConfigurationStore.swift`                      |
| 修改扩展行为                | `TranslationUI/TranslationProvider.swift`                                  |
| 修改输出类型/结构化输出模板 | `ShareCore/Configuration/OutputType.swift`                                 |
| 修改偏好设置                | `ShareCore/Preferences/AppPreferences.swift`, `TargetLanguageOption.swift` |
| **修改结果卡片/Cell UI**    | ⚠️ 需同时修改 3 个文件，见下方「结果卡片共享组件」章节                     |

## Overview

TLingo 是一款面向 iOS 18+ / macOS 的 SwiftUI 应用，配套一个 `TranslationUIProviderExtension` 扩展，用于在系统翻译面板中直接调用自定义的 LLM 动作。

**核心能力**：

- 多提供商并发请求（TaskGroup）
- SSE 流式响应 + 结构化输出（JSON Schema）
- 基于 LCS 的 diff 对比展示
- TTS 语音朗读
- App Group 跨进程配置共享

## 项目结构

```
AITranslator/
├── AITranslator/                    # 主应用入口
│   ├── AITranslatorApp.swift        # App 入口点
│   ├── Info.plist / Entitlements
│   └── UI/                          # 主应用界面
│       ├── RootTabView.swift        # 主导航（Home/Actions/Providers/Settings）
│       ├── ActionsView.swift        # 动作库管理界面
│       ├── ActionDetailView.swift   # 动作详情编辑
│       ├── ProvidersView.swift      # 提供商配置界面
│       ├── SettingsView.swift       # 设置界面（目标语言/TTS配置）
│       └── PlaceholderTab.swift     # 占位视图
├── ShareCore/                       # ⚠️ 跨模块共享逻辑（主应用+扩展共用）
│   ├── Configuration/
│   │   ├── ActionConfig.swift       # 动作配置模型
│   │   ├── ProviderConfig.swift     # 提供商配置模型
│   │   ├── ProviderCategory.swift   # 提供商类别枚举（4种）
│   │   ├── OutputType.swift         # 输出类型枚举（plain/diff/sentencePairs/grammarCheck）
│   │   ├── AppConfiguration.swift   # JSON 配置文件的 Codable 模型
│   │   ├── AppConfigurationStore.swift # 单例配置仓库（双向同步）
│   │   ├── ConfigurationFileManager.swift # 配置文件管理（文件监控）
│   │   ├── ConfigurationValidator.swift  # 配置验证器
│   │   ├── ConfigurationService.swift    # 配置导入/导出服务
│   │   └── TTSConfiguration.swift   # TTS 配置模型
│   ├── Networking/
│   │   ├── LLMService.swift         # LLM 请求服务（流式/结构化输出）
│   │   ├── LLMRequestPayload.swift  # 请求负载模型
│   │   ├── LLMServiceError.swift    # 错误类型定义
│   │   ├── ProviderExecutionResult.swift # 执行结果模型
│   │   └── TextToSpeechService.swift # TTS 语音合成服务
│   ├── Preferences/
│   │   ├── AppPreferences.swift     # 应用偏好设置（App Group 共享）
│   │   └── TargetLanguageOption.swift # 目标语言选项枚举
│   ├── UI/
│   │   ├── HomeView.swift           # 主界面（macOS/iOS/扩展共用）
│   │   └── HomeViewModel.swift      # 主界面状态管理
│   ├── Utilities/
│   │   └── TextDiffBuilder.swift    # 文本差异对比（LCS算法）
│   └── AppColors.swift              # 自适应配色表
├── TranslationUI/                   # 系统翻译扩展
│   ├── TranslationProvider.swift    # TranslationUIProviderExtension 入口
│   └── Info.plist / Entitlements
└── Workers/
    └── azureProxyWorker.ts          # Cloudflare Worker 代理（可选）
```

## 核心数据模型

### ActionConfig（动作配置）

```swift
// ShareCore/Configuration/ActionConfig.swift
public struct ActionConfig: Identifiable, Hashable, Codable {
  public let id: UUID           // 内存唯一标识
  public var name: String       // 动作名称（用于 UI 显示）
  public var prompt: String     // 发送给 LLM 的提示词
  public var usageScenes: UsageScene  // 可见场景（app/contextRead/contextEdit）
  public var outputType: OutputType   // 输出类型（决定 UI 展示方式）

  // 计算属性（由 outputType 派生）
  public var showsDiff: Bool          // 是否显示 diff 对比
  public var structuredOutput: StructuredOutputConfig?  // 结构化输出配置
  public var displayMode: DisplayMode // 显示模式（standard/sentencePairs）
}
```

**Prompt 占位符**（在 LLMService 中替换）：

- `{text}` / `{{text}}` → 用户输入文本
- `{targetLanguage}` / `{{targetLanguage}}` → 用户配置的目标语言

### OutputType（输出类型）

```swift
// ShareCore/Configuration/OutputType.swift
public enum OutputType: String, Codable {
  case plain          // 纯文本输出
  case diff           // Diff 对比显示（删除线 + 高亮）
  case sentencePairs  // 逐句翻译（原文+译文交替）
  case grammarCheck   // 语法检查（修订文本 + 错误分析）

  // 内置 JSON Schema 模板
  public var structuredOutput: ActionConfig.StructuredOutputConfig? {
    switch self {
    case .sentencePairs: return .sentencePairs  // primaryField: "sentence_pairs"
    case .grammarCheck:  return .grammarCheck   // primaryField: "revised_text"
    case .plain, .diff:  return nil
    }
  }
}
```

### ProviderConfig（提供商配置）

```swift
// ShareCore/Configuration/ProviderConfig.swift
public struct ProviderConfig: Identifiable, Hashable, Codable {
  public let id: UUID
  public var displayName: String      // 显示名称
  public var baseEndpoint: URL        // 基础端点 URL
  public var apiVersion: String       // API 版本（如 2025-01-01-preview）
  public var token: String            // API Token
  public var authHeaderName: String   // 认证头名称（如 api-key, Authorization）
  public var category: ProviderCategory  // 提供商类别
  public var deployments: [String]       // 所有可用模型部署
  public var enabledDeployments: Set<String>  // 已启用的模型部署

  // 计算 API URL
  public func apiURL(for deployment: String) -> URL
}
```

### ProviderCategory（提供商类别）

```swift
// ShareCore/Configuration/ProviderCategory.swift
public enum ProviderCategory: String, Codable {
  case builtInCloud = "Built-in Cloud"  // 内置云服务（无需配置）
  case azureOpenAI = "Azure OpenAI"     // Azure OpenAI 部署
  case custom = "Custom"                 // 自定义 OpenAI 兼容 API
  case local = "Local"                   // 本地模型（Apple Foundation）

  public var usesBuiltInProxy: Bool     // 是否使用内置 CloudFlare 代理
  public var requiresEndpointConfig: Bool  // 是否需要端点配置
}
```

## 核心功能

### 1. 默认动作

| 动作               | outputType    | 特性                                               |
| ------------------ | ------------- | -------------------------------------------------- |
| Translate          | plain         | 动态 Prompt（`{{targetLanguage}}`）                |
| Sentence Translate | sentencePairs | 逐句翻译，结构化输出                               |
| Grammar Check      | grammarCheck  | 结构化输出（revised_text + additional_text）+ diff |
| Polish             | diff          | 原语言润色，显示删除线对比                         |
| Sentence Analysis  | plain         | 语法解析，动态 Prompt                              |

### 2. 动作可见性控制（UsageScene）

```swift
public struct UsageScene: OptionSet {
  static let app = UsageScene(rawValue: 1 << 0)         // 主应用可见
  static let contextRead = UsageScene(rawValue: 1 << 1) // 扩展只读模式可见
  static let contextEdit = UsageScene(rawValue: 1 << 2) // 扩展可编辑模式可见
  static let all: UsageScene = [.app, .contextRead, .contextEdit]
}
```

### 3. 流式与结构化响应

**流式响应（SSE）**：

- 通过 `URLSession.bytes(for:)` 实时解析 `data:` 事件
- 支持增量解析结构化 JSON（`StreamingSentencePairParser`、`StreamingStructuredOutputParser`）

**结构化输出**：

- 仅 `azureOpenAI` 和 `builtInCloud` 类别支持
- 通过 `response_format: json_schema` 请求参数启用
- 内置模板：`sentencePairs`（逐句翻译）、`grammarCheck`（语法检查）

### 4. 默认提供商

```swift
// Built-in Cloud 提供商（无需配置）
ProviderConfig.builtInCloudProvider(enabledModels: ["model-router"])

// 内置常量
static let builtInCloudEndpoint = URL(string: "https://translator-api.zanderwang.com")!
static let builtInCloudAvailableModels = ["model-router", "gpt-4.1-nano"]
static let builtInCloudSecret = "..." // HMAC 签名密钥
```

## 核心组件详解

### AppConfigurationStore（配置仓库）

**位置**：`ShareCore/Configuration/AppConfigurationStore.swift`

**职责**：单例，管理动作与提供商配置的内存状态和持久化。

**关键属性**：

```swift
@MainActor
public final class AppConfigurationStore: ObservableObject {
  public static let shared = AppConfigurationStore()

  @Published public private(set) var actions: [ActionConfig]
  @Published public private(set) var providers: [ProviderConfig]
  @Published public private(set) var configurationMode: ConfigurationMode
  // .defaultConfiguration（只读）或 .customConfiguration(name:)（可编辑）
}
```

**配置模式**：

- **Default Mode**（只读）：从 Bundle 加载 `DefaultConfiguration.json`，不可修改
- **Custom Mode**（可编辑）：从 App Group 容器加载用户配置文件

**关键方法**：

```swift
// 更新动作（默认模式下触发创建自定义配置的请求）
func updateActions(_ actions: [ActionConfig]) -> ConfigurationValidationResult?

// 更新提供商
func updateProviders(_ providers: [ProviderConfig]) -> ConfigurationValidationResult?

// 从默认配置创建自定义配置
func createCustomConfigurationFromDefault(named: String) -> Bool

// 切换回默认配置
func switchToDefaultConfiguration()

// 重新加载当前配置（从磁盘）
func reloadCurrentConfiguration()
```

**目标语言自动更新**：

- 订阅 `preferences.$targetLanguage`
- 自动更新受管理动作（Translate/Summarize/SentenceAnalysis）的 Prompt
- 通过 `ManagedActionTemplate` 枚举匹配和更新

### HomeViewModel（主界面状态）

**位置**：`ShareCore/UI/HomeViewModel.swift`

**职责**：管理翻译界面的所有状态，包括输入、动作选择、提供商执行结果。

**关键状态**：

```swift
@MainActor
public final class HomeViewModel: ObservableObject {
  @Published public var inputText: String = ""
  @Published public private(set) var actions: [ActionConfig]      // 当前场景可用动作
  @Published public var selectedActionID: UUID?
  @Published public private(set) var providerRuns: [ProviderRunViewState] = []  // 执行结果
  @Published public private(set) var speakingProviders: Set<String> = []
}
```

**ProviderRunViewState.Status**（执行状态）：

```swift
enum Status {
  case idle
  case running(start: Date)
  case streaming(text: String, start: Date)
  case streamingSentencePairs(pairs: [SentencePair], start: Date)
  case success(text:, copyText:, duration:, diff:, supplementalTexts:, sentencePairs:)
  case failure(message:, duration:)
}
```

**执行流程**：

```swift
performSelectedAction()
  └─> cancelActiveRequest(clearResults: false)
  └─> getAllEnabledDeployments()  // 获取所有启用的提供商+部署
  └─> providerRuns = [...running states...]
  └─> llmService.perform(text:, action:, providerDeployments:, partialHandler:, completionHandler:)
```

### LLMService（LLM 请求服务）

**位置**：`ShareCore/Networking/LLMService.swift`

**职责**：发送 LLM 请求，处理流式/非流式响应，解析结构化输出。

**关键方法**：

```swift
public func perform(
  text: String,
  with action: ActionConfig,
  providerDeployments: [(provider: ProviderConfig, deployment: String)],
  partialHandler: (@MainActor @Sendable (UUID, String, StreamingUpdate) -> Void)?,
  completionHandler: (@MainActor @Sendable (ProviderExecutionResult) -> Void)?
) async -> [ProviderExecutionResult]
```

**请求构建逻辑**：

1. 替换 Prompt 占位符（`{text}`, `{targetLanguage}`）
2. 判断 Prompt 是否包含 `{text}` 占位符：
   - 包含：单条 user 消息
   - 不包含：system 消息（prompt）+ user 消息（text）
3. 结构化输出：添加 `response_format: json_schema`
4. 流式请求：设置 `stream: true`，解析 SSE 事件

**Built-in Cloud 认证**：

```swift
// HMAC-SHA256 签名
let message = "\(timestamp):\(path)"
let signature = HMAC<SHA256>.authenticationCode(for: message, using: key)
request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
request.setValue(signature, forHTTPHeaderField: "X-Signature")
```

### TranslationProviderExtension（系统翻译扩展）

**位置**：`TranslationUI/TranslationProvider.swift`

**职责**：作为 iOS/macOS 系统翻译扩展入口点。

```swift
@main
final class TranslationProviderExtension: TranslationUIProviderExtension {
  required init() {
    // 1. 加载 App Group 偏好设置
    UserDefaults.standard.addSuite(named: AppPreferences.appGroupSuiteName)
    AppPreferences.shared.refreshFromDefaults()
    // 2. 强制重新加载配置（扩展可能在主应用修改配置后启动）
    AppConfigurationStore.shared.reloadCurrentConfiguration()
  }

  var body: some TranslationUIProviderExtensionScene {
    TranslationUIProviderSelectedTextScene { context in
      ExtensionCompactView(context: context)
    }
  }
}
```

## 配置系统架构

### 分层架构

```
┌─────────────────────────────────────────────────────────────────────┐
│  UI 层                                                              │
│  ActionsView / ProvidersView / SettingsView                         │
│  └── @ObservedObject store = AppConfigurationStore.shared           │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ @Published bindings
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  配置仓库层                                                          │
│  AppConfigurationStore (单例, @MainActor)                            │
│  ├── actions: [ActionConfig]      // 内存模型（UUID 标识）          │
│  ├── providers: [ProviderConfig]  // 内存模型（UUID 标识）          │
│  ├── configurationMode: ConfigurationMode                          │
│  └── updateActions() / updateProviders() → 自动 saveConfiguration() │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ AppConfiguration (Codable 中间模型)
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  文件管理层                                                          │
│  ConfigurationFileManager                                           │
│  ├── loadConfiguration(named:) / saveConfiguration(_:name:)        │
│  ├── fileChangePublisher: AnyPublisher<ConfigurationFileChangeEvent>│
│  └── startMonitoring() / stopMonitoring() // DispatchSource        │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ JSON 文件
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  持久化层                                                            │
│  App Group Container/Configurations/                                │
│  ├── Default.json (首次启动从 Bundle 复制)                          │
│  └── MyConfig.json (用户自定义)                                     │
│  UserDefaults (App Group)                                           │
│  ├── current_config_name, target_language, tts_*                    │
└─────────────────────────────────────────────────────────────────────┘
```

### 配置文件格式（v1.1.0）

```json
// DefaultConfiguration.json
{
  "version": "1.1.0",
  "preferences": {
    "targetLanguage": "app-language"
  },
  "providers": {
    "Built-in Cloud": {
      "category": "Built-in Cloud",
      "enabledDeployments": ["model-router"]
    }
  },
  "tts": {
    "useBuiltInCloud": true,
    "voice": "alloy"
  },
  "actions": [
    {
      "name": "Translate",
      "prompt": "Translate the selected text into {{targetLanguage}}...",
      "outputType": "plain"
    }
  ]
}
```

### 名称 ↔ UUID 映射

配置文件使用 **名称** 标识 Provider，内存模型使用 **UUID**：

**加载时**（名称 → UUID）：

```swift
var providerNameToID: [String: UUID] = [:]
for (name, entry) in config.providers {
  let provider = entry.toProviderConfig(name: name)  // 生成新 UUID
  providerNameToID[name] = provider.id
}
```

**保存时**（UUID → 名称）：

```swift
var providerIDToName: [UUID: String] = [:]
for provider in providers {
  let (name, entry) = ProviderEntry.from(provider)
  providerIDToName[provider.id] = name
}
```

### 双向同步机制

**UI → 文件**：

```swift
store.updateActions(newActions)
  └─> applyTargetLanguage()  // 更新受管理动作的 Prompt
  └─> self.actions = adjusted
  └─> saveConfiguration()    // 自动保存
```

**文件 → UI**：

```swift
ConfigurationFileManager.fileChangePublisher
  .debounce(for: 0.5s)
  .sink { event in
    if event.timestamp - lastSaveTimestamp > 0.5 {
      store.reloadCurrentConfiguration()  // 非自身触发的变更
    }
  }
```

## 常见开发任务

### 添加新动作

1. **编辑 DefaultConfiguration.json**（仅新用户可见）：

```json
{
  "name": "My Action",
  "prompt": "Your prompt with {{targetLanguage}} placeholder...",
  "outputType": "plain" // plain/diff/sentencePairs/grammarCheck
}
```

2. **如需新的输出类型**，编辑 `OutputType.swift`：

```swift
public enum OutputType: String, Codable {
  case myNewType = "myNewType"

  public var structuredOutput: ActionConfig.StructuredOutputConfig? {
    switch self {
    case .myNewType: return .myNewSchema  // 定义 JSON Schema
    }
  }
}
```

3. **如需受管理的动态 Prompt**，编辑 `AppConfigurationStore.swift` 中的 `ManagedActionTemplate`。

### 添加新提供商类别

1. **编辑 ProviderCategory.swift**：

```swift
public enum ProviderCategory: String, Codable {
  case myProvider = "My Provider"

  public var usesBuiltInProxy: Bool { ... }
  public var requiresEndpointConfig: Bool { ... }
}
```

2. **编辑 LLMService.swift**，在 `sendRequest()` 中处理新类别的认证逻辑。

3. **编辑 ProviderConfig.swift**，添加该类别的特定常量（如果需要）。

### 修改请求/响应处理

**请求构建**：`LLMService.sendRequest()`

- Prompt 占位符替换
- 消息构建（system + user 或单 user）
- 认证头设置

**流式响应解析**：`LLMService.handleStreamingRequest()`

- SSE 事件解析
- 增量结构化输出解析（`StreamingSentencePairParser`、`StreamingStructuredOutputParser`）

**非流式响应解析**：`LLMService.parseResponsePayload()`

### 修改 UI 状态

**HomeViewModel** 是主要的状态管理类：

- `inputText` - 输入文本
- `selectedActionID` - 当前选中动作
- `providerRuns` - 执行结果列表
- `performSelectedAction()` - 触发执行

## 默认配置

| 动作               | 功能描述                       | outputType    |
| ------------------ | ------------------------------ | ------------- |
| Translate          | 翻译到目标语言，同语言时转英语 | plain         |
| Sentence Translate | 逐句翻译                       | sentencePairs |
| Grammar Check      | 润色 + 错误分析                | grammarCheck  |
| Polish             | 原语言润色                     | diff          |
| Sentence Analysis  | 语法解析与搭配积累             | plain         |

默认提供商：

- Built-in Cloud（内置云服务，无需配置）
- 启用模型：`model-router`

## 扩展执行流程

```
┌─────────────────────────────────────────────────────────────────────┐
│  1. 扩展启动                                                        │
│     TranslationProviderExtension.init()                             │
│     ├─ UserDefaults.addSuite(appGroupSuiteName)                     │
│     ├─ AppPreferences.shared.refreshFromDefaults()                  │
│     └─ AppConfigurationStore.shared.reloadCurrentConfiguration()    │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  2. 接收翻译上下文                                                   │
│     TranslationUIProviderSelectedTextScene { context in ... }       │
│     └─ context.selectedText → 填充 inputText                        │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  3. 执行翻译                                                        │
│     HomeViewModel.performSelectedAction()                           │
│     ├─ getAllEnabledDeployments() → [(provider, deployment)]        │
│     ├─ providerRuns = [.running(...)]                              │
│     └─ LLMService.perform(...)                                     │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  4. 流式更新 UI                                                      │
│     partialHandler: → .streaming(text) / .streamingSentencePairs    │
│     completionHandler: → .success(...) / .failure(...)              │
└─────────────────────────────────────────────────────────────────────┘
```

## 代码风格

遵循 [Swift Style Guide.md](Swift%20Style%20Guide.md)：

- 一个文件一个顶层类型
- 私有辅助类型使用嵌套声明（如 `SettingsView.LanguagePickerView`）
- 2 空格缩进，最大行宽 100 字符
- trailing comma 规则
- 多行条件语句在关键字后换行

## 关键常量

```swift
// App Group
AppPreferences.appGroupSuiteName = "group.com.zanderwang.AITranslator"

// Built-in Cloud
ProviderConfig.builtInCloudEndpoint = "https://translator-api.zanderwang.com"
ProviderConfig.builtInCloudAvailableModels = ["model-router", "gpt-4.1-nano"]
ProviderConfig.builtInCloudSecret = "REDACTED_HMAC_SECRET"

// 配置版本
AppConfigurationStore.minimumVersion = "1.1.0"
```

## 后续演进建议

1. **Keychain 敏感信息存储**：将 API Token 从 UserDefaults 迁移到 Keychain
2. **提供商配置 UI**：完善提供商新增/编辑界面
3. **动作编辑 UI**：完善动作创建/编辑流程
4. **测试覆盖**：补充 URLProtocol Mock 单元测试、UI 测试
5. **本地化**：完善多语言支持
6. **日志系统**：加入 os_log 可观测性与调试日志
7. **iCloud 同步**：跨设备配置同步

## 参考资料

- Apple: [Preparing your app to be the default translation app](https://developer.apple.com/documentation/TranslationUIProvider/Preparing-your-app-to-be-the-default-translation-app)
- Apple TranslationUIProvider / ExtensionKit 文档与 WWDC24 相关 Session

## XcodeBuildMCP 自动化开发

本项目支持通过 [XcodeBuildMCP](https://github.com/nicepkg/xcodebuild-mcp) 实现 AI Agent 自动化开发。

### 快速开始

```bash
# 1. 设置会话默认值
mcp_xcodebuildmcp_session-set-defaults {
  "projectPath": "/Users/zander/Work/AITranslator/AITranslator.xcodeproj",
  "scheme": "AITranslator",
  "useLatestOS": true
}

# 2. 构建并运行
mcp_xcodebuildmcp_build_run_sim  # iOS 模拟器
mcp_xcodebuildmcp_build_run_macos  # macOS

# 3. UI 自动化
mcp_xcodebuildmcp_describe_ui  # 获取 UI 层次结构（用于点击坐标）
mcp_xcodebuildmcp_tap { "x": 200, "y": 100 }  # 坐标点击
mcp_xcodebuildmcp_type_text { "text": "Hello" }  # 输入文本
```

### 常用工具

| 工具              | 用途                                   |
| ----------------- | -------------------------------------- |
| `build_run_sim`   | 构建并运行到 iOS 模拟器                |
| `build_run_macos` | 构建并运行 macOS 应用                  |
| `describe_ui`     | 获取 UI 层次结构（accessibility info） |
| `tap`             | 点击（坐标或 label）                   |
| `type_text`       | 输入文本                               |
| `gesture`         | 滚动/滑动手势                          |
| `screenshot`      | 截图（注意：静态，无法捕获动画）       |

### 注意事项

- `describe_ui` 返回 accessibility 信息，用于精确定位 UI 元素坐标
- Tab Bar 按钮可能未设置 `accessibilityLabel`，需通过坐标点击
- 建议在点击前先调用 `describe_ui` 获取精确坐标

## 结果卡片共享组件

> ⚠️ **重要**：结果卡片（Provider Result Card）在 **3 个不同界面** 中分别实现，修改时需要同步更新所有文件。

### 界面清单

| 界面                 | 文件路径                                  | 平台        | 场景              |
| -------------------- | ----------------------------------------- | ----------- | ----------------- |
| 主应用 Home          | `ShareCore/UI/HomeView.swift`             | iOS + macOS | 主 Tab 的翻译界面 |
| macOS 快捷翻译       | `AITranslator/MenuBarPopoverView.swift`   | macOS only  | 菜单栏弹出窗口    |
| iOS Translation 扩展 | `ShareCore/UI/ExtensionCompactView.swift` | iOS only    | 系统翻译扩展      |

### 共享组件结构

每个界面都需要实现以下组件：

```
providerResultCard(for:)              # 结果卡片容器
├── content(for:)                     # 内容区域（根据状态渲染）
│   ├── skeletonPlaceholder()         # 加载骨架屏
│   ├── streaming text                # 流式文本
│   ├── sentencePairsView()           # 逐句翻译
│   ├── diffView()                    # Diff 对比（可切换）
│   ├── plain text                    # 纯文本
│   ├── [仅 grammarCheck 模式]
│   │   └── contentActionButtons()    # 操作按钮（分割线上方）
│   ├── Divider                       # 分割线（仅 grammarCheck）
│   └── supplementalTexts             # 补充内容（语法分析等）
└── bottomInfoBar(for:)               # 底部信息栏
    ├── status icon                   # 状态图标
    ├── duration                      # 耗时
    ├── model name                    # 模型名称
    └── [仅纯文本/diff 模式]
        └── actionButtons()           # 操作按钮（底部）
```

> 📍 **按钮位置规则**：
>
> - **有 supplementalTexts**（如 grammarCheck）：按钮在分割线上方，针对主内容操作
> - **无 supplementalTexts**（如 plain/diff/sentencePairs）：按钮在底部状态栏

### 修改 Cell/卡片时的检查清单

修改结果卡片相关 UI 时，务必检查：

- [ ] `HomeView.swift` - 主应用界面
- [ ] `MenuBarPopoverView.swift` - macOS 快捷翻译
- [ ] `ExtensionCompactView.swift` - iOS 系统翻译扩展

### 状态管理

所有界面共享 `HomeViewModel`，关键状态：

```swift
// 每个 ProviderRunViewState 包含：
- status: Status        // 执行状态（idle/running/streaming/success/failure）
- showDiff: Bool        // 是否显示 diff（默认 true，可切换）

// ViewModel 方法：
- toggleDiffDisplay(for:)  // 切换 diff 显示
- hasDiff(for:)            // 检查是否有 diff 数据
- isDiffShown(for:)        // 获取当前 diff 显示状态
```

## UI 结构参考

### Tab Bar 导航

| Tab       | 图标        | 功能         |
| --------- | ----------- | ------------ |
| Home      | house.fill  | 主翻译界面   |
| Actions   | list.bullet | 动作列表管理 |
| Providers | cpu         | 提供商配置   |
| Settings  | gear        | 设置         |

### Home 页面布局

```
┌─────────────────────────────────────────┐
│  [Set as default translation app]       │ ← 提示横幅（可关闭）
├─────────────────────────────────────────┤
│  ┌─────────────────────────────────┐    │
│  │ Type or paste text here...     │    │ ← 可展开输入框
│  └─────────────────────────────────┘    │
│                                         │
│  [Translate] [Sentence..] [Grammar..]   │ ← 动作选择器（水平滚动）
│                                         │
│  ┌─────────────────────────────────┐    │  纯文本/diff 模式：
│  │  响应内容                        │    │  ← 主内容区域
│  │  ─────────────────────────────  │    │
│  │  ✓ 2.3s  [👁] [🔊] [📋]        │    │  ← 底部状态栏 + 按钮
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │  grammarCheck 模式：
│  │  修订内容（diff 高亮）           │    │  ← 主内容
│  │      [👁] [🔊] [📋] [Replace]   │    │  ← 按钮（分割线上方）
│  │  ─────────────────────────────  │    │  ← 分割线
│  │  语法分析补充说明                │    │  ← 补充内容
│  │  ─────────────────────────────  │    │
│  │  ✓ 8.2s · model-router          │    │  ← 底部状态栏（无按钮）
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

### 性能基准

| 操作     | 平均耗时   | 备注               |
| -------- | ---------- | ------------------ |
| 应用启动 | < 1s       | 冷启动到可交互     |
| 简单翻译 | 2.6 - 4.3s | 10 词以内          |
| 语法检查 | 8 - 10s    | 结构化输出，含分析 |
| Tab 切换 | < 0.1s     | 即时响应           |

## 手动测试检查清单

### macOS 快捷翻译界面

- [ ] **文本选中可读性**：在 Quick Translate 弹窗中选中文本，确认选中高亮清晰可见（深色/浅色模式均需测试）
  - 修复记录：使用自定义 `SelectableTextEditor`（基于 NSTextView）替代 SwiftUI TextEditor，设置 `selectedTextAttributes` 使用系统标准选中颜色
