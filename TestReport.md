# AITranslator (Tree² Lang) 测试报告

**测试日期**: 2025-07-15 (更新)  
**测试环境**: iPhone 17 Pro Simulator (iOS 26.0)  
**测试工具**: XcodeBuildMCP v1.15.1  
**应用版本**: com.zanderwang.AITranslator

---

## 📋 测试概述

本次测试覆盖了 AITranslator 的核心功能路径，包括主界面导航、全部 5 个默认 Actions、语言设置、Actions 和 Providers 管理功能。

## ✅ 测试结果汇总

| 测试项             | 状态    | 备注                                                  |
| ------------------ | ------- | ----------------------------------------------------- |
| 应用构建           | ✅ 通过 | 构建成功，无编译错误                                  |
| Tab 导航           | ✅ 通过 | Home/Actions/Providers/Settings 切换正常 (需用坐标)   |
| Translate          | ✅ 通过 | 输入 → 执行 → 结果显示正常                            |
| Sentence Translate | ✅ 通过 | 逐句翻译，原文+译文对照显示                           |
| Grammar Check      | ✅ 通过 | 语法分析 + 润色建议 + 翻译                            |
| Polish             | ✅ 通过 | 文本润色，**支持 Diff 显示**                          |
| Sentence Analysis  | ✅ 通过 | 完整语法结构分析 (中文输出)                           |
| 目标语言切换       | ✅ 通过 | 8 种语言可选，切换后翻译结果正确                      |
| Action 详情        | ✅ 通过 | 完整配置项: Name/Prompt/Usage/OutputType/Provider     |
| Provider 详情      | ✅ 通过 | Built-in Cloud, 2 models (model-router, gpt-4.1-nano) |
| 创建新配置         | ✅ 通过 | 点击 + 按钮成功创建，继承默认配置内容                 |
| 编辑配置           | ✅ 通过 | JSON 编辑器显示完整配置结构                           |
| 配置切换           | ✅ 通过 | Reset to Default / Use 按钮正常工作                   |
| 删除配置           | ⚠️ 部分 | 删除成功，但产生空配置问题 (见 BUG-001)               |

---

## 🔍 详细测试记录

### 1. 应用构建与启动 (TC-1.1)

**测试步骤**:

1. 配置 MCP 会话 (projectPath, scheme, simulatorId)
2. 执行 `build_run_sim`

**结果**: ✅ 构建成功，应用启动正常

**截图验证**: 主界面正确显示，包含：

- Tree² 标题
- 设置默认翻译应用提示 (可关闭)
- 文本输入框 (placeholder: "Enter text to translate or process...")
- 动作选择器 (5 个 chips)
- Tab 导航栏 (Home/Actions/Providers/Settings)

---

### 2. Tab 导航测试 (TC-2.x)

**测试步骤**:

1. 点击 Home Tab (x:60, y:820)
2. 点击 Actions Tab (x:144, y:820)
3. 点击 Providers Tab (x:211, y:820)
4. 点击 Settings Tab (x:340, y:820)

**结果**: ✅ 所有 Tab 切换正常

**⚠️ 注意**: Tab Bar 的 accessibility label 未正确暴露，需要使用坐标点击

---

### 3. 翻译功能测试 (TC-1.3)

**测试步骤**:

1. 点击输入框
2. 输入 "Hello, how are you today?"
3. 选择 Translate 动作（默认选中）
4. 点击 Send 按钮

**结果**: ✅ 翻译成功

**翻译输出**: "你好，今天过得怎么样？" (目标语言: 简体中文)  
**响应时间**: 5.9s

**UI 元素验证**:

- ✅ 朗读按钮 (🔊)
- ✅ 复制按钮
- ✅ 耗时显示 (5.9s)
- ✅ 成功状态指示器 (✓)
- ✅ Info 按钮 (ⓘ)

---

### 4. Sentence Translate 测试 (TC-1.4)

**输入**: "Hello, how are you today?"  
**输出**:

- 原文: "Hello, how are you today?"
- 译文: "你好，今天过得怎么样？"

**响应时间**: 4.7s  
**结果**: ✅ 通过

---

### 5. Grammar Check 测试 (TC-1.5)

**输入**: "Hello, how are you today?"  
**输出**:

- 原句: "Hello, how are you today?"
- ⚠️ 原句语法上没有错误，但可以根据风格将逗号改为句号或破折号以增强停顿感
- 翻译: "你好，你今天怎么样？"

**响应时间**: 5.7s  
**结果**: ✅ 通过

---

### 6. Polish 测试 (TC-1.6)

