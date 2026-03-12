# Findings: TLingo 代码库调研

## 项目概况

| 指标 | 值 |
|------|-----|
| 项目名称 | TLingo (AITranslator) |
| 技术栈 | SwiftUI + Swift 5.0 + Combine |
| 平台 | iOS 18.4+ / macOS 15.4+ |
| 项目 Swift 文件数 | ~70 个（不含 vendor/build） |
| 项目 Swift 总行数 | ~16,000 行（不含 vendor/build） |
| 模块 | TLingo (主 App) + ShareCore (共享框架) + TLingoTranslation (翻译扩展) |

## 现有目录结构

```
AITranslator/
├── AITranslator/              ← 主 App (iOS + macOS)
│   ├── AITranslatorApp.swift  ← App 入口 + macOS AppDelegate (401L)
│   ├── ClipboardMonitor.swift ← macOS 剪贴板轮询 (114L)
│   ├── HotKeyManager.swift    ← macOS 全局快捷键 (396L)
│   ├── MenuBarManager.swift   ← macOS 菜单栏图标 (198L)
│   ├── MenuBarPopoverView.swift ← macOS 快速翻译弹窗 (634L)
│   ├── Snapshot/              ← 截图导出 (macOS)
│   ├── UI/                    ← 主 App UI
│   │   ├── RootTabView.swift       (113L)
│   │   ├── SettingsView.swift      (1,202L) ⚠️
│   │   ├── ActionsView.swift       (307L)
│   │   ├── ActionDetailView.swift  (478L)
│   │   ├── ModelsView.swift        (423L)
│   │   ├── PaywallView.swift       (346L)
│   │   └── VoicePickerView.swift   (276L)
│   └── Assets.xcassets
├── ShareCore/                 ← 共享框架 (iOS + macOS + Extension)
│   ├── AppColors.swift        (主题色)
│   ├── Configuration/         ← 配置层 (10 files)
│   ├── Networking/            ← 网络层 (10 files)
│   │   └── Debug/             ← 调试网络日志 (4 files)
│   ├── Preferences/           ← 偏好设置 (3 files)
│   ├── StoreKit/              ← 订阅管理 (2 files)
│   ├── UI/                    ← 共享 UI
│   │   ├── HomeView.swift          (1,686L) ⚠️⚠️
│   │   ├── HomeViewModel.swift     (1,137L) ⚠️
│   │   ├── Components/        (5 files)
│   │   ├── Conversation/      (6 files)
│   │   ├── Debug/             (2 files)
│   │   ├── ExtensionCompactView.swift
│   │   ├── DataConsentView.swift
│   │   └── LanguagePickerView.swift
│   ├── Utilities/             (6 files)
│   └── Resources/
│       └── DefaultConfiguration.json
├── TranslationUI/             ← 系统翻译扩展
│   └── TranslationProvider.swift (29L)
├── ShareCoreTests/            ← 单元测试 (2 files)
└── TLingoUITests/             ← UI 测试/截图
```

## 核心问题分析

### 1. 过大文件（>500 行）

| 文件 | 行数 | 问题 |
|------|------|------|
| HomeView.swift | 1,686 | 输入、结果展示、操作栏、扩展上下文、平台差异全混在一起 |
| SettingsView.swift | 1,202 | 配置导入导出、语音选择、模型选择、快捷键配置、网络调试混杂，25+ @State |
| HomeViewModel.swift | 1,137 | 翻译执行、流式状态、TTS、动作选择、错误处理、快照模式 |
| LLMService.swift | 1,103 | HMAC 签名、多模型并发、流式解析、请求构建、图片处理 |
| MenuBarPopoverView.swift | 634 | 翻译输入+操作+结果+内联对话+自定义 NSTextView |
| AppConfigurationStore.swift | 617 | 配置持久化+文件监视+验证+快照 |
| ConfigurationFileManager.swift | 610 | 文件系统监视+iCloud同步 |

### 2. 职责混合

- **AITranslatorApp.swift**: App 入口 + AppDelegate + 窗口管理 + 剪贴板监控启动 + 快捷键注册 + 截图导出 + Services handler
- **SettingsView.swift**: 至少 5 种不同设置面板混在同一个文件
- **HomeView.swift**: 输入区域 + 结果展示 + 操作栏 + 扩展模式处理 + 平台条件编译
- **LLMService.swift**: 请求构建 + 流式解析 + 认证 + 图片处理 + 错误映射

