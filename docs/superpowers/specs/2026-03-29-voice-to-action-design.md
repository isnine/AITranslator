# Voice-to-Action Design Spec

Create Actions via voice input with AI-assisted configuration generation.

## Overview

Add a voice entry point to ActionsView that lets users describe an Action in natural language. The system transcribes speech locally via `SFSpeechRecognizer`, sends the text to the cloud API for intent classification, presents ≤3 options for user confirmation, then pre-fills ActionDetailView with the generated configuration.

## User Flow

```
ActionsView [tap 🎙️]
  → Permission check (first time only)
  → Recording Overlay (toggle mode, real-time transcription)
    → [tap "完成"]
  → AI Intent Confirmation (≤3 option cards)
    → [select option + confirm]
  → ActionDetailView (pre-filled by AI, user reviews & saves)
```

### Phase 1 — Voice Entry

- 🎙️ button placed next to the existing "+" button in ActionsView header
- Visually prominent: gradient background (accent color), same size as "+"
- On tap: check microphone + speech recognition permissions before opening overlay (see Permissions section)

### Phase 2 — Recording (Toggle Mode)

**State machine:**

```
idle ──[tap 🎙️ + permissions granted]──► recording
recording ──[tap "完成"]──► processing
recording ──[tap "取消"]──► idle
recording ──[app backgrounded]──► paused
paused ──[app foregrounded within 30s]──► recording (resume)
paused ──[app foregrounded after 30s]──► idle (auto-cancel, show toast)
processing ──[transcript empty]──► idle (show "未检测到语音" toast)
processing ──[transcript non-empty]──► Phase 3
```

- Animated microphone icon with pulse effect indicates active recording
- Real-time transcription displayed below the mic icon via `SFSpeechRecognizer`
- Button debounce: ignore taps within 300ms of previous tap to prevent double-triggers
- No cloud fallback — Apple STT only

### Phase 3 — AI Intent Confirmation

After recording ends, the transcribed text is sent to the cloud API (`/voice-to-action` endpoint). The API returns 2–3 structured options.

**Option card structure:**
- Icon + title
- Short description
- Last option is always "自定义描述" with a text input field

**User interaction:**
- Tap to select an option (single-select, radio-style)
- For the custom option, user types their own description (max 500 characters)
- Tap "确认并生成" to proceed
- Custom input uses the **same** `/voice-to-action` endpoint with the user's text as the new `transcript`

**Locale resolution:** Use `Locale.current.language.languageCode?.identifier ?? "en"` (the device's current language, not the app's target translation language).

**API request:**
```json
{
  "transcript": "我想要一个动作，可以把文本翻译成日语，用敬语的表达方式",
  "locale": "zh-Hans"
}
```

**API response:**
```json
{
  "options": [
    {
      "title": "日语敬语翻译",
      "description": "翻译为日语，使用です/ます体敬语",
      "action_config": {
        "name": "日语敬語翻訳",
        "prompt": "Translate the following text into Japanese using polite form (です/ます体)...\n\n\"{text}\"",
        "output_type": "plain",
        "usage_scenes": ["app", "contextRead", "contextEdit"]
      }
    },
    {
      "title": "日语商务翻译",
      "description": "翻译为正式商务日语，含敬称和谦让语",
      "action_config": {
        "name": "日语商务翻译",
        "prompt": "Translate the following text into formal business Japanese...\n\n\"{text}\"",
        "output_type": "plain",
        "usage_scenes": ["app", "contextRead", "contextEdit"]
      }
    }
  ],
  "allow_custom_input": true
}
```

**Note:** The API response does NOT include `id` — the client generates a new `UUID` when constructing the `ActionConfig`. The `output_type` field is a string matching `OutputType.rawValue` ("plain", "diff", "sentencePairs", "grammarCheck"). The `usage_scenes` field is an array of strings matching `UsageScene` cases.

### Phase 4 — ActionDetailView Pre-fill

