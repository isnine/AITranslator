# AITranslator

## Overview

AITranslator 是一款面向 iOS 18+ 的 SwiftUI 应用，配套一个 `TranslationUIProvider` 扩展，用于在系统翻译面板中直接调用自定义的 LLM 动作。当前代码库聚焦于核心体验：主应用提供动作与模型配置界面，扩展侧在出现时自动执行默认动作，并展示每个 LLM 提供商的结果。

## 项目结构

- `AITranslator/` – 主应用入口，包含 `AITranslatorApp`、顶部 Tab 导航以及占位页面。
- `AITranslator/UI/` – 主界面相关的 SwiftUI 组件，例如 `RootTabView` 与 `PlaceholderTab`。
- `ShareCore/` – 可被 App 和扩展共用的跨模块逻辑：
  - `Configuration/` – `ProviderCategory`、`ActionConfig`、`ProviderConfig` 与 `AppConfigurationStore` 等配置模型。
  - `Networking/` – `LLMService` 及其请求/结果模型，负责并发调用多个 OpenAI 兼容接口。
  - `UI/` – 共享的 `HomeView` 和 `HomeViewModel`，在主应用与扩展中共用。
  - `AppColors.swift` – 支持亮/暗模式的自适应配色表，通过 `AppColorPalette` 暴露统一调色。
- `TranslationUI/` – 系统翻译扩展，`TranslationProviderExtension` 直接呈现 `HomeView(context:)`。
- `AITranslator.xcodeproj` – 启用了“文件夹同步”模式，新增 Swift 文件自动加入对应 Target。

## 最近结构优化

- 遵循 Airbnb Swift Style Guide 的“一个文件一个顶层类型”约定，将 `AppConfigurationStore`、`LLMService` 与 `TextDiffBuilder` 的私有辅助类型下沉为嵌套声明。
- 将 `SettingsView`、`ActionsView`、`ProvidersView` 的辅助视图改为 `private` 嵌套类型，避免顶层类型膨胀并明确可见性。
- 将 `AppColors` 的调色板暴露为嵌套 `AppColors.Palette`（通过 `AppColorPalette` typealias 兼容旧代码），集中管理自适应色值。
- 收敛 `TextDiffBuilder` API：`Segment`、`Presentation` 等类型与配色主题统一收纳在该枚举内部，简化命名空间。

已移除旧的 `TranslationU/` 模板代码，避免重复实现。

## 核心组件

- **AppConfigurationStore**：单例配置仓库，启动时注入一个 Azure OpenAI 默认提供商与四个预置动作（翻译、总结、打磨、语法检查），提供更新接口供未来持久化接入。
- **ActionConfig / ProviderConfig**：精简的可编码模型，分别描述用户动作以及 OpenAI 兼容提供商，便于持久化或同步。
- **LLMService**：基于 `URLSession` 的异步客户端，并行向所有匹配的提供商发送请求，落地统一的 `ProviderExecutionResult` 结构，并提供基础的错误分类。
- **HomeView / HomeViewModel**：共享的 SwiftUI 界面与状态管理，负责输入框折叠/展开、动作切换、并发请求状态以及结果渲染（复制、替换操作）。
- **TranslationProviderExtension**：扩展入口极简化，仅持有 `HomeView(context:)`，确保应用与扩展界面一致。

## 默认配置

| 动作 | Prompt 概要 |
| --- | --- |
| 翻译 | 智能翻译选中文本，保持原意并简洁输出 |
| 总结 | 精简总结选中文本，保留关键信息 |
| 打磨 | 在原语言中润色文本 |
| 语法检查 | 输出润色版本并列出错误说明，按严重度标记 |

默认提供商预设为 Azure OpenAI 的 `model-router` 部署，可根据需要扩展。

## 扩展执行流程

1. 扩展接收 `TranslationUIProviderContext`，自动填充输入框并触发默认动作。
2. `HomeViewModel` 根据所选动作筛选提供商、更新运行状态，并通过 `LLMService` 并发发送请求。
3. 请求完成后更新 UI，支持复制结果或在宿主应用支持时替换原文。
4. 若出现错误，界面会在对应提供商卡片中显示诊断信息。

## 后续演进建议

1. 将配置持久化到 App Group，敏感信息放入 Keychain，供扩展读取。
2. 扩展 `ProviderConfig`，支持更多 HTTP Header、温度参数以及流式响应。
3. 补充单元测试（URLProtocol Mock）、UI 测试以及扩展集成测试。
4. 丰富主应用 Tab 页面：动作管理、提供商配置、运行日志、引导设置。
5. 加入日志与可观测性（可选），并覆盖可访问性/本地化需求。

## 参考资料

- Apple: [Preparing your app to be the default translation app](https://developer.apple.com/documentation/TranslationUIProvider/Preparing-your-app-to-be-the-default-translation-app)
- Apple TranslationUIProvider / ExtensionKit 文档与 WWDC24 相关 Session
