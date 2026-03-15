# Progress Log: TLingo iOS 代码重构

## Session: 2026-03-12

### Phase 1: 代码库调研 ✅
- **时间**: 开始
- **完成内容**:
  - 扫描全部目录结构和 Swift 文件
  - 统计各文件行数，识别 7 个 >500 行的大文件
  - 深入阅读全部 ~70 个 Swift 源文件
  - 分析平台差异（macOS-only / iOS-only / 共享）
  - 识别核心代码异味和重复代码
  - 产出 findings.md 完整报告
  - 产出 task_plan.md 重构计划

### 计划调整
- 用户确认：**全功能重写**（非重构），在 `/Users/zander/Work/AITranslator/TLingo/` 新项目中从零编写
- 范围：iOS + macOS + Translation Extension，全部功能复刻
- 保持旧 Bundle ID: `com.zanderwang.AITranslator`
- 保持 ShareCore embedded framework
- 继续使用 Azure Function 后端
- 计划扩展为 11 个阶段

### 待办
- [ ] Phase 1: 项目基础搭建（Xcode 配置 + targets + 目录骨架）
- [ ] Phase 2: ShareCore 数据模型与配置层
- [ ] Phase 3: ShareCore 网络层
- [ ] Phase 4: ShareCore StoreKit + Utilities + Theme
- [ ] Phase 5: ShareCore 共享 UI 组件
- [ ] Phase 6: ShareCore Home UI
- [ ] Phase 7: ShareCore 对话 + Extension UI + Debug UI
- [ ] Phase 8: 主 App 入口 + 导航 + 核心页面
- [ ] Phase 9: 主 App macOS 专属功能
- [ ] Phase 10: Translation Extension
- [ ] Phase 11: 验证与收尾
