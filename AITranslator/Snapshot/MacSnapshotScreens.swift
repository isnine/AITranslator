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
        // Build a realistic mock conversation session with locale-aware content.
        let model = ModelConfig(id: "gpt-4.1", displayName: "GPT-4.1", isDefault: true)
        let action = ActionConfig(
            name: NSLocalizedString("Translate", comment: ""),
            prompt: "Translate the following text",
            usageScenes: .all,
            outputType: .plain
        )
        let (userText, assistantText) = conversationSnapshotTexts()
        let msgs: [ChatMessage] = [
            ChatMessage(role: "user", content: userText, images: []),
            ChatMessage(role: "assistant", content: assistantText, images: []),
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

/// Returns (user message, assistant reply) localized for the current app locale.
/// Each locale gets a natural translation demo: source quote → translated quote.
private func conversationSnapshotTexts() -> (String, String) {
    let lang = Locale.current.language.languageCode?.identifier ?? "en"
    switch lang {
    case "zh":
        return (
            "帮我翻译成英文：\n\n「好的设计就是尽可能少的设计。」",
            "Sure.\n\n\"Good design is as little design as possible.\""
        )
    case "ja":
        return (
            "これを英語に翻訳してください：\n\n「良いデザインとは、できるだけ少ないデザインのことである。」",
            "もちろんです。\n\n\"Good design is as little design as possible.\""
        )
    case "ko":
        return (
            "이것을 영어로 번역해 주세요:\n\n'좋은 디자인은 가능한 한 적은 디자인이다.'",
            "물론이죠.\n\n\"Good design is as little design as possible.\""
        )
    case "de":
        return (
            "Übersetze das ins Englische:\n\n\u{201E}Gutes Design ist so wenig Design wie möglich.\u{201C}",
            "Natürlich.\n\n\"Good design is as little design as possible.\""
        )
    case "fr":
        return (
            "Traduis ceci en anglais :\n\n\u{00AB} Le bon design, c\u{2019}est aussi peu de design que possible. \u{00BB}",
            "Bien sûr.\n\n\"Good design is as little design as possible.\""
        )
    case "es":
        return (
            "Traduce esto al inglés:\n\n\u{00AB}El buen diseño es tan poco diseño como sea posible.\u{00BB}",
            "Por supuesto.\n\n\"Good design is as little design as possible.\""
        )
    case "it":
        return (
            "Traduci in inglese:\n\n\u{00AB}Il buon design è il meno design possibile.\u{00BB}",
            "Certo.\n\n\"Good design is as little design as possible.\""
        )
    case "pt":
        return (
            "Traduza para o inglês:\n\nBom design é o mínimo de design possível.",
            "Claro.\n\n\"Good design is as little design as possible.\""
        )
    case "ar":
        return (
            "ترجم هذا إلى الإنجليزية:\n\nالتصميم الجيد هو أقل قدر ممكن من التصميم.",
            "بالطبع.\n\n\"Good design is as little design as possible.\""
        )
    case "da":
        return (
            "Oversæt dette til engelsk:\n\n\"Godt design er så lidt design som muligt.\"",
            "Selvfølgelig.\n\n\"Good design is as little design as possible.\""
        )
    case "nb", "no":
        return (
            "Oversett dette til engelsk:\n\n\"Godt design er så lite design som mulig.\"",
            "Selvfølgelig.\n\n\"Good design is as little design as possible.\""
        )
    case "nl":
        return (
            "Vertaal dit naar het Engels:\n\n\"Goed ontwerp is zo weinig ontwerp als mogelijk.\"",
            "Natuurlijk.\n\n\"Good design is as little design as possible.\""
        )
    case "sv":
        return (
            "Översätt detta till engelska:\n\n\"Bra design är så lite design som möjligt.\"",
            "Självklart.\n\n\"Good design is as little design as possible.\""
        )
    case "tr":
        return (
            "Bunu İngilizceye çevir:\n\n\"İyi tasarım, mümkün olduğunca az tasarımdır.\"",
            "Tabii ki.\n\n\"Good design is as little design as possible.\""
        )
    case "id":
        return (
            "Terjemahkan ini ke bahasa Inggris:\n\n\"Desain yang baik adalah sesedikit mungkin desain.\"",
            "Tentu saja.\n\n\"Good design is as little design as possible.\""
        )
    default: // en and others
        return (
            "Translate this to Chinese:\n\n\"Good design is as little design as possible.\"",
            "Sure.\n\n「好的设计就是尽可能少的设计。」"
        )
    }
}
#endif
