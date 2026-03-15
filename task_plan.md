# Task Plan: TLingo iOS/macOS 全功能重写

## Goal
在 `/Users/zander/Work/AITranslator/TLingo/` 目录下，使用全新 Xcode 项目从零重写 TLingo 的全部功能（iOS + macOS + Translation Extension），保持相同技术栈（SwiftUI + Swift + Combine），使用更简洁、可读、合理的代码结构。

## Constraints
- **Bundle ID**: `com.zanderwang.AITranslator`（沿用旧项目）
- **App Group**: `group.com.zanderwang.AITranslator`
- **技术栈**: SwiftUI + Swift 5.0 + Combine, MVVM
- **平台**: iOS 26.0+ / macOS 26.0+
- **后端**: 继续使用现有 Azure Function（Cloudflare Worker 代理）
- **共享框架**: 需要 ShareCore embedded framework（主 App + Translation Extension 共享）
- **Xcode**: 26.4, fileSystemSynchronizedGroups

## Current Phase
Phase 1

## Target Architecture

```
TLingo/                          ← 新 Xcode 项目根目录
├── TLingo.xcodeproj
├── TLingo/                      ← 主 App target
│   ├── App/                     ← App 入口 + AppDelegate
│   ├── Features/                ← 按功能域分组
│   │   ├── Home/                ← 翻译主界面（输入、结果、工具栏）
│   │   ├── Actions/             ← 动作管理（列表、详情编辑）
│   │   ├── Models/              ← 模型选择与管理
│   │   ├── Settings/            ← 设置页面（拆分为子页面）
│   │   ├── Paywall/             ← 订阅购买
│   │   └── Voice/               ← 语音选择
│   ├── macOS/                   ← macOS 专属功能
│   │   ├── MenuBar/             ← 菜单栏图标 + 弹窗
│   │   ├── HotKey/              ← 全局快捷键
│   │   └── Clipboard/           ← 剪贴板监控
│   └── Assets.xcassets
├── ShareCore/                   ← 共享 framework target
│   ├── Configuration/           ← 动作/模型/语音配置 + 持久化 + 迁移
│   ├── Networking/              ← LLM 请求 + 流式解析 + TTS + 模型列表
│   │   └── Debug/               ← 网络调试（仅 Debug build）
│   ├── Preferences/             ← UserDefaults + App Group 偏好
│   ├── StoreKit/                ← 订阅管理
│   ├── UI/                      ← 共享 UI 组件
│   │   ├── Home/                ← HomeView + HomeViewModel（拆分后）
│   │   ├── Conversation/        ← 多轮对话
│   │   ├── Components/          ← 可复用组件（chips, cards, overlays...）
│   │   ├── Extension/           ← Translation Extension UI
│   │   └── Debug/               ← 网络调试 UI
│   ├── Utilities/               ← 工具函数（diff, prompt, logger...）
│   ├── Theme/                   ← 颜色、样式
│   └── Resources/               ← DefaultConfiguration.json
├── TranslationExtension/        ← 系统翻译扩展 target
│   └── TranslationProvider.swift
└── Localizable.xcstrings        ← 本地化
```

## Phases

### Phase 1: 项目基础搭建
- [ ] 配置 Xcode 项目（修正 Bundle ID、App Group、Deployment Target）
- [ ] 创建 ShareCore framework target
- [ ] 创建 TranslationExtension target
- [ ] 搭建目录结构骨架
- [ ] 验证空项目可编译
- **Status:** pending

### Phase 2: ShareCore — 数据模型与配置层
- [ ] Configuration 模块：ActionConfig, ModelConfig, VoiceConfig, OutputType
- [ ] Configuration 持久化：AppConfigurationStore, ConfigurationFileManager
- [ ] Configuration 辅助：ConfigurationValidator, ConfigurationMigrator, ConfigurationService
- [ ] Preferences 模块：AppPreferences, TargetLanguageOption
- [ ] BuildEnvironment / SecretsConfiguration
- [ ] Resources: DefaultConfiguration.json
- [ ] 验证编译
- **Status:** pending

### Phase 3: ShareCore — 网络层
- [ ] LLMService 核心（拆分为更合理的结构）
  - LLMService（协调层）
  - LLMRequestBuilder（请求构建 + payload 组装）
  - StreamingResponseParser（SSE 流式解析）
  - CloudServiceAuth（HMAC 签名）
- [ ] LLMRequestPayload, LLMServiceError, ModelExecutionResult
- [ ] ModelsService（模型列表获取）
- [ ] VoicesService（语音列表获取）
- [ ] TTSPreviewService（TTS 播放）
- [ ] ImageAttachment, NetworkTimingMetrics
- [ ] Debug: NetworkRequestLogger, NetworkRequestRecord, NetworkSession, DebugNetworkProtocol
- [ ] 验证编译
- **Status:** pending

### Phase 4: ShareCore — StoreKit + Utilities + Theme
- [ ] StoreKit: StoreManager, SubscriptionProduct
- [ ] Utilities: TextDiffBuilder, PromptSubstitution, SourceLanguageDetector, Logger, PasteboardHelper, Data+Hex
- [ ] Theme: AppColors (Palette)
- [ ] 验证编译
- **Status:** pending