**输入**: "Hello, how are you today?"  
**输出** (Diff 格式):

- ~~Hello,~~ → Hello **—**
- how are you → how are you **doing**
- today? → today?

**润色建议**: 添加 "doing" 使句子更完整，将逗号改为破折号

**响应时间**: 5.2s  
**结果**: ✅ 通过 (Diff 效果显示正常)

---

### 7. Sentence Analysis 测试 (TC-1.7)

**输入**: "Hello, how are you today?"  
**输出** (中文):

```markdown
## 📚 语法分析

- 句子由两部分构成: 感叹式问候语 "Hello," + 由 wh-疑问词引导的一般现在时疑问句
- "Hello" 是感叹词/称呼性语段，后接逗号作话轮开启
- "How are you today?" 结构:
  - How (疑问副词，询问状态/方式)
  - are (连系动词 be 的一般现在时，第二人称)
  - you (主语)
  - today (时间状语，置于句末)

## ✍️ 搭配积累

- "How are you" - 日常问候语，寒暄套语
  ...
```

**响应时间**: ~15s (流式输出)  
**结果**: ✅ 通过 (Markdown 格式渲染正常)

---

### 8. 目标语言切换测试 (TC-3.x)

**测试步骤**:

1. 进入 Settings Tab
2. 点击 Target Language (显示 "Match App Language")
3. 在弹出的选择器中选择 "简体中文"
4. 返回 Home 执行翻译

**结果**: ✅ 语言切换成功

**验证**:

- Settings 页面显示 "Target Language, 简体中文"
- 翻译结果正确为中文 ("你好，今天过得怎么样？")

**可选语言** (8 种):

1. Match App Language (English)
2. English
3. 简体中文 (Chinese, Simplified)
4. 日本語 (Japanese)
5. 한국어 (Korean)
6. français (French)
7. Deutsch (German)
8. español (Spanish)

---

### 9. Action 详情测试 (TC-5.x)

**测试步骤**:

1. 进入 Actions Tab
2. 查看 Actions 列表 (5 个 Actions)
3. 点击 Translate 动作

**结果**: ✅ 详情页显示正常

**Actions 列表**:
| Action | Description | Models |
|--------|-------------|--------|
| Translate | Translate the selected text i... | 1 models |
| Sentence Translate | Translate the following text... | 1 models |
| Grammar Check | Review this text for gramma... | 1 models |
| Polish | Polish the text and return th... | 1 models |
| Sentence Analysis | Analyze the provided sente... | 1 models |

**Action 详情页显示内容**:

- **Basic Info**: Action Name
- **Prompt Template**: 完整 prompt (支持 {text} 和 {targetLanguage} 占位符)
- **Usage Scenes**: In App / Read-Only Context / Editable Context
- **Output Type**: Plain Text / Show Diff / Sentence Pairs / Grammar Check
- **Provider**: (需滚动查看)

---

### 10. Provider 详情测试 (TC-6.x)

**测试步骤**:

1. 进入 Providers Tab
2. 查看 Providers 列表
3. 点击 Built-in Cloud

**结果**: ✅ 配置信息完整显示

**Providers 列表**:

- Built-in Cloud (1 of 2 models enabled) ✅

**Provider 详情页显示内容**:

- **Provider Type**:

  - Built-in Cloud ⦿ (已选中) - Use built-in cloud service, no configuration needed
  - Azure OpenAI ○ - Connect to your Azure OpenAI deployment
  - Custom ○ - Connect to a custom OpenAI-compatible API

- **Model Selection**:

  - model-router ☑️ - Smart routing - automatically selects the best model
  - gpt-4.1-nano ○ - Fast & efficient - optimized for quick responses

- **Status**: ✅ Ready to use - No API key required

- **Danger Zone**: Delete Provider 按钮

---

### 11. 配置管理测试 (TC-4.x)

#### TC-4.1 创建新配置

**测试步骤**:

1. 进入 Settings Tab
2. 查看 CONFIGURATION 部分 - Default Configuration (Read-Only)
3. 点击 + 按钮创建新配置

**结果**: ✅ 创建成功

- 新配置命名为 "New Configuration"
- 自动继承默认配置内容 (1 Providers · 5 Actions)
- 新配置自动激活 (蓝色点标记)

#### TC-4.2 查看/编辑配置

**测试步骤**:

1. 点击 "New Configuration, in 0s" 按钮
2. 查看配置编辑界面

**结果**: ✅ JSON 编辑器正常显示

**配置结构**:

```json
{
  "actions": [
    /* 5 个 Actions */
  ],
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
  "version": "1.1.0"
}
```

