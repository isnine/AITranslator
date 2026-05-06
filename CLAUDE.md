# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AITranslator (app name: **TLingo**) is a Swift/SwiftUI iOS/macOS translation app that integrates with the system translation framework. It supports multiple LLM providers (Azure OpenAI, custom OpenAI-compatible APIs) with concurrent requests and streaming responses.

**Stack**: SwiftUI, Swift 5.0, iOS 18.4+ / macOS 15.4+, Combine, Xcode 16+

## Architecture

```
TLingo (main app)
  └─► ShareCore (shared framework)
TLingoTranslation (system translation extension)
  └─► ShareCore
```

| Module | Purpose |
|--------|---------|
| **AITranslator/** | Main app — MVVM UI layer (tabs: Home/Actions/Providers/Settings), macOS menu bar, global hotkey, clipboard monitor |
| **ShareCore/** | Embedded framework — all shared business logic: networking (`LLMService`), configuration models, preferences, StoreKit, UI components. ~56 Swift files |
| **TranslationUI/** | System translation extension (`TranslationProvider.swift`). Reuses ShareCore views |
| **Workers/** | Cloudflare Worker proxy (TypeScript) for built-in cloud service |

### Backend Infrastructure

- **LLM / GPT calls**: Proxied through a Cloudflare Worker (`Workers/azureProxyWorker.ts`) that forwards to Azure OpenAI endpoints. The Worker handles HMAC auth validation, model routing, and SSE streaming relay. Uses AI Gateway from Istio Foundation scripts for request management.
- **Actions Marketplace**: Runs entirely on Cloudflare — the Worker handles CRUD for marketplace actions, backed by a Cloudflare D1 (SQLite) database. Endpoint: `CloudServiceConstants.marketplaceEndpoint` (`translator-api.zanderwang.com`). The marketplace endpoint is separate from the Azure proxy endpoint (`CloudServiceConstants.endpoint`).

### Key Patterns

- **MVVM + Combine**: `HomeViewModel` drives translation state via Published properties
- **App Groups** (`group.com.zanderwang.AITranslator`): Config & preferences shared between app and extension via `UserDefaults` suite and shared container
- **Singleton Services**: `AppConfigurationStore.shared`, `LLMService.shared`, `StoreManager.shared`, `AppPreferences.shared` — all `@MainActor`
- **SSE Streaming**: `URLSession.bytes(for:)` with incremental JSON parsing (`StreamingSentencePairParser`, `StreamingStructuredOutputParser`)
- **Structured Output**: `response_format: json_schema` for sentence-pair and grammar-check actions
- **Multi-provider Concurrency**: `TaskGroup` sends to multiple providers in parallel, merges results
- **Filesystem-synced groups**: New Swift files placed in the correct directory are auto-included. **Do NOT manually edit `project.pbxproj` to add file references**

## Essential Commands

### Building

The app scheme is **TLingo** (not AITranslator):

```bash
# Build for iOS Simulator
xcodebuild -project AITranslator.xcodeproj -scheme TLingo \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Build for macOS
xcodebuild -project AITranslator.xcodeproj -scheme TLingo \
  -destination 'platform=macOS' build
```

### Make Targets

```bash
make gen               # Interactive .env setup wizard
make secrets           # Generate Configuration/Secrets.xcconfig from .env
make secrets-check     # Verify secret configuration
make format            # Auto-format code (SwiftFormat)
make lint              # Lint code (SwiftLint + SwiftFormat --lint)
```

### Testing

Minimal unit tests in ShareCoreTests (migration/substitution tests). Primary testing uses MCP-based UI automation.

### App Store Connect (asc CLI)

Metadata, builds, and submissions are managed via the `asc` CLI. Canonical metadata lives in `metadata/{ios,macos}/`.

```bash
# Pull current metadata from ASC
asc metadata pull --app 6754217103 --version 3.1 --platform IOS --dir metadata/ios --force
asc metadata pull --app 6754217103 --app-info 7726c983-1526-480d-a629-419d70e657fe \
  --version 3.0 --platform MAC_OS --dir metadata/macos --force

# Push edits back (use --dry-run first)
asc metadata push --app 6754217103 --version 3.1 --platform IOS --dir metadata/ios --dry-run
asc metadata push --app 6754217103 --version 3.1 --platform IOS --dir metadata/ios

# Screenshots (still captured locally under screenshots/)
Scripts/capture_screenshots.sh           # iOS Simulator capture
Scripts/capture_screenshots_ipad.sh      # iPad capture
Scripts/capture_macos_screenshots_self.sh  # macOS in-app capture
Scripts/frame_macos_marketing.sh         # Compose marketing frames
asc screenshots upload --app 6754217103 --dir screenshots/...  # Upload to ASC
```

## Configuration System

- **Bundled defaults**: `ShareCore/Resources/DefaultConfiguration.json` (5 built-in actions)
- **Custom configs**: Stored in App Group container, created by users via UI
- **File watching**: `ConfigurationFileManager` detects changes and hot-reloads
- **Prompt placeholders**: `{text}`/`{{text}}` and `{targetLanguage}`/`{{targetLanguage}}` — replaced at request time in `LLMService.swift`

### Secrets & Build Config

- **Base.xcconfig**: Unified Debug/Release config (default endpoint, fallback values)
- **Secrets.xcconfig**: Git-ignored, generated by `make secrets` or `Scripts/inject-secrets.sh`
- **Priority**: Local env vars → `.env` file → `Secrets.xcconfig` → `Base.xcconfig` defaults
- **Xcode Cloud**: `ci_scripts/ci_post_clone.sh` injects `AITRANSLATOR_CLOUD_SECRET` env var → `Secrets.xcconfig`
- Do NOT commit `.env`, `Secrets.xcconfig`, or `Local.xcconfig`

## Where to Make Changes

| Task | Key Files |
|------|-----------|
| Add/edit translation action | `ShareCore/Configuration/ActionConfig.swift`, `DefaultConfiguration.json` |
| Add/edit LLM provider | `ShareCore/Configuration/ProviderConfig.swift`, `ProviderCategory.swift` |
| Change LLM request logic | `ShareCore/Networking/LLMService.swift` |
| Change UI state management | `ShareCore/UI/HomeViewModel.swift` |
| Change config persistence | `ShareCore/Configuration/AppConfigurationStore.swift`, `ConfigurationFileManager.swift` |
| Change extension behavior | `TranslationUI/TranslationProvider.swift` |
| Change preferences | `ShareCore/Preferences/AppPreferences.swift` |
| Change subscriptions/StoreKit | `ShareCore/StoreKit/StoreManager.swift` |
| Text diff/comparison | `ShareCore/Utilities/TextDiffBuilder.swift` |
| App colors & theming | `ShareCore/AppColors.swift` |
| TTS functionality | `ShareCore/Networking/TTSPreviewService.swift` |
| Marketplace UI | `AITranslator/UI/MarketplaceView.swift`, `MarketplaceActionDetailView.swift`, `PublishActionView.swift` |
| Marketplace service | `ShareCore/Marketplace/MarketplaceService.swift`, `MarketplaceAction.swift` |
| Marketplace Worker API | `Workers/azureProxyWorker.ts` (routes under `/marketplace/` and `/web/api/`) |
| Marketplace Web UI | `Workers/azureProxyWorker.ts` (route `/web`, inline SPA) |

## Code Style

- **Style guide**: Airbnb Swift Style Guide (`docs/Swift Style Guide.md`)
- **SwiftFormat** (`.swiftformat`): 4-space indent, LF line endings, `before-first` wrapping, 130 char max width
- **SwiftLint** (`.swiftlint.yml`): Opt-in rules: `empty_count`, `empty_string`, `implicit_return`, `modifier_order`, `sorted_imports`. Line length warning at 130, error at 160
- Run `make format && make lint` before committing

## Localization

- Format: Modern `.xcstrings` (not `Localizable.strings`)
- File: `Localizable.xcstrings` at project root, shared across all targets
- 16+ locales: en, ar, da, de, es, fr, id, it, ja, ko, nb, nl, pt-BR, sv, tr, zh-Hans, zh-Hant

## Version Management

- **MARKETING_VERSION**: Update only this for version bumps
- **CURRENT_PROJECT_VERSION**: Managed by Xcode Cloud — do not modify
- The project uses XcodeBuildMCP for AI-assisted development

## CI/CD

GitHub Actions (`.github/workflows/ci.yml`) runs on push to main and all PRs:
1. SwiftFormat lint check
2. SwiftLint
3. Build for iOS Simulator

## Code Change Guidelines

- Before committing, verify that ONLY the files you intentionally modified are staged. Run `git diff --cached --name-only` and confirm with the user if more than the expected files are included.
- When fixing a UI bug, identify ALL views where the affected component appears (list view, detail view, macOS, iOS) before implementing. Ask the user which views need fixing if unclear.
- When modifying existing UI elements (subtitles, labels, footers), COMBINE new content with existing content rather than replacing it, unless explicitly told to replace.
- After making UI or code changes, verify cross-platform compilation for both iOS Simulator and macOS targets before committing. Report any platform-specific errors.
- Before implementing a feature, check `git log --oneline -20 main` to see if it already exists on the main branch to avoid duplicate work.
- When the user specifies a threshold, value, or specific requirement, repeat it back before implementing. Do not silently adjust values.

## Additional Documentation

- `docs/agent.md` — Detailed architecture & implementation notes (Chinese)
- `docs/marketplace-web-api.md` — Marketplace Web API reference (endpoints, auth, data model, deployment)
- `docs/macos-screenshots.md` — macOS screenshot pipeline
- `docs/Swift Style Guide.md` — Code style conventions
- `docs/KEY_ROTATION_CHECKLIST.md` — Secret rotation procedures
