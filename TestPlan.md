# Tree² Lang (AITranslator) MCP 自动化测试计划

## 概述

本测试计划专为 MCP (XcodeBuildMCP) 自动化测试设计，涵盖 Tree² Lang 应用的核心功能验证。所有测试步骤均以 MCP 工具调用格式编写，便于自动化执行。

---

## 测试环境配置

### 前置条件

```bash
# 1. 设置会话默认值
mcp_xcodebuildmcp_session-set-defaults {
  "projectPath": "/Users/zander/Work/AITranslator/AITranslator.xcodeproj",
  "scheme": "AITranslator",
  "useLatestOS": true
}

# 2. 构建并运行应用
mcp_xcodebuildmcp_build_run_sim
```

### 应用信息

| 项目          | 值                                     |
| ------------- | -------------------------------------- |
| Bundle ID     | `com.zanderwang.AITranslator`          |
| 主 Tab 数量   | 4 (Home, Actions, Providers, Settings) |
| 默认 Actions  | 5 个                                   |
| 默认 Provider | Built-in Cloud                         |

---

## 测试用例

### 模块 1：Home 页面核心功能

#### TC-1.1 应用启动验证

**目的**：验证应用正常启动并显示 Home 页面

```bash
# 步骤 1：截图确认应用已启动
mcp_xcodebuildmcp_screenshot

# 步骤 2：获取 UI 层次结构
mcp_xcodebuildmcp_describe_ui
```

**预期结果**：

- 应用显示 Home 页面
- 可见"Tree²"标题
- 显示输入框和动作选择器
- 底部 Tab Bar 可见

---

#### TC-1.2 文本输入功能

**目的**：验证用户可以输入文本

```bash
# 步骤 1：获取 UI 找到输入框位置
mcp_xcodebuildmcp_describe_ui

# 步骤 2：点击输入框（根据 describe_ui 返回的坐标）
mcp_xcodebuildmcp_tap { "x": <input_field_x>, "y": <input_field_y> }

# 步骤 3：输入测试文本
mcp_xcodebuildmcp_type_text { "text": "Hello, how are you today?" }

# 步骤 4：截图验证输入内容
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 输入框显示输入的文本
- Send 按钮变为可用状态

---

#### TC-1.3 翻译功能（默认 Action）

**目的**：验证 Translate 动作正常工作

```bash
# 步骤 1：确保输入框有文本（承接 TC-1.2）
mcp_xcodebuildmcp_describe_ui

# 步骤 2：点击 "Translate" chip（通过 label 或坐标）
mcp_xcodebuildmcp_tap { "label": "Translate" }
# 或使用坐标
# mcp_xcodebuildmcp_tap { "x": <translate_chip_x>, "y": <translate_chip_y> }

# 步骤 3：点击 Send 按钮
mcp_xcodebuildmcp_tap { "label": "Send" }

# 步骤 4：等待响应（约 3-5 秒）
# 注意：需要延时等待

# 步骤 5：截图验证翻译结果
mcp_xcodebuildmcp_screenshot

# 步骤 6：获取 UI 验证结果卡片
mcp_xcodebuildmcp_describe_ui
```

**预期结果**：

- 显示翻译结果卡片
- 卡片包含翻译后的文本
- 显示成功状态图标（绿色对勾）
- 显示响应时间
- 显示 Copy 和 Speak 按钮

---

#### TC-1.4 Sentence Translate 功能

**目的**：验证句子逐句翻译功能

```bash
# 步骤 1：清空输入框（如需要）
# 步骤 2：输入多句文本
mcp_xcodebuildmcp_tap { "x": <input_field_x>, "y": <input_field_y> }
mcp_xcodebuildmcp_type_text { "text": "Hello world. How are you? Nice to meet you." }

# 步骤 3：点击 "Sentence Translate" chip
mcp_xcodebuildmcp_tap { "label": "Sentence Translate" }
# 或滚动到可见位置
mcp_xcodebuildmcp_gesture { "preset": "scroll-right" }
mcp_xcodebuildmcp_tap { "label": "Sentence Translate" }

