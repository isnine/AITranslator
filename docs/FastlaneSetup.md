# Fastlane 配置与 App Store 元数据管理

> 本文档记录 TLingo 项目的 Fastlane 配置过程，以及 App Store Connect 元数据的本地化管理流程。

## 背景

TLingo 项目原先已有 Fastlane 配置，但仅用于截图自动化（capture → frame → upload）。元数据（描述、关键词、更新日志等）一直是手动在 App Store Connect 网页管理的。

为了：
1. 将元数据纳入版本控制
2. 支持 12 种语言的本地化
3. 实现一键上传元数据到 App Store Connect

我们扩展了 Fastlane 配置，增加了元数据管理能力。

## 完成的工作

### 1. Fastlane 配置重写

**`fastlane/Fastfile`** — 重写后包含：

- **`asc_api_key` 辅助方法**：统一 App Store Connect API Key 认证，密钥文件存放在 iCloud MacConfigs（`AuthKey_Z2LZ4Y87BX.p8`），跨机器通用
- **截图 lanes**（保留原有）：`screenshots`、`frames`、`deliver_screenshots`、`upload_only`、`full_pipeline`
- **元数据 lanes**（新增）：
  - `download_metadata` — 从 App Store Connect 下载元数据到本地
  - `upload_metadata` — 上传本地元数据到 App Store Connect
  - `release` — 完整发布（元数据 + 截图）

**`fastlane/Deliverfile`** — 更新：

- 添加 `metadata_path("./fastlane/metadata")`
- 移除 `skip_metadata(true)` 和 `skip_binary_upload(true)`
- 保留 `app_version("2.0")` 和 `force(true)`

### 2. 元数据目录结构

从 App Store Connect 下载了已有的 4 个语言（en-US、zh-Hans、ja、ko），并新增了 8 个语言的翻译：

```
fastlane/metadata/
├── copyright.txt                     # 全局：版权信息
├── primary_category.txt              # 全局：主分类
├── secondary_category.txt            # 全局：副分类
├── review_information/               # 审核信息
│   ├── email_address.txt
│   ├── first_name.txt
│   ├── last_name.txt
│   └── phone_number.txt
│
├── en-US/                            # 英语（原有）
├── zh-Hans/                          # 简体中文（原有）
├── ja/                               # 日语（原有）
├── ko/                               # 韩语（原有）
├── zh-Hant/                          # 繁體中文（新增）
├── fr-FR/                            # 法语（新增）
├── de-DE/                            # 德语（新增）
├── es-ES/                            # 西班牙语（新增）
├── pt-BR/                            # 巴西葡萄牙语（新增）
├── it/                               # 意大利语（新增）
├── ru/                               # 俄语（新增）
└── ar-SA/                            # 阿拉伯语（新增）
```

每个语言目录包含 10 个文件：

| 文件 | 说明 | 字符限制 |
|------|------|----------|
| `name.txt` | 应用名称 | ≤30 |
| `subtitle.txt` | 副标题 | ≤30 |
| `description.txt` | 应用描述 | ≤4000 |
| `keywords.txt` | 搜索关键词（逗号分隔） | ≤100 |
| `release_notes.txt` | 版本更新说明 | ≤4000 |
| `promotional_text.txt` | 推广文本（可随时更新） | ≤170 |
| `support_url.txt` | 支持链接 | — |
| `marketing_url.txt` | 营销链接 | — |
| `privacy_url.txt` | 隐私政策链接 | — |
| `apple_tv_privacy_policy.txt` | Apple TV 隐私政策 | — |

### 3. 翻译风格

所有翻译遵循以下原则（参照已有的 ja/ko/zh-Hans 翻译质量）：

- **自然营销风格**，非逐字翻译
- **品牌名 "TLingo" 保持不变**
- **技术术语保留英文**：ChatGPT、Claude、AI、GPT、Safari、iPhone、iPad、Mac
- **功能名称本地化**：如 "Polish" → 润色 / 校正 / Korrektur / Pulir 等
- **关键词混合使用**：本地语言搜索词 + 英文技术术语（AI、GPT）
- **段落结构保持一致**：使用 `•` 列表 + `—` 分隔符