- Navigate to ActionDetailView with the selected `action_config` pre-populated (new UUID generated client-side)
- All fields editable: name, prompt, outputType, usageScenes
- Subtle banner at bottom: "✨ 由 AI 生成 · 请检查后保存"
- Banner is session-scoped: visible until user saves or dismisses the action. Not persisted.
- Standard save/cancel flow — no new UI components needed
- **One-way flow**: dismissing ActionDetailView without saving discards the AI-generated config. User must re-record if they want to start over.

## Architecture

### New Files

| File | Module | Purpose |
|------|--------|---------|
| `VoiceActionService.swift` | ShareCore/Networking | Cloud API client for `/voice-to-action` endpoint |
| `SpeechRecognitionService.swift` | ShareCore/Networking | `SFSpeechRecognizer` wrapper with real-time transcription |
| `VoiceRecordingView.swift` | AITranslator/UI | Recording overlay UI (Phase 2) |
| `VoiceIntentConfirmationView.swift` | AITranslator/UI | Option selection UI (Phase 3) |

### Modified Files

| File | Change |
|------|--------|
| `ActionsView.swift` | Add 🎙️ button in header, navigation to voice flow |
| `ActionDetailView.swift` | Accept optional pre-filled `ActionConfig` + `isAIGenerated` flag, show AI banner, UI polish |
| `Info.plist` | Add `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` |

### Data Flow

```
SpeechRecognitionService (local)
  ├── AVAudioEngine (capture)
  └── SFSpeechRecognizer (transcribe)
        ↓ transcript: String
VoiceActionService (cloud)
  ├── POST /voice-to-action (CloudAuthHelper signs request)
  └── Response: VoiceActionResponse (options array)
        ↓ selected option
Client constructs ActionConfig (new UUID + option fields)
        ↓
ActionDetailView (pre-filled)
  └── AppConfigurationStore.updateActions() on save
```

### SpeechRecognitionService

```swift
class SpeechRecognitionService: NSObject, ObservableObject {
    enum State { case idle, recording, paused, processing }

    @Published var transcript: String = ""
    @Published var state: State = .idle
    @Published var error: SpeechError?

    func requestAuthorization() async -> Bool
    func startRecording() throws
    func stopRecording()
    func cancelRecording()
}
```

- Uses `AVAudioEngine` for audio capture
- `SFSpeechAudioBufferRecognitionRequest` for real-time results
- Updates `transcript` on each partial result via `@MainActor`-isolated handlers
- Class itself is NOT `@MainActor` — follows `TTSPreviewService` pattern (NSObject + ObservableObject)
- Subscribes to `UIApplication.didEnterBackgroundNotification` / `willEnterForegroundNotification` for pause/resume

### VoiceActionService

```swift
final class VoiceActionService {
    struct VoiceActionOption: Codable, Identifiable {
        let id = UUID()   // client-generated
        let title: String
        let description: String
        let actionConfig: PartialActionConfig

        private enum CodingKeys: String, CodingKey {
            case title, description
            case actionConfig = "action_config"
        }
    }

    /// Minimal config from API (no id — client generates UUID)
    struct PartialActionConfig: Codable {
        let name: String
        let prompt: String
        let outputType: String    // "plain" | "diff" | "sentencePairs" | "grammarCheck"
        let usageScenes: [String] // ["app", "contextRead", "contextEdit"]

        private enum CodingKeys: String, CodingKey {
            case name, prompt
            case outputType = "output_type"
            case usageScenes = "usage_scenes"
        }

        func toActionConfig() -> ActionConfig {
            ActionConfig(
                id: UUID(),
                name: name,
                prompt: prompt,
                usageScenes: UsageScene(from: usageScenes),
                outputType: OutputType(rawValue: outputType) ?? .plain
            )
        }
    }

    struct VoiceActionResponse: Codable {
        let options: [VoiceActionOption]
        let allowCustomInput: Bool

        private enum CodingKeys: String, CodingKey {
            case options
            case allowCustomInput = "allow_custom_input"
        }
    }

    func generateOptions(transcript: String, locale: String) async throws -> VoiceActionResponse
}
```