### 3. 重复代码

- **VoicePickerView.swift**: `voiceRow` 和 `voiceRowCard` 实现重复
- **PaywallView.swift**: iOS 和 macOS 端有部分重复的产品展示逻辑
- **HomeView / MenuBarPopoverView / ExtensionCompactView**: 结果展示逻辑有部分重叠

### 4. 命名与组织

- `AITranslator/` 目录同时包含 macOS 专属文件（MenuBar*, ClipboardMonitor, HotKey*）和共享 UI，没有明确分组
- `ShareCore/UI/` 层级较浅，HomeView 和 HomeViewModel 直接放在 UI/ 下
- Debug 相关代码分散在 `ShareCore/Networking/Debug/` 和 `ShareCore/UI/Debug/`

### 5. 架构亮点（保留）

- **App Group** 数据共享设计优秀
- **Configuration 热重载**（文件监视 + 防抖）
- **TaskGroup 并发翻译**多模型结果
- **流式解析**（SSE + 增量 JSON）
- **Conversation 模块**拆分清晰（6 个文件各司其职）
- **组件化**: ActionChipsView, LanguageSwitcherView 等可复用组件

## 平台分类

### macOS 专属
- `ClipboardMonitor.swift` — 剪贴板轮询
- `HotKeyManager.swift` — Carbon Events 全局快捷键
- `MenuBarManager.swift` — NSStatusItem 管理
- `MenuBarPopoverView.swift` — 菜单栏弹窗 UI
- `Snapshot/` — 截图导出（仅 macOS 用）

### iOS 专属
- `TranslationUI/TranslationProvider.swift` — 系统翻译扩展入口

### 共享（iOS + macOS）
- 所有 ShareCore/ 代码
- 主 App UI/ 下的 RootTabView, SettingsView, ActionsView, ActionDetailView, ModelsView, PaywallView, VoicePickerView（含 #if 条件编译）
- AITranslatorApp.swift（含 #if 条件编译）

## 拆分建议

### HomeView.swift (1,686L) → 4-5 个文件
1. **HomeView.swift** (~200L) — 骨架布局 + 组合子视图
2. **HomeInputSection.swift** (~300L) — 输入框 + 图片附件 + 语言切换
3. **HomeResultsSection.swift** (~400L) — 结果卡片列表 + 操作按钮
4. **HomeToolbar.swift** (~150L) — 底部/顶部工具栏
5. 平台差异通过 `#if` 就地处理或提取 modifier

### HomeViewModel.swift (1,137L) → 2-3 个文件
1. **HomeViewModel.swift** (~500L) — 核心状态 + 公开 API
2. **TranslationStreamingManager.swift** (~400L) — 流式请求/取消/重试
3. **TTSPlaybackManager.swift** (~200L) — TTS 控制（可选拆分）

### SettingsView.swift (1,202L) → 4-5 个文件
1. **SettingsView.swift** (~150L) — 设置页面骨架（List/Form）
2. **GeneralSettingsSection.swift** — 通用设置（语言、外观）
3. **ModelSettingsSection.swift** — 模型配置
4. **VoiceSettingsSection.swift** — 语音配置
5. **ConfigImportExportSection.swift** — 配置导入/导出
6. **HotkeySettingsSection.swift** — macOS 快捷键配置

### LLMService.swift (1,103L) → 3-4 个文件
1. **LLMService.swift** (~400L) — 核心 perform() 协调
2. **LLMRequestBuilder.swift** (~300L) — 请求构建 + payload 组装
3. **StreamingResponseParser.swift** (~300L) — SSE 流式解析
4. **CloudServiceAuth.swift** (~100L) — HMAC 签名 + 云服务认证

### MenuBarPopoverView.swift (634L) → 2-3 个文件
1. **MenuBarPopoverView.swift** (~300L) — 主弹窗布局
2. **InlineConversationContent.swift** (~200L) — 内联对话视图
3. **SelectableTextEditor.swift** (~80L) — NSViewRepresentable 文本编辑器
