# AITranslator

## Overview

AITranslator is an iOS 18+ companion app built with SwiftUI that augments the system-wide translation experience. It registers a `TranslationUIProvider` extension so that, whenever users highlight text and tap the system translation button, they can run customizable LLM-powered actions (translate, summarize, analyze tone, code review, etc.). The host app serves as the configuration console: it manages actions, connects to OpenAI-compatible providers (OpenAI, Azure OpenAI, local gateways), and guides users through setting AITranslator as the default translation app in iOS Settings.

## Project Structure

- `AITranslator/` – SwiftUI app target; will host onboarding, provider configuration, and action management UI.
- `TranslationUI/` – `TranslationUIProvider` extension target executed from the system translation sheet; currently contains the placeholder `TranslationProviderView`.
- `AITranslator.xcodeproj` – Xcode project with SwiftUI lifecycle and ExtensionKit integration.
- (_Note_) `TranslationU/` mirrors the starter extension template and can be cleaned up once the `TranslationUI` target is fully in use.

## Core Scenarios

1. Configure OpenAI-compatible endpoints and store API credentials securely.
2. Define reusable “actions” with prompts, output expectations, and which providers to fan out to.
3. Assign one action as the default so the extension can execute it immediately for selected text.
4. Allow users to swap actions on the fly inside the translation sheet, with results streamed from each configured provider.
5. Provide first-run guidance so users enable AITranslator in **Settings ▸ Translate ▸ Default App** (name may change in final iOS builds).

## Main App (Configuration Console)

- **Action Library** – list, create, clone, archive actions; each action stores a display name, prompt template, optional formatting hints, and post-processing rules (e.g., replace original text automatically).
- **Provider Connectors** – capture base URL, API key/token, model/engine ID, Azure resource name/deployment name, timeout, max tokens, and optional per-provider instructions; allow multiple connectors and mark them active/inactive.
- **Routing Rules** – per action, pick one or more providers and specify execution mode (`sequential`, `parallel`, or `first-success`), plus retry limits.
- **Onboarding & Status** – walk users through enabling the extension, verifying connectivity (test call), and checking entitlement status; surface health indicators (last latency, error counts).
- **Persistence** – plan to store configuration in AppStorage/CoreData; secrets should live in Keychain with iCloud Keychain sync opt-in.

## Translation Extension (TranslationUIProvider)

- Entry point: `TranslationProviderExtension` with `TranslationUIProviderSelectedTextScene` producing `TranslationProviderView`.
- Responsibilities:
  - Read `TranslationUIProviderContext` (input text, locale hints, replacement permissions).
  - Run the default action immediately on appearance; show progress indicator and streamed results.
  - Offer UI to switch actions; when user selects another action, dispatch requests to all mapped providers and aggregate responses.
  - Support replacement flow via `context.finish(replacingWithTranslation:)` or `context.expandSheet()` for rich output.
  - Handle offline/errors gracefully, surfacing provider-specific diagnostics and fallback suggestions.
- UI Considerations:
  - Compact vertical layout that respects attributed source text.
  - Tabs/segmented control for actions and nested chips for provider results.
  - Option to copy results, share, or send back to main app for deeper processing.

## Action Execution Pipeline

1. Extension receives text and reads current configuration from shared App Group storage.
2. Determine target action (default or user-selected) and hydrate prompt using templates/variables (language, app name, etc.).
3. Build provider-specific payloads (OpenAI `chat.completions`, Azure `deployments/{id}/chat/completions`, etc.).
4. Execute requests according to action routing rules; stream partial results when supported.
5. Aggregate outputs (per provider with metadata), apply post-processing (e.g., Markdown rendering, text cleanup), then render UI and optionally replace source text.

## Provider Configuration Requirements

- Support any OpenAI-compatible API by letting users specify:
  - Base URL (e.g., `https://api.openai.com/v1`, `https://your-resource.openai.azure.com/openai/deployments/...`).
  - HTTP headers (Authorization bearer token, optional custom headers for Azure `api-key`, `api-version` query).
  - Model/deployment name per provider.
  - Default system prompt and temperature/top_p settings.
  - Streaming toggle.
- Allow multiple credentials; group them by vendor and expose quick reachability test.
- Consider optional provider types (DeepSeek, Anthropic-compatible proxies) by keeping schema flexible.

## Data & Security

- Use a dedicated App Group container for sharing action definitions between app and extension.
- Store tokens and secrets in the Keychain (per-provider IDs reference Keychain items).
- Provide clear privacy messaging: text snippets are sent to configured providers; encourage enterprise users to point to private endpoints.

## UX Blueprint

- **Home Screen** – summary of default action, quick toggles (enable/disable extension), last run stats.
- **Actions Detail** – editable prompt template with SwiftUI form, preview of how variables resolve, provider selection matrix, default toggle.
- **Provider Detail** – connection form, test button, result log.
- **Guided Setup** – stepper showing: grant extension, choose default, add provider, create action.
- **Extension Sheet** – top area with source text snippet, central card with action picker, accordion for provider responses, bottom bar with “Replace”, “Copy”, “Run different action”.

## Implementation Roadmap

- **Milestone 1 – Configuration Foundation**
  - Build settings data models, Keychain helpers, and SwiftUI forms.
  - Implement App Group persistence and live preview of prompts.
  - Ship onboarding checklist.
- **Milestone 2 – Provider SDK Layer**
  - Abstract OpenAI-compatible API client with streaming support.
  - Add concurrency control, caching, and error taxonomy.
  - Write unit tests using mocked URLProtocols.
- **Milestone 3 – Extension MVP**
  - Replace placeholder `TranslationProviderView` with production UI.
  - Load configuration from shared storage, run default action, display results.
  - Handle replacement flow and fallbacks.
- **Milestone 4 – Polishing**
  - Add analytics/telemetry (opt-in), crash diagnostics, localization.
  - Fine-tune accessibility (Dynamic Type, VoiceOver).
  - Prepare TestFlight builds and documentation.

## Testing Strategy

- Unit tests for prompt templating, provider clients, and configuration persistence.
- UI tests for the main app forms and guided setup.
- Extension integration tests using XCTest with injected mock providers.
- Manual regression around switching default actions, offline scenarios, and Settings toggles.

## References

- Apple Developer Documentation – [Preparing your app to be the default translation app](https://developer.apple.com/documentation/TranslationUIProvider/Preparing-your-app-to-be-the-default-translation-app)
- Apple Translation framework docs – `translationPresentation`, `translationTask`, `TranslationSession.Configuration`.
- WWDC24 materials (Translation UI Provider) for latest UX and entitlement requirements.