# 步骤 4：点击 Send
mcp_xcodebuildmcp_tap { "label": "Send" }

# 步骤 5：等待并截图
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 结果以句子对形式展示
- 每对包含原文和译文
- 句子之间有分隔线

---

#### TC-1.5 Grammar Check 功能（结构化输出）

**目的**：验证语法检查的结构化输出

```bash
# 步骤 1：输入含语法错误的文本
mcp_xcodebuildmcp_tap { "x": <input_field_x>, "y": <input_field_y> }
mcp_xcodebuildmcp_type_text { "text": "She don't likes apples. Me and him goes to school everyday." }

# 步骤 2：点击 "Grammar Check" chip
mcp_xcodebuildmcp_tap { "label": "Grammar Check" }

# 步骤 3：点击 Send
mcp_xcodebuildmcp_tap { "label": "Send" }

# 步骤 4：等待较长时间（约 8-10 秒）
# 步骤 5：截图验证
mcp_xcodebuildmcp_screenshot

# 步骤 6：验证 UI 结构
mcp_xcodebuildmcp_describe_ui
```

**预期结果**：

- 显示修正后的文本（revised_text）
- 显示额外分析内容（additional_text）
- 启用 diff 对比显示（删除线 + 高亮）

---

#### TC-1.6 Polish 功能（Diff 对比）

**目的**：验证 Polish 动作的 diff 对比显示

```bash
# 步骤 1：输入需要润色的文本
mcp_xcodebuildmcp_tap { "x": <input_field_x>, "y": <input_field_y> }
mcp_xcodebuildmcp_type_text { "text": "I am very very happy today because the weather is good and sunny." }

# 步骤 2：点击 "Polish" chip
mcp_xcodebuildmcp_tap { "label": "Polish" }

# 步骤 3：点击 Send
mcp_xcodebuildmcp_tap { "label": "Send" }

# 步骤 4：截图验证 diff 效果
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 原文以删除线形式展示
- 修订后的文本以高亮形式展示
- 清晰显示差异部分

---

#### TC-1.7 Sentence Analysis 功能

**目的**：验证句子分析功能

```bash
# 步骤 1：输入复杂句子
mcp_xcodebuildmcp_tap { "x": <input_field_x>, "y": <input_field_y> }
mcp_xcodebuildmcp_type_text { "text": "Had I known about the meeting, I would have prepared the presentation in advance." }

# 步骤 2：滚动并点击 "Sentence Analysis" chip
mcp_xcodebuildmcp_gesture { "preset": "scroll-right" }
mcp_xcodebuildmcp_tap { "label": "Sentence Analysis" }

# 步骤 3：点击 Send
mcp_xcodebuildmcp_tap { "label": "Send" }

# 步骤 4：截图验证
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 显示"📚 语法分析"部分
- 显示"✍️ 搭配积累"部分
- 使用目标语言展示分析结果

---

### 模块 2：Tab 导航

#### TC-2.1 切换到 Actions Tab

**目的**：验证 Tab 导航到 Actions 页面

```bash
# 步骤 1：获取 UI 找到 Tab Bar 位置
mcp_xcodebuildmcp_describe_ui

# 步骤 2：点击 Actions Tab（第二个 Tab）
# Tab Bar 通常在屏幕底部，根据实际坐标调整
mcp_xcodebuildmcp_tap { "x": <actions_tab_x>, "y": <tab_bar_y> }

# 步骤 3：截图验证
mcp_xcodebuildmcp_screenshot

# 步骤 4：验证 UI 结构
mcp_xcodebuildmcp_describe_ui
```

**预期结果**：

- 显示 "Actions" 标题
- 显示 5 个默认动作列表
- 每个动作显示名称和 models 数量

---

#### TC-2.2 切换到 Providers Tab

**目的**：验证 Tab 导航到 Providers 页面

```bash
# 步骤 1：点击 Providers Tab（第三个 Tab）
mcp_xcodebuildmcp_tap { "x": <providers_tab_x>, "y": <tab_bar_y> }

# 步骤 2：截图验证
mcp_xcodebuildmcp_screenshot

# 步骤 3：验证 UI 结构
mcp_xcodebuildmcp_describe_ui
```