### 4. 其他变更

- **`Gemfile`** — 新建，声明 `gem "fastlane"` 依赖
- **`.gitignore`** — 添加 `fastlane/api_key.json`（临时生成的 API Key 文件不应入库）
- **`en-US/keywords.txt`** — 修复原始数据超限问题（101→91 字符，移除 "proofread"）

## 使用方式

### 前置依赖

- **Fastlane**：通过 Homebrew 安装 (`brew install fastlane`)
- **App Store Connect API Key**：`AuthKey_Z2LZ4Y87BX.p8`，存放于 iCloud MacConfigs，详见 MacConfigs README

### 常用命令

```bash
# 上传元数据到 App Store Connect
fastlane ios upload_metadata

# 从 App Store Connect 下载最新元数据
# 需要先生成临时 api_key.json（见下方说明）
fastlane deliver download_metadata --api_key_path ./fastlane/api_key.json

# 完整发布（元数据 + 截图）
fastlane ios release

# 仅上传截图
fastlane ios upload_only
```

### 下载元数据时生成临时 api_key.json

`deliver download_metadata` 子命令不走 Fastfile 的 lane，需要通过 `--api_key_path` 传入 JSON 格式的 key。生成方式：

```bash
# 生成临时文件（注意：用完后删除，不要提交到 git）
cat > fastlane/api_key.json << 'EOF'
{
  "key_id": "Z2LZ4Y87BX",
  "issuer_id": "69a6de8e-b1f0-47e3-e053-5b8c7c11a4d1",
  "key": "<将 AuthKey_Z2LZ4Y87BX.p8 的内容粘贴到这里>",
  "in_house": false
}
EOF

# 执行下载
fastlane deliver download_metadata --api_key_path ./fastlane/api_key.json

# 用完删除
rm fastlane/api_key.json
```

### 添加新语言

1. 在 `fastlane/metadata/` 下创建对应 locale 目录（使用 App Store Connect 的 locale code）
2. 创建上述 10 个 `.txt` 文件，确保遵守字符限制
3. 运行 `fastlane ios upload_metadata` 上传

### 更新元数据

1. 编辑 `fastlane/metadata/<locale>/` 下的对应文件
2. 运行 `fastlane ios upload_metadata` 上传
3. 注意：`promotional_text.txt` 的更新不需要提交新版本审核

## 字符限制验证结果

截至当前，所有 12 个语言均通过字符限制检查：

| Locale | Name | Subtitle | Keywords | Description | Promo |
|--------|------|----------|----------|-------------|-------|
| en-US | 22/30 | 23/30 | 91/100 | 1763/4000 | 160/170 |
| zh-Hans | 13/30 | 10/30 | 49/100 | 620/4000 | 62/170 |
| ja | 13/30 | 12/30 | 51/100 | 761/4000 | 57/170 |
| ko | 15/30 | 16/30 | 50/100 | 844/4000 | 69/170 |
| zh-Hant | 13/30 | 10/30 | 49/100 | 711/4000 | 69/170 |
| fr-FR | 23/30 | 26/30 | 99/100 | 2109/4000 | 162/170 |
| de-DE | 22/30 | 29/30 | 94/100 | 1951/4000 | 167/170 |
| es-ES | 21/30 | 28/30 | 96/100 | 2070/4000 | 162/170 |
| pt-BR | 20/30 | 27/30 | 88/100 | 1873/4000 | 162/170 |
| it | 21/30 | 25/30 | 97/100 | 1975/4000 | 161/170 |
| ru | 22/30 | 23/30 | 89/100 | 1862/4000 | 146/170 |
| ar-SA | 18/30 | 21/30 | 59/100 | 1549/4000 | 133/170 |
