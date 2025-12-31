# AITranslator (Tree² Lang)

## Overview

Tree² Lang 是一款面向 iOS 18+ / macOS 的 SwiftUI 应用，配套一个 `TranslationUIProviderExtension` 扩展，用于在系统翻译面板中直接调用自定义的 LLM 动作。应用支持多提供商并发请求、流式响应、TTS 语音朗读，以及基于 diff 的文本对比展示。

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
├── ShareCore/                       # 跨模块共享逻辑
│   ├── Configuration/
│   │   ├── ActionConfig.swift       # 动作配置模型（支持结构化输出/diff对比）
│   │   ├── ProviderConfig.swift     # 提供商配置模型
│   │   ├── ProviderCategory.swift   # 提供商类别枚举
│   │   ├── AppConfigurationStore.swift # 单例配置仓库
│   │   └── TTSConfiguration.swift   # TTS 配置模型
│   ├── Networking/
│   │   ├── LLMService.swift         # LLM 请求服务（支持流式/结构化输出）
│   │   ├── LLMRequestPayload.swift  # 请求负载模型
│   │   ├── LLMServiceError.swift    # 错误类型定义
│   │   ├── ProviderExecutionResult.swift # 执行结果模型
│   │   └── TextToSpeechService.swift # TTS 语音合成服务
│   ├── Preferences/
│   │   ├── AppPreferences.swift     # 应用偏好设置（App Group 共享）
│   │   └── TargetLanguageOption.swift # 目标语言选项枚举
│   ├── UI/
│   │   ├── HomeView.swift           # 主界面（支持 macOS/iOS/扩展）
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

## 核心功能

### 1. 多动作支持

- **翻译**：智能翻译，自动检测语言并在目标语言与英语之间切换
- **总结**：精简总结，保留关键信息
- **打磨**：原语言润色，提升表达质量
- **语法检查**：结构化输出，分离润色结果与错误分析（使用 JSON Schema）
- **句子分析**：语法解析与搭配积累

### 2. 动作配置模型（ActionConfig）

- `usageScenes`：控制动作在 App/扩展只读/扩展可编辑 场景下的可见性
- `showsDiff`：启用 diff 对比展示（原文删除线 + 新增高亮）
- `structuredOutput`：JSON Schema 结构化输出配置（primaryField + additionalFields）

### 3. 流式与结构化响应

- **流式响应**：通过 SSE 实时显示生成内容
- **结构化输出**：Azure OpenAI 的 `response_format: json_schema` 支持
- **多提供商并发**：同时向多个配置的提供商发送请求

### 4. TTS 语音朗读

- 集成 Azure OpenAI TTS API（gpt-4o-mini-tts）
- 支持自定义端点/API Key 配置
- 可选使用默认配置或自定义配置

### 5. 目标语言设置

- 支持 8 种语言：应用语言/英语/简体中文/日语/韩语/法语/德语/西班牙语
- 动态更新动作 Prompt 模板

### 6. 差异对比（TextDiffBuilder）

- 基于 LCS（最长公共子序列）算法
- 分离原文段落（删除标记）与修订段落（新增高亮）
- 自适应亮/暗模式配色

## 核心组件

### AppConfigurationStore

单例配置仓库，管理动作与提供商配置：

- 启动时注入默认提供商（Azure OpenAI model-router + gpt-5-nano）
- 预置 5 个动作模板
- 响应目标语言变更，自动更新受管理的动作 Prompt

### HomeView / HomeViewModel

共享主界面，同时用于主应用与系统翻译扩展：

- 输入框可折叠/展开
- 动作 Chip 选择器
- 提供商结果卡片（skeleton/streaming/success/failure 状态）
- 支持复制/替换/语音朗读
- 自动粘贴并执行功能

### LLMService

基于 URLSession 的异步网络客户端：

- 并发 TaskGroup 执行多提供商请求
- 支持 SSE 流式响应解析
- 结构化输出 JSON 解析
- 统一的 ProviderExecutionResult 结果封装

### TranslationProviderExtension

系统翻译扩展入口，极简封装：

- 读取 App Group 偏好设置
- 呈现 `HomeView(context:)`
- 支持替换原文（allowsReplacement）

### AppPreferences

应用偏好设置管理：

