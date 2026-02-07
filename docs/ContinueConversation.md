# Continue Conversation Feature Design

## Overview

Allow users to continue iterating on a translation/action result by entering a chat-like conversation with the LLM. Each model result card gets an independent "continue conversation" button that opens a dedicated chat interface.

## Core Decisions

- **Per-card independent conversation**: Each model result card has its own chat button. Conversation is 1:1 with that specific model.
- **Full/half-screen sheet**: Tapping the button opens a `.sheet` with conversation history and input bar.
- **macOS menu bar simplified**: Menu bar popover only shows the button; clicking it opens the main app.
- **Conversations are ephemeral**: Not persisted to disk. Closing the sheet destroys the session.

## Interaction Flow

```
Result Card [copy] [chat]
                    |
                    v  tap
Sheet / FullScreen Conversation View
+-------------------------------------+
|  <- Back           GPT-4.1 Nano     |  nav bar with model name
|------------------------------------- |
|  +- System Prompt > -------------+  |  collapsed by default
|  +-------------------------------+  |
|                                      |
|                  +-----------------+ |
|                  | Hello            | |  user bubble (right-aligned)
|                  +-----------------+ |
|                                      |
|  +-------------------------------+  |
|  | text (selectable)              |  |  assistant bubble (left-aligned)
|  |-------------------------------|  |
|  |                        [copy]  |  |  copy button at bottom-right
|  +-------------------------------+  |
|                                      |
|                  +-----------------+ |
|                  | make it formal   | |  user follow-up
|                  +-----------------+ |
|                                      |
|  +-------------------------------+  |
|  | streaming...                   |  |  new assistant reply (streaming)
|  |-------------------------------|  |
|  |                        [copy]  |  |
|  +-------------------------------+  |
|                                      |
|--------------------------------------|
|  +---------------------------+ [>]   |  input bar
|  | Type follow-up...         |       |
|  +---------------------------+       |
+--------------------------------------+
```

## Platform Adaptation

| Platform            | Presentation               | Notes                                    |
|---------------------|-----------------------------|------------------------------------------|
| iPhone main app     | `.sheet` with `.presentationDetents([.medium, .large])` | Swipe up to expand         |
| iPhone Extension    | `.sheet` with `.presentationDetents([.medium, .large])` | Same, space-constrained    |
| macOS main app      | `.sheet` (centered popup)   | Standard macOS sheet behavior             |
| macOS menu bar      | Button only, opens main app | Uses `NSWorkspace.shared.open(url)` or activates main window |

## Button Design

Added to each result card's action buttons group, after the copy button:

```
[eye] [speaker] [copy] [chat]
                         ^
              SF Symbol: "text.bubble"
              Same style: 13-14pt, accent color
              Only visible in .success state
```

## Message Bubble Design

| Role       | Alignment | Background                     | Text Selection            | Copy Button | Notes                    |
|------------|-----------|--------------------------------|---------------------------|-------------|--------------------------|
| `system`   | Center    | Transparent / very light gray  | No                        | No          | Collapsed by default, "System Prompt >" tap to expand |
| `user`     | Right     | `accent.opacity(0.15)`         | `.textSelection(.enabled)` | No         | User's own text          |
| `assistant`| Left      | `colors.cardBackground`        | `.textSelection(.enabled)` | Yes, bottom-right `doc.on.doc` | Streaming animation while generating |

## Data Models

### ChatMessage

```swift
public struct ChatMessage: Identifiable {
    public let id: UUID
    public let role: String           // "system", "user", "assistant"
    public let content: String
    public let timestamp: Date
}
```

### ConversationSession

```swift
public struct ConversationSession: Identifiable {
    public let id: UUID
    public let model: ModelConfig
    public let action: ActionConfig
    public var messages: [ChatMessage]
    public var isStreaming: Bool = false
    public var streamingText: String = ""
}
```

## Session Initialization

When user taps the chat button, a `ConversationSession` is created from:

1. The action's system prompt (if present and not containing `{text}` placeholder)
2. The user's original input text (as `user` message)
3. The model's response (as `assistant` message)

```swift
func createConversation(from run: ModelRunViewState,
                        action: ActionConfig,
                        inputText: String) -> ConversationSession {
    var messages: [ChatMessage] = []

    // 1. System prompt
    if !action.prompt.isEmpty {
        let processed = substitutePromptPlaceholders(action.prompt, text: inputText)
        let hasTextPlaceholder = action.prompt.contains("{text}") || action.prompt.contains("{{text}}")
        if !hasTextPlaceholder {
            messages.append(ChatMessage(role: "system", content: processed))
        }
    }

    // 2. User input
    messages.append(ChatMessage(role: "user", content: inputText))

    // 3. Assistant response
    if case .success(_, let copyText, _, _, _, _) = run.status {
        messages.append(ChatMessage(role: "assistant", content: copyText))
    }

    return ConversationSession(model: run.model, action: action, messages: messages)
}
```

## Network Layer

New method in `LLMService` that accepts full message history:

```swift
public func sendContinuation(
    messages: [LLMRequestPayload.Message],
    model: ModelConfig,
    partialHandler: @escaping (String) -> Void
) async throws -> String
```

Differences from existing `sendModelRequest`:
- Accepts pre-built `messages` array instead of constructing from action + text
- No `response_format` (structured output not needed for follow-up conversation)
- Single model only (no concurrent multi-model dispatch)
- Streaming always enabled

## PasteboardHelper

Cross-platform clipboard utility to unify copy logic:

```swift
public enum PasteboardHelper {
    public static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }
}
```

## File Changes

| File | Change | Description |
|------|--------|-------------|
| **NEW** `ShareCore/Utilities/PasteboardHelper.swift` | Add | Cross-platform clipboard helper |
| **NEW** `ShareCore/UI/Conversation/ChatMessage.swift` | Add | Message data model |
| **NEW** `ShareCore/UI/Conversation/ConversationSession.swift` | Add | Session data model |
| **NEW** `ShareCore/UI/Conversation/ConversationViewModel.swift` | Add | ViewModel for conversation |
| **NEW** `ShareCore/UI/Conversation/ConversationView.swift` | Add | Main conversation view |
| **NEW** `ShareCore/UI/Conversation/MessageBubbleView.swift` | Add | Chat bubble component |
| **NEW** `ShareCore/UI/Conversation/ConversationInputBar.swift` | Add | Bottom input bar |
| **MOD** `ShareCore/UI/Components/ProviderResultCardView.swift` | Modify | Add chat button to `ResultActionButtons` |
| **MOD** `ShareCore/UI/HomeView.swift` | Modify | Add chat button + `.sheet` presentation |
| **MOD** `ShareCore/UI/HomeViewModel.swift` | Modify | Add `createConversation()`, store action/inputText |
| **MOD** `ShareCore/UI/ExtensionCompactView.swift` | Modify | Support conversation sheet |
| **MOD** `AITranslator/MenuBarPopoverView.swift` | Modify | Simplified: button opens main app |
| **MOD** `ShareCore/Networking/LLMService.swift` | Modify | Add `sendContinuation()` method |

## Key Constraints

1. **No persistence**: Conversations are in-memory only, destroyed on sheet dismiss
2. **Single model**: Follow-up messages go to one specific model, not concurrent multi-model
3. **Original results unchanged**: The result cards in the main view remain as-is
4. **Streaming**: Follow-up responses use SSE streaming, consistent with existing UX
5. **No structured output**: Continuation responses are plain text (no JSON Schema / response_format)