**预期结果**：

- 显示 "Providers" 标题
- 显示 Built-in Cloud Provider
- 显示 Provider 状态（active/inactive）

---

#### TC-2.3 切换到 Settings Tab

**目的**：验证 Tab 导航到 Settings 页面

```bash
# 步骤 1：点击 Settings Tab（第四个 Tab）
mcp_xcodebuildmcp_tap { "x": <settings_tab_x>, "y": <tab_bar_y> }

# 步骤 2：截图验证
mcp_xcodebuildmcp_screenshot

# 步骤 3：验证 UI 结构
mcp_xcodebuildmcp_describe_ui
```

**预期结果**：

- 显示 "Settings" 标题
- 显示 General 部分（Target Language）
- 显示 Configuration 部分
- 显示 Text to Speech 部分

---

### 模块 3：目标语言设置

#### TC-3.1 打开语言选择器

**目的**：验证语言选择器正常打开

```bash
# 前置：已在 Settings Tab

# 步骤 1：获取 UI 找到 Target Language 行位置
mcp_xcodebuildmcp_describe_ui

# 步骤 2：点击 Target Language 行
mcp_xcodebuildmcp_tap { "label": "Target Language" }
# 或使用坐标
# mcp_xcodebuildmcp_tap { "x": <language_row_x>, "y": <language_row_y> }

# 步骤 3：截图验证 Picker
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 显示语言选择列表
- 列出所有支持的语言：
  - Match App Language
  - English
  - 简体中文
  - 日本語
  - 한국어
  - Français
  - Deutsch
  - Español

---

#### TC-3.2 切换目标语言为简体中文

**目的**：验证语言切换功能

```bash
# 前置：语言选择器已打开

# 步骤 1：点击 "简体中文" 选项
mcp_xcodebuildmcp_tap { "label": "简体中文" }
# 或通过坐标点击
# mcp_xcodebuildmcp_tap { "x": <chinese_option_x>, "y": <chinese_option_y> }

# 步骤 2：截图验证设置已更改
mcp_xcodebuildmcp_screenshot

# 步骤 3：返回 Home 验证翻译效果
mcp_xcodebuildmcp_tap { "x": <home_tab_x>, "y": <tab_bar_y> }

# 步骤 4：执行翻译测试
mcp_xcodebuildmcp_tap { "x": <input_field_x>, "y": <input_field_y> }
mcp_xcodebuildmcp_type_text { "text": "Good morning" }
mcp_xcodebuildmcp_tap { "label": "Translate" }
mcp_xcodebuildmcp_tap { "label": "Send" }

# 步骤 5：截图验证翻译结果为中文
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 设置页显示目标语言为 "简体中文"
- 翻译结果为简体中文

---

#### TC-3.3 切换目标语言为日语

**目的**：验证语言切换到日语

```bash
# 步骤 1：返回 Settings
mcp_xcodebuildmcp_tap { "x": <settings_tab_x>, "y": <tab_bar_y> }

# 步骤 2：点击 Target Language
mcp_xcodebuildmcp_tap { "label": "Target Language" }

# 步骤 3：选择日语
mcp_xcodebuildmcp_tap { "label": "日本語" }

# 步骤 4：截图验证
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 目标语言显示为 "日本語"
- 后续翻译结果为日语

---

### 模块 4：Configuration 配置管理

#### TC-4.1 查看当前配置状态

**目的**：验证配置状态显示正确

```bash
# 前置：已在 Settings Tab

# 步骤 1：获取 UI 查看 Configuration 部分
mcp_xcodebuildmcp_describe_ui

# 步骤 2：截图
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 显示当前配置名称（Default 或自定义）
- 显示 Provider 数量和 Action 数量
- Default 配置显示 "Read-Only" 标签

---

#### TC-4.2 创建新配置

**目的**：验证从默认模板创建新配置

