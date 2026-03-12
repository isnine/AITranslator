# Task Plan: TLingo iOS 端代码重构

## Goal
在保持所有现有功能和相同技术栈 (SwiftUI + Swift + Combine) 的前提下，对 TLingo iOS 端代码进行结构性重构，使其更简洁、可读性更好、文件/文件夹分类更合理。

## Current Phase
Phase 1

## Phases

### Phase 1: 代码库调研与现状分析
- [x] 梳理目录结构和文件清单
- [x] 统计各文件行数和复杂度
- [x] 识别代码异味（过大文件、混合职责、重复代码）
- [x] 分析平台差异（iOS-only / macOS-only / 共享）
- [x] 整理发现到 findings.md
- **Status:** complete

### Phase 2: 目标架构设计
- [ ] 设计新的文件夹结构（按功能域分组）
- [ ] 规划大文件的拆分方案
  - HomeView (1,686L) → 拆分为 InputComposer + ResultsContainer + ...
  - HomeViewModel (1,137L) → 拆分 streaming/retry 逻辑
  - SettingsView (1,202L) → 拆分为独立的设置子页面
  - LLMService (1,103L) → 拆分 request builder / streaming parser
  - MenuBarPopoverView (634L) → 提取嵌套组件
- [ ] 确定文件重命名/移动清单
- [ ] 识别可以统一的重复代码
- [ ] 确认不影响 macOS 端现有功能
- **Status:** pending

### Phase 3: ShareCore 基础层重构
- [ ] Configuration 模块整理
- [ ] Networking 模块拆分（LLMService → RequestBuilder + StreamingParser + LLMService）
- [ ] Preferences 模块整理
- [ ] Utilities 模块整理
- [ ] StoreKit 模块整理
- [ ] 确保编译通过
- **Status:** pending

### Phase 4: ShareCore UI 层重构
- [ ] HomeView 拆分为多个子视图
- [ ] HomeViewModel 拆分
- [ ] ProviderResultCardView 整理
- [ ] Conversation 模块检查
- [ ] Components 模块检查
- [ ] 确保编译通过
- **Status:** pending

### Phase 5: 主 App UI 层重构
- [ ] SettingsView 拆分为独立设置页面
- [ ] ModelsView 整理
- [ ] ActionsView / ActionDetailView 整理
- [ ] PaywallView / VoicePickerView 整理
- [ ] macOS 专属文件整理（MenuBar 等）
- [ ] App 入口 (AITranslatorApp.swift) 整理
- [ ] 确保编译通过
- **Status:** pending

### Phase 6: 验证与收尾
- [ ] 全量编译（iOS Simulator + macOS）
- [ ] Translation Extension 功能验证
- [ ] make format && make lint
- [ ] 检查 App Group / 共享数据完整性
- [ ] Smoke test 核心翻译流程
- **Status:** pending

## Scope Definition

### 在范围内
- 文件/文件夹结构重组
- 大文件拆分为职责单一的小文件
- 消除重复代码
- 改善命名和可读性
- 保持完全相同的功能行为

### 不在范围内
- 功能变更或新功能
- 技术栈迁移（例如不切 TCA 或 Observation）
- macOS 端独有功能的重写（只做必要整理）
- Worker/AzureFunction 后端代码
- fastlane/CI 配置
- 单元测试大规模增补（但会保持现有测试通过）

## Key Questions
1. HomeView 的拆分粒度：按功能区域（输入框、结果区、操作栏）还是按平台（iOS/macOS）？→ **按功能区域，平台差异用 #if 处理**
2. ShareCore 是否有必要继续作为独立 framework？→ **是，Translation Extension 需要共享代码**
3. 重构是增量进行（每次一个模块）还是一次性重写？→ **增量，每阶段确保编译通过**
4. macOS MenuBar 相关文件是否移入独立 macOS 子文件夹？→ **待定**
5. 是否引入 Swift Package 替代 embedded framework？→ **暂不考虑，保持 xcodeproj 结构**

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| 按功能域分文件夹 | 比按文件类型分（Views/ViewModels/Models）更易维护，相关代码就近 |
| 增量重构，每阶段可编译 | 降低风险，方便 git bisect 定位问题 |
| 先重构 ShareCore，再重构主 App | ShareCore 是基础层，主 App 依赖它 |
| 保持 ShareCore 为 embedded framework | Translation Extension 需要共享，不能去掉 |
| 不引入新架构模式 (TCA/Redux) | 用户要求保持相同技术栈 |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
|       | 1       |            |

## Notes
- 项目使用 filesystem-synced groups，新 Swift 文件放入正确目录即自动包含，**不需要手动编辑 project.pbxproj**
- 重构时注意 `@MainActor` singleton 的初始化顺序
- App Group (`group.com.zanderwang.AITranslator`) 不能破坏
- 注意保持 `DefaultConfiguration.json` 的路径不变（Bundle 加载用）