- NOT `@MainActor` — follows `LLMService` / `TTSPreviewService` pattern
- Authenticated via `CloudAuthHelper` (same pattern as existing services)
- Single REST endpoint, no streaming needed

### Cloud Worker Endpoint

New route in the Cloudflare Worker:

```
POST /voice-to-action
```

**Behavior:**
- Receives transcript + locale
- Calls Azure OpenAI (`gpt-4o-mini` for cost efficiency) with a system prompt
- System prompt instructs the model to return 2–3 ActionConfig options as structured JSON
- Returns JSON matching `VoiceActionResponse` schema
- Timeout: 10 seconds. On timeout, returns HTTP 504.

**Error responses:**
```json
// HTTP 400 — invalid request
{ "error": "transcript is required" }

// HTTP 500 — upstream LLM failure
{ "error": "Failed to generate options", "detail": "Azure OpenAI timeout" }

// HTTP 504 — request timeout
{ "error": "Request timed out" }
```

**Fallback behavior (client-side):** If the API returns an empty `options` array, the client constructs a single fallback option:
```swift
VoiceActionOption(
    title: "基本翻译动作",
    description: "基于你的描述创建的翻译动作",
    actionConfig: PartialActionConfig(
        name: "自定义动作",
        prompt: "Based on the user's request: \"\(transcript)\"\n\nTranslate \"{text}\" to {targetLanguage}.",
        outputType: "plain",
        usageScenes: ["app", "contextRead", "contextEdit"]
    )
)
```
This fallback is always paired with the custom input option.

## Permissions

Add to `AITranslator/Info.plist`:
- `NSSpeechRecognitionUsageDescription`: "TLingo uses speech recognition to create translation actions from your voice."
- `NSMicrophoneUsageDescription`: "TLingo needs microphone access to record your voice for creating actions."

These are **not** needed in the extension's Info.plist — voice-to-action is main app only.

**Permission request flow:**

1. User taps 🎙️ button in ActionsView
2. `SpeechRecognitionService.requestAuthorization()` checks both `SFSpeechRecognizer.authorizationStatus()` and `AVAudioSession.recordPermission`
3. If either not determined → system prompts user (iOS handles the alert)
4. If either denied → show custom alert: "需要麦克风和语音识别权限" with "前往设置" button (opens `UIApplication.openSettingsURLString`)
5. If both authorized → open recording overlay

## UI Polish for ActionDetailView

As part of this feature, improve ActionDetailView readability:
- Clearer section labels (uppercase, smaller font)
- Collapsible sections default to expanded when `isAIGenerated` flag is true (so user sees all fields)
- Output type and usage scenes use more descriptive labels, not just enum names
- AI-generated banner is session-scoped (visible until save or dismiss, not persisted)

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Microphone permission denied | Show alert with "前往设置" button before opening overlay |
| Speech recognition permission denied | Same alert as above (both permissions checked together) |
| Speech recognition unavailable on device | Show alert: "此设备不支持语音识别", suggest typing manually via "+" |
| Recording produces empty transcript | Show toast "未检测到语音，请重试", return to idle |
| Network error on API call | Show retry button in confirmation view + "手动创建" link to copy transcript and use "+" |
| API returns empty options | Client-side fallback option (see Cloud Worker section) + custom input |
| API returns HTTP 4xx/5xx | Show error message from response body + retry button |
| App backgrounded during recording | Pause recording, resume if foregrounded within 30s, auto-cancel otherwise |

## Scope Boundaries

**In scope:**
- Voice button in ActionsView
- Recording overlay with real-time transcription
- AI option selection (≤3 options + custom)
- Pre-fill ActionDetailView
- Cloud worker endpoint
- Permission handling
- ActionDetailView UI polish

**Out of scope:**
- Voice input in the extension (main app only)
- Voice editing of existing actions
- Multi-turn voice conversation
- Azure STT fallback (Apple-only)
- Streaming API response for option generation
- Back-navigation from ActionDetailView to intent confirmation (one-way flow)