```bash
# 前置：已在 Settings Tab

# 步骤 1：找到 "+" 按钮创建新配置
mcp_xcodebuildmcp_describe_ui

# 步骤 2：点击 "+" 按钮
mcp_xcodebuildmcp_tap { "label": "Create New Configuration" }
# 或使用坐标
# mcp_xcodebuildmcp_tap { "x": <plus_button_x>, "y": <plus_button_y> }

# 步骤 3：截图验证新配置已创建
mcp_xcodebuildmcp_screenshot

# 步骤 4：验证 UI
mcp_xcodebuildmcp_describe_ui
```

**预期结果**：

- 创建新配置（名称如 "Custom_20260106_123456"）
- 自动切换到新配置
- 新配置不显示 "Read-Only" 标签

---

#### TC-4.3 切换配置

**目的**：验证配置切换功能

```bash
# 前置：存在多个配置

# 步骤 1：在配置列表中找到其他配置
mcp_xcodebuildmcp_describe_ui

# 步骤 2：点击配置旁边的 "Use" 按钮
mcp_xcodebuildmcp_tap { "label": "Use" }

# 步骤 3：截图验证配置已切换
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 配置切换成功
- 当前配置显示蓝色高亮
- Actions 和 Providers 更新为新配置内容

---

#### TC-4.4 重置到默认配置

**目的**：验证重置功能

```bash
# 前置：当前使用非默认配置

# 步骤 1：找到重置按钮（arrow.counterclockwise）
mcp_xcodebuildmcp_describe_ui

# 步骤 2：点击重置按钮
mcp_xcodebuildmcp_tap { "label": "Reset to Default" }
# 或通过坐标点击

# 步骤 3：截图验证已重置
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 切换回 Default 配置
- 显示 "Read-Only" 标签
- 重置按钮消失

---

### 模块 5：Actions 管理

#### TC-5.1 查看 Action 列表

**目的**：验证 Action 列表正确显示

```bash
# 步骤 1：切换到 Actions Tab
mcp_xcodebuildmcp_tap { "x": <actions_tab_x>, "y": <tab_bar_y> }

# 步骤 2：获取 UI 验证列表
mcp_xcodebuildmcp_describe_ui

# 步骤 3：截图
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 显示 5 个默认 Actions：
  1. Translate
  2. Sentence Translate
  3. Grammar Check
  4. Polish
  5. Sentence Analysis
- 每个 Action 显示图标、名称、描述

---

#### TC-5.2 查看 Action 详情

**目的**：验证 Action 详情页面

```bash
# 步骤 1：点击 "Translate" Action
mcp_xcodebuildmcp_tap { "label": "Translate" }
# 或根据坐标点击第一个 Action

# 步骤 2：截图详情页
mcp_xcodebuildmcp_screenshot

# 步骤 3：验证 UI
mcp_xcodebuildmcp_describe_ui
```

**预期结果**：

- 显示 Action 名称
- 显示 Prompt 内容
- 显示 Output Type 设置
- 显示 Usage Scenes 设置

---

#### TC-5.3 编辑 Action（需非默认配置）

**目的**：验证 Action 编辑功能

```bash
# 前置：使用非默认（可编辑）配置

# 步骤 1：进入 Action 详情
mcp_xcodebuildmcp_tap { "label": "Translate" }

# 步骤 2：编辑 Action 名称
# 找到名称输入框并点击
mcp_xcodebuildmcp_tap { "x": <name_field_x>, "y": <name_field_y> }
mcp_xcodebuildmcp_type_text { "text": " (Custom)" }

# 步骤 3：点击保存/返回
mcp_xcodebuildmcp_button { "buttonType": "home" }
# 或点击返回按钮

# 步骤 4：截图验证修改已保存
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- Action 名称更新为 "Translate (Custom)"
- 修改自动保存到配置文件

---

#### TC-5.4 创建新 Action

**目的**：验证创建新 Action 功能

