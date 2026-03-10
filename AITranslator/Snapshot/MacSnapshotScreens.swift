#if os(macOS)
import ShareCore
import SwiftUI

enum MacSnapshotScreen {
    case home
    case conversation
    case actions
    case models
    case settings

    static func fromLaunchArguments(_ args: [String]) -> MacSnapshotScreen {
        if args.contains("-SNAPSHOT_CONVERSATION") {
            return .conversation
        }
        if let idx = args.firstIndex(of: "-SNAPSHOT_TAB"), idx + 1 < args.count {
            switch args[idx + 1].lowercased() {
            case "actions": return .actions
            case "models": return .models
            case "settings": return .settings
            default: break
            }
        }
        return .home
    }
}

@MainActor
func macSnapshotView(for screen: MacSnapshotScreen) -> AnyView {
    switch screen {
    case .home:
        return AnyView(HomeView(context: nil))

    case .conversation:
        // Build a realistic mock conversation session.
        let model = ModelConfig(id: "gpt-4.1", displayName: "GPT-4.1", isDefault: true)
        let action = ActionConfig(
            name: NSLocalizedString("Translate", comment: ""),
            prompt: "Translate the following text",
            usageScenes: .all,
            outputType: .plain
        )
        let msgs: [ChatMessage] = [
            ChatMessage(role: "user", content: "Can you translate this to Chinese?\n\n‘Good design is as little design as possible.’", images: []),
            ChatMessage(role: "assistant", content: "当然可以。\n\n“好的设计就是尽可能少的设计。”", images: [])
        ]
        let session = ConversationSession(
            model: model,
            action: action,
            availableModels: [model],
            messages: msgs,
            isStreaming: false
        )
        return AnyView(ConversationView(session: session))

    case .actions:
        return AnyView(ActionsView(configurationStore: .makeSnapshotStore()))

    case .models:
        return AnyView(ModelsView())

    case .settings:
        return AnyView(SettingsView(configStore: .makeSnapshotStore()))
    }
}
#endif
