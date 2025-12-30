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