```bash
# 前置：使用非默认配置

# 步骤 1：在 Actions 页面点击 "+" 按钮
mcp_xcodebuildmcp_tap { "x": <add_action_x>, "y": <add_action_y> }

# 步骤 2：截图新 Action 创建页面
mcp_xcodebuildmcp_screenshot

# 步骤 3：填写 Action 信息
mcp_xcodebuildmcp_tap { "x": <name_field_x>, "y": <name_field_y> }
mcp_xcodebuildmcp_type_text { "text": "My Custom Action" }

# 步骤 4：填写 Prompt
mcp_xcodebuildmcp_tap { "x": <prompt_field_x>, "y": <prompt_field_y> }
mcp_xcodebuildmcp_type_text { "text": "Explain the text in simple words for a child to understand." }

# 步骤 5：保存并返回
# 步骤 6：截图验证新 Action 出现在列表中
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 新 Action 出现在列表末尾
- 可在 Home 页面的 Action 选择器中使用

---

#### TC-5.5 重新排序 Actions

**目的**：验证 Action 拖拽排序功能

```bash
# 步骤 1：点击 "Reorder" 按钮
mcp_xcodebuildmcp_tap { "label": "Reorder" }

# 步骤 2：截图显示拖拽手柄
mcp_xcodebuildmcp_screenshot

# 步骤 3：执行拖拽操作（通过长按和移动）
# 注意：MCP 可能需要 long_press + swipe 组合

# 步骤 4：点击 "Done"
mcp_xcodebuildmcp_tap { "label": "Done" }

# 步骤 5：截图验证排序结果
mcp_xcodebuildmcp_screenshot
```

---

### 模块 6：Providers 管理

#### TC-6.1 查看 Provider 列表

**目的**：验证 Provider 列表正确显示

```bash
# 步骤 1：切换到 Providers Tab
mcp_xcodebuildmcp_tap { "x": <providers_tab_x>, "y": <tab_bar_y> }

# 步骤 2：获取 UI
mcp_xcodebuildmcp_describe_ui

# 步骤 3：截图
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 显示 Built-in Cloud Provider
- 显示 Provider 状态（绿色对勾表示 active）
- 显示启用的 models 数量

---

#### TC-6.2 展开 Provider 查看 Deployments

**目的**：验证 Deployment 列表展开

```bash
# 步骤 1：点击 Provider 行的展开箭头
mcp_xcodebuildmcp_tap { "x": <expand_arrow_x>, "y": <provider_row_y> }

# 步骤 2：截图展开后的列表
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 显示 Deployment 列表：
  - model-router
  - gpt-4.1-nano
- 每个 Deployment 有启用/禁用开关

---

#### TC-6.3 切换 Deployment 启用状态

**目的**：验证 Deployment 启用/禁用功能

```bash
# 前置：Provider 已展开

# 步骤 1：点击某个 Deployment 的开关
mcp_xcodebuildmcp_tap { "label": "gpt-4.1-nano" }
# 或点击开关位置

# 步骤 2：截图验证状态变化
mcp_xcodebuildmcp_screenshot

# 步骤 3：返回 Home 验证影响
mcp_xcodebuildmcp_tap { "x": <home_tab_x>, "y": <tab_bar_y> }
```

**预期结果**：

- Deployment 启用状态切换
- Home 页执行 Action 时使用的 models 相应变化

---

#### TC-6.4 查看 Provider 详情

**目的**：验证 Provider 详情页

```bash
# 步骤 1：点击 Provider 名称区域进入详情
mcp_xcodebuildmcp_tap { "label": "Built-in Cloud" }

# 步骤 2：截图详情页
mcp_xcodebuildmcp_screenshot

# 步骤 3：验证 UI
mcp_xcodebuildmcp_describe_ui
```

**预期结果**：

- 显示 Provider 名称
- 显示 Category（Built-in Cloud）
- 显示 Endpoint URL
- 显示 API Version
- 显示 Deployments 列表

---

#### TC-6.5 添加新 Provider

**目的**：验证创建新 Provider 功能

```bash
# 步骤 1：点击 "+" 按钮
mcp_xcodebuildmcp_tap { "x": <add_provider_x>, "y": <add_provider_y> }

# 步骤 2：截图创建页面
mcp_xcodebuildmcp_screenshot