- 使用 App Group 共享存储
- 管理目标语言、TTS 配置
- 响应 UserDefaults 变更通知

## 配置读写流程

### 配置架构概述

配置系统采用多层架构，实现了 JSON 配置文件与内存模型之间的双向转换：

```
┌─────────────────────────────────────────────────────────────────────┐
│                        持久化层                                      │
├─────────────────────────────────────────────────────────────────────┤
│  App Group Container                                                │
│  └── Configurations/                                                │
│      ├── Default.json          <- 首次启动从 Bundle 复制            │
│      ├── MyConfig.json         <- 用户自定义配置                    │
│      └── ...                                                        │
│                                                                     │
│  UserDefaults (App Group)                                           │
│  ├── current_config_name       <- 当前激活的配置名称                 │
│  ├── target_language           <- 目标语言偏好                      │
│  └── tts_*                     <- TTS 相关设置                      │
└─────────────────────────────────────────────────────────────────────┘
                               ▲
                               │ 读/写
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        文件管理层                                    │
├─────────────────────────────────────────────────────────────────────┤
│  ConfigurationFileManager                                           │
│  ├── listConfigurations()      -> [ConfigurationFileInfo]           │
│  ├── loadConfiguration(named:) -> AppConfiguration                  │
│  ├── saveConfiguration(_:name:)                                     │
│  └── deleteConfiguration(named:)                                    │
└─────────────────────────────────────────────────────────────────────┘
                               ▲
                               │ AppConfiguration (中间模型)
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        配置仓库层                                    │
├─────────────────────────────────────────────────────────────────────┤
│  AppConfigurationStore (单例)                                        │
│  ├── @Published actions: [ActionConfig]                             │
│  ├── @Published providers: [ProviderConfig]                         │
│  ├── updateActions(_:)         -> 更新内存 + 自动保存               │
│  ├── updateProviders(_:)       -> 更新内存 + 自动保存               │
│  └── switchConfiguration(to:)  -> 切换配置文件                      │
└─────────────────────────────────────────────────────────────────────┘
                               ▲
                               │ ObservableObject
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        UI 层                                         │
├─────────────────────────────────────────────────────────────────────┤
│  ActionsView / ProvidersView / SettingsView                         │
│  └── 绑定到 AppConfigurationStore.shared                            │
└─────────────────────────────────────────────────────────────────────┘
```

### 关键数据模型

| 模型                | 职责                                    | 存储位置         |
| ------------------- | --------------------------------------- | ---------------- |
| `AppConfiguration`  | JSON 配置文件的 Codable 中间模型        | .json 文件       |
| `ActionConfig`      | 动作的内存模型（含 UUID）               | 内存             |
| `ProviderConfig`    | 提供商的内存模型（含 UUID）             | 内存             |
| `AppPreferences`    | 偏好设置（目标语言、TTS、当前配置名称） | UserDefaults     |

### 启动时加载流程

```swift
// AppConfigurationStore.init()
1. 调用 loadConfiguration()
   │
   ├─ 2. 从 UserDefaults 读取 currentConfigName
   │
   ├─ 3. 尝试加载指定名称的配置文件
   │     └─ tryLoadConfiguration(named:)
   │         ├─ configFileManager.loadConfiguration(named:)
   │         │   └─ JSON 解码 -> AppConfiguration
   │         └─ applyLoadedConfiguration(_:)
   │             ├─ 解析 providers -> [ProviderConfig]
   │             │   └─ ProviderEntry.toProviderConfig(name:)
   │             ├─ 解析 actions -> [ActionConfig]
   │             │   └─ ActionEntry.toActionConfig(providerMap:)
   │             └─ 应用目标语言到 prompt
   │                 └─ applyTargetLanguage(_:targetLanguage:)
   │
   ├─ 4. 若加载失败，尝试加载其他可用配置
   │     └─ configFileManager.listConfigurations()
   │
   └─ 5. 若无可用配置，创建空配置
         └─ createEmptyConfiguration()
```

**首次启动特殊处理**：
- `ConfigurationFileManager` 初始化时检查 `Default.json` 是否存在
- 若不存在，从 Bundle 中的 `DefaultConfiguration.json` 复制到 App Group 容器

### UI 修改后的保存流程

