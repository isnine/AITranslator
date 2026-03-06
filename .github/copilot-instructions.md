# Copilot Instructions

## Build & Lint

```bash
make format         # Auto-format (SwiftFormat)
make lint           # Lint (SwiftLint + SwiftFormat --lint)
make secrets        # Regenerate Secrets.xcconfig from .env
make secrets-check  # Verify secret configuration
```

Build the app with Xcode (scheme **TLingo**, not AITranslator) or via CLI:

```bash
xcodebuild -project AITranslator.xcodeproj -scheme TLingo \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

The project also supports macOS builds. There are no unit test suites to run (only `ShareCoreTests` with a couple of migration/substitution tests). CI runs SwiftFormat lint → SwiftLint → build on every PR.

## Architecture

**TLingo** is a SwiftUI iOS/macOS translation app backed by LLM providers. It ships a system Translation Extension so users can translate from any app.

### Module Dependency Graph

```
TLingo (main app)
  └─► ShareCore (shared framework)
TLingoTranslation (system translation extension)
  └─► ShareCore
```

- **AITranslator/** — Main app entry point + app-only UI (tab navigation, settings, action/provider editors, macOS menu bar, global hotkey).
- **ShareCore/** — All shared business logic: networking (`LLMService`), configuration models, preferences, UI components used by both app and extension. This is an embedded framework target, not a Swift Package.
- **TranslationUI/** — `TranslationUIProviderExtension` entry point. Reuses `ShareCore` views (e.g. `ExtensionCompactView`).
- **Workers/** — Cloudflare Worker proxy (TypeScript) for the built-in cloud service.

### Key Patterns

- **MVVM + Combine** — `HomeViewModel` drives all translation state. Published properties propagate through SwiftUI.
- **App Groups** (`group.com.zanderwang.AITranslator`) — Config and preferences are shared between the main app and the translation extension via `UserDefaults` suite and a shared container.
- **Singleton services** — `AppConfigurationStore.shared`, `LLMService.shared`, `StoreManager.shared`, `AppPreferences.shared` are `@MainActor` singletons.
- **SSE streaming** — `URLSession.bytes(for:)` with incremental JSON parsing (`StreamingSentencePairParser`, `StreamingStructuredOutputParser`).
- **Structured output** — `response_format: json_schema` for sentence-pair and grammar-check actions. Only Azure OpenAI and built-in cloud providers support this.
- **Multi-provider concurrency** — `TaskGroup` sends to multiple LLM providers in parallel and merges results.

### Configuration System

Default actions/providers are bundled as JSON (`DefaultConfiguration.json`). Users can create custom configs stored in the App Group container. `ConfigurationFileManager` watches for file changes and hot-reloads. The extension force-reloads on launch to pick up main-app changes.

**Prompt placeholders**: `{text}`/`{{text}}` → user input, `{targetLanguage}`/`{{targetLanguage}}` → configured target language. Replaced at call time in `LLMService`.

### Authentication

- **Azure OpenAI**: API key in a configurable header (`api-key` or `Authorization`).
- **Built-in cloud**: HMAC-SHA256 signing — `X-Timestamp` + `X-Signature` headers. Secret injected via `BuildEnvironment` (xcconfig → Info.plist → env vars → Secrets.plist fallback).

## Conventions

- **Scheme name**: The app scheme is **TLingo** (not AITranslator). Use this for building and running.
- **Style guide**: Airbnb Swift Style Guide (`docs/Swift Style Guide.md`). Enforced by SwiftFormat (`.swiftformat`) and SwiftLint (`.swiftlint.yml`) — 130 char line width, 4-space indent, LF line endings.
- **Xcode file sync**: The project uses filesystem-synchronized groups. New Swift files placed in the correct directory are auto-included — do **not** manually edit `project.pbxproj` to add file references.
- **Localization**: Modern `.xcstrings` format (`Localizable.xcstrings` at project root). Shared across all targets.
- **Version bumps**: Only update `MARKETING_VERSION`. Do **not** touch `CURRENT_PROJECT_VERSION` — it is managed by Xcode Cloud.
- **Secrets**: Never commit real keys. A pre-commit hook scans for leaked secrets. Use `make gen` for interactive setup or copy `.env.example` to `.env` and run `make secrets`.
- **PR checklist**: Run `make format` + `make lint` before opening a PR. PRs should follow the template in `.github/PULL_REQUEST_TEMPLATE.md`.
- **Minimum deployment**: iOS 18.4+ / macOS 15.4+.

## Where to Make Common Changes

| Task | Key files |
|------|-----------|
| Add/edit a translation action | `ShareCore/Configuration/ActionConfig.swift`, `DefaultConfiguration.json` |
| Add/edit an LLM provider | `ShareCore/Configuration/ProviderConfig.swift`, `ProviderCategory.swift` |
| Change LLM request logic | `ShareCore/Networking/LLMService.swift` |
| Change UI state management | `ShareCore/UI/HomeViewModel.swift` |
| Change config persistence | `ShareCore/Configuration/AppConfigurationStore.swift` |
| Change extension behavior | `TranslationUI/TranslationProvider.swift` |
| Change output types | `ShareCore/Configuration/OutputType.swift` |
| Change preferences | `ShareCore/Preferences/AppPreferences.swift` |
| Change subscriptions | `ShareCore/StoreKit/StoreManager.swift` |
