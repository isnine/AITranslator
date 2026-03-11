# Copilot Instructions for AITranslator

## Project Overview

**AITranslator** is a Swift/SwiftUI iOS/macOS translation application that integrates with the system translation framework. It supports multiple LLM providers (Azure OpenAI, custom OpenAI-compatible APIs) with concurrent requests and streaming responses. The app ships with a system Translation Extension for translating text directly from any app.

**Stack**: SwiftUI, Swift 5.0, iOS 18.4+ / macOS 15.4+, Combine framework

**Build System**: Xcode 16+, SwiftFormat/SwiftLint, Fastlane for App Store automation

---

## Architecture & Module Structure

```
AITranslator (main app)
  └─► ShareCore (shared framework)
TLingoTranslation (system translation extension)
  └─► ShareCore
```

### Module Responsibilities

| Module | Purpose |
|--------|---------|
| **AITranslator/** | Main app entry point + app-only UI (MVVM, tabs: Home/Actions/Providers/Settings, macOS menu bar, global hotkey) |
| **ShareCore/** | Embedded framework with all shared business logic: networking (`LLMService`), configuration models, preferences, UI components used by both app and extension |
| **TranslationUI/** | System translation extension (`TranslationUIProviderExtension`). Reuses `ShareCore` views. Entry: `TranslationProvider.swift` |
| **Workers/** | Cloudflare Worker proxy (TypeScript) for built-in cloud service |

### Key Architectural Patterns

- **MVVM + Combine**: `HomeViewModel` drives translation state; Published properties propagate through SwiftUI
- **App Groups** (`group.com.zanderwang.AITranslator`): Config & preferences shared between main app and extension via `UserDefaults` suite and shared container
- **Singleton Services**: `AppConfigurationStore.shared`, `LLMService.shared`, `StoreManager.shared`, `AppPreferences.shared` — all `@MainActor` singletons
- **SSE Streaming**: `URLSession.bytes(for:)` with incremental JSON parsing (`StreamingSentencePairParser`, `StreamingStructuredOutputParser`)
- **Structured Output**: `response_format: json_schema` for sentence-pair and grammar-check actions (Azure OpenAI & built-in cloud only)
- **Multi-provider Concurrency**: `TaskGroup` sends to multiple LLM providers in parallel, merges results

---

## Build & Development Commands

### Essential Commands

```bash
make gen               # Interactive .env setup wizard (choose endpoint & HMAC secret)
make secrets          # Generate Configuration/Secrets.xcconfig from .env
make secrets-check    # Verify secret configuration
make format           # Auto-format code (SwiftFormat)
make lint             # Lint code (SwiftLint + SwiftFormat --lint)
```

### Building

```bash
# Build main app for iOS Simulator
xcodebuild -project AITranslator.xcodeproj -scheme TLingo \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Build for macOS
xcodebuild -project AITranslator.xcodeproj -scheme TLingo \
  -destination 'platform=macOS' build
```

**Note**: The app scheme is **TLingo** (not AITranslator) — use this for all builds.

### Fastlane Commands (App Store Automation)

```bash
# iOS Screenshots
fastlane ios screenshots              # Capture on all devices/languages
fastlane ios frames                   # Add device frames & marketing text
fastlane ios deliver_screenshots      # Capture → frame → upload
fastlane ios upload_only              # Upload pre-framed screenshots only
fastlane ios full_pipeline            # Full pipeline

# iOS Metadata
fastlane ios download_metadata        # Download from App Store Connect
fastlane ios upload_metadata          # Upload metadata to App Store
fastlane ios release                  # Full release (metadata + screenshots)

# macOS Screenshots
fastlane mac macos_screenshots        # Capture via in-app export
fastlane mac macos_screenshots locale:en-US  # Single locale
fastlane mac macos_frames             # Compose marketing screenshots
fastlane mac macos_full_pipeline      # Full pipeline
```

---

## Configuration System

### Default & Custom Configs

- **Bundled defaults**: `DefaultConfiguration.json` (included in app bundle)
- **Custom configs**: Stored in App Group container, created by users via UI
- **File watching**: `ConfigurationFileManager` detects changes and hot-reloads
- **Extension reload**: Extension force-reloads on launch to pick up main-app changes

### Prompt Placeholders

| Placeholder | Replaced With |
|------------|----------------|
| `{text}` or `{{text}}` | User input text |
| `{targetLanguage}` or `{{targetLanguage}}` | Configured target language |

Replacement happens at request time in `LLMService.swift`.

### Models & Files

- **ActionConfig**: `ShareCore/Configuration/ActionConfig.swift` — name, prompt, usage scenes, output type
- **ProviderConfig**: `ShareCore/Configuration/ProviderConfig.swift` — API credentials, model, base URL
- **OutputType**: `ShareCore/Configuration/OutputType.swift` — plain/diff/sentencePairs/grammarCheck
- **AppConfiguration**: `ShareCore/Configuration/AppConfiguration.swift` — JSON Codable model
- **AppConfigurationStore**: `ShareCore/Configuration/AppConfigurationStore.swift` — singleton repository with file sync

---

## Authentication & Secrets

### Azure OpenAI

- **Header**: API key in configurable header (default: `api-key`, can be `Authorization`)
- **Injection**: Via `Configuration/Base.xcconfig` and `Configuration/Secrets.xcconfig`

### Built-in Cloud Service

- **HMAC-SHA256**: Signed requests with `X-Timestamp` + `X-Signature` headers
- **Secret Injection**:
  1. Local: `make gen` → `.env` file → `make secrets` → `Configuration/Secrets.xcconfig`
  2. Xcode Cloud: Environment variable `AITRANSLATOR_CLOUD_SECRET` → `ci_scripts/ci_post_clone.sh` → `Scripts/inject-secrets.sh` → `Secrets.xcconfig`

### Configuration Files

- **Base.xcconfig**: Unified config for Debug/Release (default endpoint, fallback values)
- **Secrets.xcconfig**: Git-ignored, auto-generated by `inject-secrets.sh`
- **Local.xcconfig.example**: Template for local overrides (copy to `Local.xcconfig`, don't commit)

**Priority order**: Local env vars → `.env` file → `Secrets.xcconfig` → `Base.xcconfig` defaults

---

## Code Style & Quality

### Style Guide

- **Reference**: Airbnb Swift Style Guide (`docs/Swift Style Guide.md`)
- **Line width**: 130 characters max (warning), 160 characters hard error
- **Indentation**: 4 spaces
- **Line endings**: LF only
- **Wrap arguments**: `before-first`
- **Wrap collections**: `before-first`

### Tools

- **SwiftFormat** (`.swiftformat`): Auto-format on save or `make format`
- **SwiftLint** (`.swiftlint.yml`): Opt-in rules (empty_count, empty_string, implicit_return, modifier_order, sorted_imports)
- **Pre-commit hook**: Scans for leaked secrets — never commit real keys

### Excluded Directories

- `build`, `DerivedData`, `.build`, `.swiftpm`, `Carthage`, `Pods`, `Workers`

---

## File Organization & Where to Make Changes

| Task | Key Files |
|------|-----------|
| **Add/edit translation action** | `ShareCore/Configuration/ActionConfig.swift`, `DefaultConfiguration.json` |
| **Add/edit LLM provider** | `ShareCore/Configuration/ProviderConfig.swift`, `ProviderCategory.swift` |
| **Change LLM request logic** | `ShareCore/Networking/LLMService.swift` |
| **Change UI state management** | `ShareCore/UI/HomeViewModel.swift` |
| **Change config persistence** | `ShareCore/Configuration/AppConfigurationStore.swift`, `ConfigurationFileManager.swift` |
| **Change extension behavior** | `TranslationUI/TranslationProvider.swift` |
| **Change output types** | `ShareCore/Configuration/OutputType.swift` |
| **Change preferences** | `ShareCore/Preferences/AppPreferences.swift`, `TargetLanguageOption.swift` |
| **Change subscriptions/StoreKit** | `ShareCore/StoreKit/StoreManager.swift` |
| **Text diff/comparison** | `ShareCore/Utilities/TextDiffBuilder.swift` (LCS algorithm) |
| **App colors & theming** | `ShareCore/AppColors.swift` (adaptive colors) |
| **TTS functionality** | `ShareCore/Networking/TextToSpeechService.swift` |

---

## Project Settings

### Version Management

- **MARKETING_VERSION**: `2.3` (user-facing version) — **ONLY update this**
- **CURRENT_PROJECT_VERSION**: `2` (build number) — **Managed by Xcode Cloud, do not touch**
- **SWIFT_VERSION**: `5.0`
- **iOS Min**: `18.4` (matches IPHONEOS_DEPLOYMENT_TARGET)
- **macOS Min**: `15.4` (matches MACOSX_DEPLOYMENT_TARGET)

**When bumping the app version**:
1. Update `MARKETING_VERSION` only
2. Commit the change
3. Xcode Cloud will auto-increment `CURRENT_PROJECT_VERSION`

### Xcode Project

- **File sync**: Filesystem-synchronized groups — new Swift files placed in the correct directory are auto-included. **Do NOT manually edit `project.pbxproj` to add file references.**

### Localization

- Format: Modern `.xcstrings` (not `Localizable.strings`)
- File: `Localizable.xcstrings` at project root
- Shared across: main app, extension, all targets

---

## CI/CD & Deployment

### GitHub Actions (`.github/workflows/ci.yml`)

Runs on **push to main** and **all pull requests**:
1. Checkout
2. Install swiftlint & swiftformat (via Homebrew)
3. SwiftFormat lint check (`swiftformat --lint .`)
4. SwiftLint (`swiftlint`)
5. Build for iOS Simulator (scheme: AITranslator)

**No unit tests** — only ShareCoreTests (couple of migration/substitution tests).

### Xcode Cloud

- **Post-clone script**: `ci_scripts/ci_post_clone.sh`
  - Calls `Scripts/inject-secrets.sh`
  - Injects `AITRANSLATOR_CLOUD_SECRET` from Xcode Cloud env var into `Configuration/Secrets.xcconfig`
- **Required env vars**: `AITRANSLATOR_CLOUD_SECRET` (mark as Secret in Xcode Cloud)
- **Optional env vars**: `AITRANSLATOR_CLOUD_ENDPOINT`

### Pull Request Workflow

1. Create branch: `git checkout -b feature/your-change`
2. Make changes
3. Format & lint: `make format && make lint`
4. Push & open PR (uses template in `.github/PULL_REQUEST_TEMPLATE.md`)
5. CI checks run automatically
6. Merge when checks pass

---

## Common Workflows

### Setting Up Locally

```bash
cp .env.example .env          # or use `make gen` for interactive setup
make secrets                  # Inject secrets into xcconfig
open AITranslator.xcodeproj
```

### Adding a New Action

1. Edit `ShareCore/Configuration/ActionConfig.swift` to update the model if needed
2. Add action definition to `DefaultConfiguration.json` (or create via UI)
3. Update action prompt placeholder logic in `ShareCore/Networking/LLMService.swift`
4. Test in app Home tab or via extension

### Adding a New LLM Provider

1. Define provider in `ShareCore/Configuration/ProviderConfig.swift`
2. Add category to `ProviderCategory.swift` if needed
3. Implement auth in `LLMService.swift` (Azure OpenAI, custom OpenAI-compatible, etc.)
4. Test via Providers tab in app

### Changing Deployment Target

Edit `Configuration/Base.xcconfig`:
```
IPHONEOS_DEPLOYMENT_TARGET = 18.4
MACOSX_DEPLOYMENT_TARGET = 15.4
```

### Taking macOS Screenshots for App Store

```bash
fastlane mac macos_screenshots            # Capture all locales
fastlane mac macos_frames                 # Frame & add marketing text
fastlane mac upload_macos_screenshots     # Upload to App Store
# Or all in one:
fastlane mac macos_full_pipeline
```

---

## Important Rules

- Do NOT manually edit `project.pbxproj` to add file references — filesystem-synced groups handle this
- Do NOT commit `.env`, `Secrets.xcconfig`, or `Local.xcconfig` files
- Do NOT update `CURRENT_PROJECT_VERSION` — managed by Xcode Cloud
- Run `make format && make lint` before committing
- Use `App Groups` suite for extension ↔ app data sharing

---

## Additional Documentation

- `docs/agent.md` — Detailed architecture & implementation notes (Chinese)
- `docs/macos-screenshots.md` — macOS screenshot pipeline details
- `docs/Swift Style Guide.md` — Swift code style conventions
- `docs/KEY_ROTATION_CHECKLIST.md` — Secret rotation procedures

---

## Quick Reference: Xcode Build Settings

| Setting | Value | Note |
|---------|-------|------|
| SWIFT_VERSION | 5.0 | |
| MARKETING_VERSION | 2.3 | Update only this for version bumps |
| CURRENT_PROJECT_VERSION | 2 | Auto-managed by Xcode Cloud |
| IPHONEOS_DEPLOYMENT_TARGET | 18.4 | iOS minimum |
| MACOSX_DEPLOYMENT_TARGET | 15.4 | macOS minimum |

---

## Troubleshooting

### Build fails with "secrets not set"

Run `make secrets` to regenerate `Configuration/Secrets.xcconfig` from `.env` file.

### Swift format or lint errors on PR

Run locally before pushing:
```bash
make format
make lint
```

### Extension not updating when main app changes

Restart the extension simulator or actual device. The extension force-reloads on launch.

### Xcode Cloud secrets not injected

Verify `AITRANSLATOR_CLOUD_SECRET` is set in Xcode Cloud > Workflows as a **Secret** type variable.

### "TLingo scheme not found"

Make sure you're opening `AITranslator.xcodeproj`, not a package. The scheme is defined in the Xcode project.