```swift
// 用户在 UI 修改 Action 或 Provider 后
1. UI 调用 store.updateActions(_:) 或 store.updateProviders(_:)
   │
   ├─ 2. 应用目标语言模板（仅 Actions）
   │     └─ applyTargetLanguage(_:targetLanguage:)
   │
   ├─ 3. 更新内存中的 @Published 属性
   │     └─ self.actions = adjusted / self.providers = providers
   │
   └─ 4. 自动调用 saveConfiguration()
         │
         ├─ 5. buildCurrentConfiguration()
         │     ├─ 构建 providerEntries: [String: ProviderEntry]
         │     │   └─ ProviderEntry.from(provider) -> (name, entry)
         │     ├─ 构建 actionEntries: [ActionEntry]
         │     │   └─ ActionEntry.from(action, providerNames:)
         │     └─ 组装 AppConfiguration
         │
         └─ 6. configFileManager.saveConfiguration(_:name:)
               └─ JSON 编码 -> 写入 .json 文件
```

### 数据转换细节

#### Provider 名称与 UUID 映射

配置文件中 Provider 使用 **名称** 标识，内存模型使用 **UUID**。转换过程：

**加载时**（名称 → UUID）：
```swift
// 在 applyLoadedConfiguration(_:) 中
var providerNameToID: [String: UUID] = [:]
for (name, entry) in config.providers {
    if let provider = entry.toProviderConfig(name: name) {
        providerNameToID[name] = provider.id  // 生成新 UUID
    }
}
// Action 使用此映射解析 providerIDs
action.toActionConfig(providerMap: providerNameToID)
```

**保存时**（UUID → 名称）：
```swift
// 在 buildCurrentConfiguration() 中
var providerIDToName: [UUID: String] = [:]
for provider in providers {
    let (name, entry) = ProviderEntry.from(provider)
    providerIDToName[provider.id] = uniqueName
}
// Action 使用此映射导出 provider 名称列表
ActionEntry.from(action, providerNames: providerIDToName)
```

#### 目标语言动态更新

受管理的动作（Translate/Summarize/Sentence Analysis 等）在以下场景自动更新 Prompt：

1. **加载配置时**：`applyTargetLanguage()` 检测 Prompt 是否匹配模板
2. **用户切换语言时**：通过 Combine 订阅 `preferences.$targetLanguage` 自动触发更新

```swift
preferences.$targetLanguage
    .sink { [weak self] option in
        let updated = applyTargetLanguage(self.actions, targetLanguage: option)
        self.actions = updated
        self.saveConfiguration()
    }
```

### 配置服务 (ConfigurationService)

提供配置的导入/导出功能，用于配置迁移或备份：

| 方法                      | 用途                           |
| ------------------------- | ------------------------------ |
| `exportConfiguration()`   | 导出当前配置为 JSON Data       |
| `importConfiguration()`   | 从 JSON 解析 AppConfiguration  |
| `applyConfiguration()`    | 将配置应用到 Store 和 Preferences |

### 数据一致性保障

1. **自动保存**：每次 `updateActions()` 或 `updateProviders()` 调用后立即持久化
2. **App Group 共享**：主应用与扩展共享同一配置目录
3. **UserDefaults 同步**：调用 `defaults.synchronize()` 确保跨进程可见
4. **Combine 订阅**：偏好变更自动触发配置更新

## 默认配置

| 动作     | 功能描述                       | 特性                         |
| -------- | ------------------------------ | ---------------------------- |
| 翻译     | 翻译到目标语言，同语言时转英语 | 动态 Prompt                  |
| 总结     | 用目标语言总结文本             | 动态 Prompt                  |
| 打磨     | 原语言润色                     | showsDiff                    |
| 语法检查 | 润色 + 错误分析                | showsDiff + structuredOutput |
| 句子分析 | 语法解析与搭配积累             | 动态 Prompt                  |

默认提供商：

- Azure OpenAI `model-router`（自动路由）
- Azure OpenAI `gpt-5-nano`（轻量模型）

## 扩展执行流程

1. 扩展启动时读取 App Group 偏好设置
2. 接收 `TranslationUIProviderContext`，自动填充输入框
3. 自动触发默认动作执行
4. `HomeViewModel` 根据动作配置筛选提供商
5. `LLMService` 并发发送请求，流式/非流式分别处理
6. 实时更新 UI 状态（skeleton → streaming → success/failure）
7. 支持复制/替换/语音朗读操作

