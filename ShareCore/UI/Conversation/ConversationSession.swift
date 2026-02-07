import Foundation

public struct ConversationSession: Identifiable {
    public let id: UUID
    public let model: ModelConfig
    public let action: ActionConfig
    public let availableModels: [ModelConfig]
    public var messages: [ChatMessage]
    public var isStreaming: Bool
    public var streamingText: String

    public init(
        id: UUID = UUID(),
        model: ModelConfig,
        action: ActionConfig,
        availableModels: [ModelConfig] = [],
        messages: [ChatMessage],
        isStreaming: Bool = false,
        streamingText: String = ""
    ) {
        self.id = id
        self.model = model
        self.action = action
        self.availableModels = availableModels
        self.messages = messages
        self.isStreaming = isStreaming
        self.streamingText = streamingText
    }
}