**UI 元素**: Cancel 按钮、Save 按钮、JSON 文本编辑区

#### TC-4.3 配置切换 - Reset to Default

**测试步骤**:

1. 在 Settings 页面，当 New Configuration 激活时
2. 点击 Reset to Default (↺) 按钮

**结果**: ✅ 切换成功

- 界面显示两个配置:
  - Default Configuration (Read-Only) ✅ 激活
  - New Configuration - 显示 "Use" 按钮和删除按钮

#### TC-4.4 配置切换 - 使用自定义配置

**测试步骤**:

1. 在配置列表中找到 New Configuration
2. 点击 "Use" 按钮

**结果**: ✅ 切换成功

- New Configuration 变为激活状态 (蓝色点)
- 显示 Reset to Default 按钮

#### TC-4.5 删除配置

**测试步骤**:

1. 点击删除按钮 (🗑️)
2. 确认对话框显示 "Delete Configuration? This action cannot be undone."
3. 点击 Delete 确认

**结果**: ⚠️ 部分通过 (发现 BUG)

- 配置删除成功
- **问题**: 删除后产生空配置 (0 Providers · 0 Actions)
- **恢复方法**: 点击 Reset to Default 恢复正常

---

## ⚠️ 发现的问题

### 🐛 BUG-001: 删除当前活动配置后产生空配置

**严重程度**: 🟡 中等

**描述**: 当删除当前正在使用的自定义配置时，系统没有自动切换回默认配置，而是创建了一个空的 "New Configuration" (0 Providers · 0 Actions)。

**复现步骤**:

1. 在 Settings > CONFIGURATION 中点击 + 创建新配置
2. 新配置自动激活
3. 点击删除按钮 (🗑️)
4. 确认删除

**预期结果**: 删除后自动切换回 Default Configuration

**实际结果**: 创建了一个空的 "New Configuration"

- 显示 "0 Providers · 0 Actions"
- 需要手动点击 Reset to Default 恢复

**影响**:

- 用户可能困惑为什么配置变空
- Actions 功能暂时不可用

**建议修复**:

```swift
// 删除配置后，检查是否需要回退到默认
func deleteConfiguration(_ config: Configuration) {
    configurations.remove(config)
    if activeConfiguration == config {
        activeConfiguration = defaultConfiguration
    }
}
```

---

### 问题 1: Tab Bar Accessibility 问题

**严重程度**: � 高

**描述**: 底部 Tab Bar 的各个 Tab 按钮没有正确暴露 accessibility label。`describe_ui` 只返回一个 "Tab Bar" Group，不包含子元素 (children 为空数组)。

**影响**:

- 无法通过 accessibility label 直接点击 Tab
- 影响 VoiceOver 等辅助功能的使用
- 自动化测试需要使用硬编码坐标

**Tab Bar 坐标** (iPhone 17 Pro, 402x874):
| Tab | X 坐标 | Y 坐标 |
|-----|--------|--------|
| Home | 60 | 820 |
| Actions | 144 | 820 |
| Providers | 211 | 820 |
| Settings | 340 | 820 |

**建议修复**:

```swift
// 确保每个 Tab 都有正确的 accessibilityLabel
TabView {
    HomeView()
        .tabItem { ... }
        .accessibilityLabel("Home")
    // ...
}
```

---

### 问题 2: 动作选择器水平滚动未完全显示

**严重程度**: 🟢 低

**描述**: 动作选择器 (Action Chip) 使用水平 ScrollView，初始状态下只能看到 Translate、Sentence Translate 和 Grammar Check 的部分。Polish 和 Sentence Analysis 需要滑动才能看到。

**影响**:

- 新用户可能不知道还有更多动作
- 部分动作可见性较低

**建议改进**:

1. 在末尾添加滚动指示器或渐变效果
2. 或者使用两行布局
3. 或者添加 "更多" 提示

---

### 问题 3: 默认翻译应用提示一直显示

**严重程度**: 🟢 低

**描述**: "Set Tree² as the default translation app" 提示在主界面一直显示。

**当前情况**: 提示已有关闭按钮 (X)，可以手动关闭 ✅

**建议改进**:

1. 记住用户的关闭选择，不再重复显示
2. 或者在设置后自动隐藏

---

### 问题 4: 部分 Action 按钮无法通过 Label 点击

**严重程度**: 🟡 中等

**描述**: Actions 列表中的 Action 行虽然是 Button，但其 label 是完整的多行文本（包含名称、描述、models 数量），导致无法用短 label 如 "Translate" 直接匹配。