# 步骤 3：填写 Provider 信息
mcp_xcodebuildmcp_tap { "x": <name_field_x>, "y": <name_field_y> }
mcp_xcodebuildmcp_type_text { "text": "My Custom Provider" }

# 步骤 4：填写 Endpoint
mcp_xcodebuildmcp_tap { "x": <endpoint_field_x>, "y": <endpoint_field_y> }
mcp_xcodebuildmcp_type_text { "text": "https://api.example.com/v1" }

# 步骤 5：保存并返回
mcp_xcodebuildmcp_screenshot
```

---

### 模块 7：TTS 文字转语音

#### TC-7.1 验证默认 TTS 配置

**目的**：验证 Built-in Cloud TTS 默认启用

```bash
# 步骤 1：切换到 Settings Tab
mcp_xcodebuildmcp_tap { "x": <settings_tab_x>, "y": <tab_bar_y> }

# 步骤 2：滚动到 TTS 部分
mcp_xcodebuildmcp_gesture { "preset": "scroll-down" }

# 步骤 3：截图验证 TTS 设置
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- "Use Built-in Cloud" 开关默认开启
- 显示 Voice 选择器

---

#### TC-7.2 更改 TTS Voice

**目的**：验证 Voice 切换功能

```bash
# 步骤 1：点击 Voice 选择器
mcp_xcodebuildmcp_tap { "label": "Voice" }
# 或点击当前选中的 voice

# 步骤 2：截图 Voice 列表
mcp_xcodebuildmcp_screenshot

# 步骤 3：选择不同的 Voice
mcp_xcodebuildmcp_tap { "label": "Nova" }
# 或其他可用 voice

# 步骤 4：截图验证更改
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- Voice 列表显示多个选项（alloy, echo, fable, onyx, nova, shimmer 等）
- 选择后显示新的 Voice

---

#### TC-7.3 测试 TTS 播放

**目的**：验证语音播放功能

```bash
# 步骤 1：切换到 Home Tab
mcp_xcodebuildmcp_tap { "x": <home_tab_x>, "y": <tab_bar_y> }

# 步骤 2：输入文本并翻译
mcp_xcodebuildmcp_tap { "x": <input_field_x>, "y": <input_field_y> }
mcp_xcodebuildmcp_type_text { "text": "Hello world" }
mcp_xcodebuildmcp_tap { "label": "Translate" }
mcp_xcodebuildmcp_tap { "label": "Send" }

# 步骤 3：等待翻译完成
# 步骤 4：点击 Speak 按钮（speaker.wave.2.fill）
mcp_xcodebuildmcp_describe_ui
# 找到 speak 按钮坐标
mcp_xcodebuildmcp_tap { "x": <speak_button_x>, "y": <speak_button_y> }

# 步骤 5：截图验证播放状态
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- Speak 按钮变为加载状态
- 音频开始播放
- 播放完成后按钮恢复正常

---

### 模块 8：错误处理

#### TC-8.1 空输入处理

**目的**：验证空输入时的行为

```bash
# 步骤 1：确保输入框为空
mcp_xcodebuildmcp_tap { "x": <home_tab_x>, "y": <tab_bar_y> }

# 步骤 2：验证 Send 按钮状态
mcp_xcodebuildmcp_describe_ui

# 步骤 3：截图
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- Send 按钮处于禁用状态（透明度降低）
- 点击无响应

---

#### TC-8.2 网络错误处理

**目的**：验证网络错误时的 UI 反馈

```bash
# 注意：此测试需要模拟网络错误环境

# 步骤 1：在网络错误条件下执行翻译
mcp_xcodebuildmcp_tap { "x": <input_field_x>, "y": <input_field_y> }
mcp_xcodebuildmcp_type_text { "text": "Test text" }
mcp_xcodebuildmcp_tap { "label": "Send" }

# 步骤 2：截图错误状态
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 显示错误卡片
- 显示红色警告图标
- 显示错误信息
- 显示 "Retry" 按钮

---

### 模块 9：UI 适配