### Phase 5: ShareCore — 共享 UI 组件
- [ ] Components: ActionChipsView, LanguageSwitcherView, LoadingOverlay, ImageAttachmentPreview
- [ ] ProviderResultCardView（结果卡片 + diff/sentence pairs 展示）
- [ ] LanguagePickerView, DataConsentView
- [ ] 验证编译
- **Status:** pending

### Phase 6: ShareCore — Home UI（翻译主界面）
- [ ] HomeViewModel（拆分后：核心状态 + 翻译执行）
- [ ] HomeView 骨架
- [ ] HomeInputSection（输入框 + 图片附件 + 语言切换）
- [ ] HomeResultsSection（结果卡片列表）
- [ ] HomeToolbar（操作按钮栏）
- [ ] 验证编译
- **Status:** pending

### Phase 7: ShareCore — 对话 + Extension UI + Debug UI
- [ ] Conversation: ChatMessage, ConversationSession, ConversationViewModel, ConversationView, ConversationInputBar, MessageBubbleView
- [ ] Extension: ExtensionCompactView
- [ ] Debug: NetworkDebugView, NetworkRequestDetailView
- [ ] 验证编译
- **Status:** pending

### Phase 8: 主 App — 入口 + 导航 + 核心页面
- [ ] App 入口: TLingoApp（含 macOS AppDelegate）
- [ ] RootTabView（Tab 导航）
- [ ] Home Feature 集成
- [ ] Actions: ActionsView, ActionDetailView
- [ ] Models: ModelsView
- [ ] Settings: SettingsView（拆分为子页面）
- [ ] Paywall: PaywallView
- [ ] Voice: VoicePickerView
- [ ] 验证 iOS 编译
- **Status:** pending

### Phase 9: 主 App — macOS 专属功能
- [ ] MenuBar: MenuBarManager, MenuBarPopoverView（拆分后）
- [ ] HotKey: HotKeyManager
- [ ] Clipboard: ClipboardMonitor
- [ ] macOS AppDelegate 集成（窗口管理、Services handler）
- [ ] 验证 macOS 编译
- **Status:** pending

### Phase 10: Translation Extension
- [ ] TranslationProvider.swift
- [ ] Extension 与 ShareCore 集成
- [ ] App Group 数据共享验证
- [ ] 验证编译
- **Status:** pending

### Phase 11: 验证与收尾
- [ ] iOS Simulator 全量编译
- [ ] macOS 全量编译
- [ ] 代码格式化（SwiftFormat）
- [ ] Lint 检查（SwiftLint）
- [ ] 核心功能 smoke test
  - 翻译流程（流式 + 非流式）
  - 多模型并发
  - 对话功能
  - TTS 播放
  - 配置导入/导出
  - 订阅流程
  - macOS 菜单栏翻译
  - macOS 快捷键
  - Translation Extension
- [ ] 本地化集成（Localizable.xcstrings）
- **Status:** pending

## Key Design Improvements (vs 旧项目)

| 改进点 | 旧项目 | 新项目 |
|--------|--------|--------|
| HomeView | 1,686 行单文件 | 拆分为 HomeView + InputSection + ResultsSection + Toolbar |
| HomeViewModel | 1,137 行 | 拆分核心状态与流式管理 |
| SettingsView | 1,202 行，25+ @State | 拆分为独立子页面 |
| LLMService | 1,103 行 | 拆分为 Service + RequestBuilder + StreamingParser + Auth |
| MenuBarPopoverView | 634 行含嵌套组件 | 拆分为主视图 + InlineConversation + SelectableTextEditor |
| 目录结构 | 按文件类型 + 扁平 | 按功能域分组 |
| macOS 专属代码 | 与共享代码混放 | 独立 macOS/ 目录 |

## Key Questions
1. ~~仅 iOS？~~ → **iOS + macOS 全平台**
2. ~~Translation Extension？~~ → **需要**
3. ~~ShareCore？~~ → **需要 embedded framework**
4. ~~后端？~~ → **继续使用 Azure Function**
5. ~~Bundle ID？~~ → **com.zanderwang.AITranslator（沿用旧项目）**
6. ~~功能范围？~~ → **全部复刻**

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| 全功能重写而非重构 | 用户明确要求重写，旧代码结构问题较多 |
| 按功能域分文件夹 | 相关代码就近，找代码更直觉 |
| LLMService 拆分为 4 部分 | 原始 1,103 行混合认证/构建/解析/协调 |
| HomeView 拆分为 4-5 部分 | 原始 1,686 行是最大的单文件 |
| SettingsView 拆分为子页面 | 原始 25+ @State，5 种面板混杂 |
| macOS 代码独立目录 | 避免 #if 条件编译散落各处 |
| 保持 MVVM + Combine | 用户要求相同技术栈 |
| 保持 embedded framework | Translation Extension 需要共享代码 |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
|       | 1       |            |

## Notes
- 新项目使用 Xcode 26.4，支持 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 和 `SWIFT_APPROACHABLE_CONCURRENCY`
- fileSystemSynchronizedGroups：放文件到目录自动包含，不需编辑 pbxproj
- 需要修改新项目 Bundle ID: `com.zanderwang.TLingo` → `com.zanderwang.AITranslator`
- 需要配置 App Group: `group.com.zanderwang.AITranslator`
- 旧项目的 Localizable.xcstrings 有 16+ 语言，需要最终集成