**示例**:

```
AXLabel: "Translate, Translate the selected text into {{targetLanguage}}. If the input language already matches the target language, translate it into English instead. Preserve tone, intent, and terminology. Respond with only the translated text., ·, 1 models"
```

**建议修复**:

```swift
Button { ... }
    .accessibilityLabel("Translate")
    .accessibilityHint("Translate the selected text...")
```

---

## 📊 性能观察

| 操作               | 响应时间  | 备注               |
| ------------------ | --------- | ------------------ |
| Translate          | 5.9s      | 简体中文输出       |
| Sentence Translate | 4.7s      | 原文+译文对照      |
| Grammar Check      | 5.7s      | 语法分析+翻译      |
| Polish             | 5.2s      | Diff 格式输出      |
| Sentence Analysis  | ~15s      | 流式输出，内容较长 |
| UI 交互            | 即时响应  |                    |
| Tab 切换           | &lt;100ms |                    |
| 语言选择弹窗       | &lt;100ms |                    |

**注**: 网络请求时间可能因网络环境而异。使用 Built-in Cloud (model-router)。

---

## 🎯 改进建议

### 紧急修复

1. **BUG-001 配置删除逻辑**: 删除当前活动配置后应自动切换回默认配置，而不是创建空配置

### 高优先级

2. **修复 Tab Bar Accessibility**: 确保所有 Tab 都有正确的 accessibility 标签，以支持 VoiceOver 和自动化测试

3. **改进 Actions 列表 Accessibility**: 将按钮的 accessibilityLabel 设为简短名称，accessibilityHint 设为详细描述

### 中优先级

4. **添加 Loading 取消功能**: 当前使用 skeleton 效果，建议添加取消请求的能力

5. **优化动作选择器**: 添加滚动指示或使用 FlowLayout

### 低优先级

6. **记住提示关闭状态**: 默认翻译应用提示关闭后应该持久化

7. **添加本地化**: 界面文字目前是英文，可以考虑本地化

---

## ✨ 亮点功能

1. **5 种默认 Actions**: Translate、Sentence Translate、Grammar Check、Polish、Sentence Analysis 覆盖常见使用场景

2. **目标语言动态更新**: 切换语言后，所有相关动作的 Prompt 自动更新 (使用 {{targetLanguage}} 占位符)

3. **多种输出类型**: Plain Text / Show Diff / Sentence Pairs / Grammar Check，满足不同需求

4. **Polish 的 Diff 显示**: 清晰展示修改前后的差异，使用删除线和高亮

5. **Sentence Analysis 的 Markdown 渲染**: 完整支持 Markdown 格式，包括标题、列表等

6. **流式输出**: AI 响应实时显示，用户体验流畅

7. **响应时间显示**: 每次请求都显示耗时，便于用户了解性能

8. **Built-in Cloud**: 开箱即用，无需配置 API key

---

## 📝 测试总结

AITranslator (Tree² Lang) 的核心功能运行正常，全部 5 个默认 Actions 测试通过。主要问题集中在 Accessibility 支持上：

1. **Tab Bar** 不暴露子元素的 accessibility 信息
2. **Actions 列表** 按钮的 label 包含完整描述而非简短名称

建议优先修复 Accessibility 问题，以提升应用的可访问性和自动化测试能力。

**测试结论**: ✅ **核心功能全部通过测试**，发现 1 个功能性 Bug (配置删除) 和 4 个可访问性问题，建议按优先级修复

---

## 🧪 MCP 测试命令参考

```bash
# 1. 设置会话默认值
session-set-defaults:
  projectPath: /Users/zander/Work/AITranslator/AITranslator.xcodeproj
  scheme: AITranslator
  simulatorId: 92C42607-9840-40A3-9EA7-70C95701B474

# 2. 构建并运行
build_run_sim

# 3. Tab 导航 (使用坐标)
tap: { x: 60, y: 820 }   # Home
tap: { x: 144, y: 820 }  # Actions
tap: { x: 211, y: 820 }  # Providers
tap: { x: 340, y: 820 }  # Settings

# 4. 输入文本
tap: { label: "Enter text to translate or process..." }
type_text: { text: "Hello, how are you today?" }

# 5. 执行 Actions
tap: { label: "Translate" }
tap: { label: "Sentence Translate" }
tap: { label: "Grammar Check" }
tap: { label: "Polish" }
tap: { label: "Sentence Analysis" }

# 6. 语言选择
tap: { x: 201, y: 238 }  # Target Language button
tap: { label: "简体中文, Chinese, Simplified" }
```