#### TC-9.1 深色模式验证

**目的**：验证深色模式下的 UI 显示

```bash
# 步骤 1：切换系统到深色模式
# 可能需要通过系统设置

# 步骤 2：重新启动应用或等待模式切换

# 步骤 3：截图各个页面
mcp_xcodebuildmcp_tap { "x": <home_tab_x>, "y": <tab_bar_y> }
mcp_xcodebuildmcp_screenshot

mcp_xcodebuildmcp_tap { "x": <actions_tab_x>, "y": <tab_bar_y> }
mcp_xcodebuildmcp_screenshot

mcp_xcodebuildmcp_tap { "x": <settings_tab_x>, "y": <tab_bar_y> }
mcp_xcodebuildmcp_screenshot
```

**预期结果**：

- 所有页面正确适配深色模式
- 文本可读性良好
- 颜色对比度符合标准

---

## 测试执行流程

### 推荐执行顺序

1. **环境准备**

   - 构建应用
   - 获取初始 UI 结构

2. **基础功能验证**

   - TC-1.1 ~ TC-1.7：Home 页面核心功能

3. **导航验证**

   - TC-2.1 ~ TC-2.3：Tab 导航

4. **设置验证**

   - TC-3.1 ~ TC-3.3：语言设置
   - TC-4.1 ~ TC-4.4：配置管理
   - TC-7.1 ~ TC-7.3：TTS 设置

5. **进阶功能验证**

   - TC-5.1 ~ TC-5.5：Actions 管理
   - TC-6.1 ~ TC-6.5：Providers 管理

6. **边界条件验证**

   - TC-8.1 ~ TC-8.2：错误处理

7. **UI 适配验证**
   - TC-9.1：深色模式

---

## 常用 MCP 命令速查

| 操作          | 命令                                                    |
| ------------- | ------------------------------------------------------- |
| 构建运行      | `mcp_xcodebuildmcp_build_run_sim`                       |
| 截图          | `mcp_xcodebuildmcp_screenshot`                          |
| 获取 UI       | `mcp_xcodebuildmcp_describe_ui`                         |
| 点击（坐标）  | `mcp_xcodebuildmcp_tap { "x": X, "y": Y }`              |
| 点击（label） | `mcp_xcodebuildmcp_tap { "label": "xxx" }`              |
| 输入文本      | `mcp_xcodebuildmcp_type_text { "text": "xxx" }`         |
| 滚动          | `mcp_xcodebuildmcp_gesture { "preset": "scroll-down" }` |
| Home 键       | `mcp_xcodebuildmcp_button { "buttonType": "home" }`     |

---

## 附录

### A. 默认 Actions 详情

| Action             | OutputType    | 特性                    |
| ------------------ | ------------- | ----------------------- |
| Translate          | plain         | 动态 Prompt（目标语言） |
| Sentence Translate | sentencePairs | 结构化输出（句子对）    |
| Grammar Check      | grammarCheck  | 结构化输出 + Diff       |
| Polish             | diff          | Diff 对比显示           |
| Sentence Analysis  | plain         | 动态 Prompt（目标语言） |

### B. 支持的目标语言

| 代码         | 语言         |
| ------------ | ------------ |
| app-language | 匹配应用语言 |
| en           | English      |
| zh-Hans      | 简体中文     |
| ja           | 日本語       |
| ko           | 한국어       |
| fr           | Français     |
| de           | Deutsch      |
| es           | Español      |

### C. Tab Bar 参考坐标（iPhone 17 Pro）

> 注意：坐标可能因设备和 iOS 版本而异，建议始终先调用 `describe_ui` 获取精确坐标

| Tab       | 大致 X 坐标 | 大致 Y 坐标 |
| --------- | ----------- | ----------- |
| Home      | ~50         | ~800        |
| Actions   | ~140        | ~800        |
| Providers | ~230        | ~800        |
| Settings  | ~320        | ~800        |

---

## 版本历史

| 版本 | 日期       | 变更     |
| ---- | ---------- | -------- |
| 1.0  | 2026-01-06 | 初始版本 |