## 代码风格

遵循 Airbnb Swift Style Guide：

- 一个文件一个顶层类型
- 私有辅助类型使用嵌套声明（如 `SettingsView.LanguagePickerView`）
- 2 空格缩进，最大行宽 100 字符
- trailing comma 规则
- 多行条件语句在关键字后换行

## 后续演进建议

1. **持久化**：将配置持久化到 App Group，敏感信息放入 Keychain
2. **提供商配置 UI**：实现提供商新增/编辑界面
3. **动作编辑 UI**：完善动作创建/编辑流程
4. **测试覆盖**：补充 URLProtocol Mock 单元测试、UI 测试
5. **本地化**：完善多语言支持
6. **日志系统**：加入可观测性与调试日志
7. **iCloud 同步**：跨设备配置同步

## 参考资料

- Apple: [Preparing your app to be the default translation app](https://developer.apple.com/documentation/TranslationUIProvider/Preparing-your-app-to-be-the-default-translation-app)
- Apple TranslationUIProvider / ExtensionKit 文档与 WWDC24 相关 Session
- [Airbnb Swift Style Guide](https://github.com/airbnb/swift)

## AI Agent 开发工具

### XcodeBuildMCP

本项目支持通过 [XcodeBuildMCP](https://github.com/nicepkg/xcodebuild-mcp) 实现 AI Agent 自动化开发。XcodeBuildMCP 是一个 Model Context Protocol (MCP) 服务器，允许 AI Agent 直接与 Xcode 项目交互。

#### 可用能力

| 能力         | 工具示例                                  | 用途                                     |
| ------------ | ----------------------------------------- | ---------------------------------------- |
| **构建**     | `build_sim`, `build_macos`                | 编译项目到模拟器或 macOS                 |
| **运行**     | `build_run_sim`, `launch_app_sim`         | 构建并运行，或直接启动应用               |
| **截图**     | `screenshot`                              | 捕获模拟器当前屏幕                       |
| **日志**     | `start_sim_log_cap`, `stop_sim_log_cap`   | 启动/停止日志捕获会话                    |
| **UI 描述**  | `describe_ui`                             | 获取完整的视图层次结构（用于自动化测试） |
| **UI 交互**  | `tap`, `type_text`, `swipe`, `long_press` | 模拟用户操作                             |
| **项目管理** | `discover_projs`, `list_schemes`          | 发现项目和 scheme                        |

#### 典型工作流程

```bash
# 1. 设置会话默认值
session-set-defaults {
  "projectPath": "/Users/zander/Work/AITranslator/AITranslator.xcodeproj",
  "scheme": "AITranslator",
  "simulatorId": "<simulator-uuid>",
  "useLatestOS": true
}

# 2. 构建并运行
build_run_sim

# 3. 开启日志捕获
start_sim_log_cap { "bundleId": "com.zanderwang.AITranslator" }
# 返回 sessionId

# 4. 截图查看当前状态
screenshot

# 5. 获取 UI 层次结构（用于精确点击坐标）
describe_ui

# 6. 模拟用户操作
tap { "label": "Send" }           # 通过 accessibility label 点击
tap { "x": 200, "y": 300 }        # 通过坐标点击
type_text { "text": "Hello" }     # 输入文字

# 7. 停止日志捕获并查看
stop_sim_log_cap { "logSessionId": "<session-id>" }
```

#### 使用场景

1. **自动化 UI 测试**：AI Agent 可以自动构建、运行应用并通过截图验证 UI 效果
2. **快速迭代**：修改代码后立即编译验证，无需手动操作 Xcode
3. **问题诊断**：通过日志捕获和 UI 描述快速定位问题
4. **自动化演示**：录制视频或截图用于文档

#### 注意事项

- 截图是静态的，无法捕获动画效果
- 日志捕获需要应用使用 `os_log` 输出结构化日志才能看到内容
- `describe_ui` 返回 accessibility 信息，用于精确定位 UI 元素坐标
- 建议在点击前先调用 `describe_ui` 获取精确坐标，而不是从截图猜测
