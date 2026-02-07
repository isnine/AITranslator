import Combine
import Foundation

@MainActor
public final class ConversationViewModel: ObservableObject {
    @Published public var messages: [ChatMessage]
    @Published public var isStreaming: Bool = false
    @Published public var streamingText: String = ""
    @Published public var inputText: String = ""
    @Published public var errorMessage: String?

    @Published public var model: ModelConfig
    public let action: ActionConfig
    public let availableModels: [ModelConfig]

    private let llmService: LLMService
    private var streamingTask: Task<Void, Never>?

    public init(session: ConversationSession, llmService: LLMService = .shared) {
        self.messages = session.messages
        self.model = session.model
        self.action = session.action
        self.availableModels = session.availableModels
        self.llmService = llmService
    }

    deinit {
        streamingTask?.cancel()
    }

    public var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    /// Cycles to the next available model in the list.
    public func cycleModel() {
        guard availableModels.count > 1 else { return }
        if let currentIndex = availableModels.firstIndex(where: { $0.id == model.id }) {
            let nextIndex = (currentIndex + 1) % availableModels.count
            model = availableModels[nextIndex]
        } else if let first = availableModels.first {
            model = first
        }
    }

    public func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        inputText = ""
        errorMessage = nil

        // Add user message
        let userMessage = ChatMessage(role: "user", content: text)
        messages.append(userMessage)

        // Start streaming
        isStreaming = true
        streamingText = ""

        streamingTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Build the full messages array for the API
                let apiMessages = self.messages.map {
                    LLMRequestPayload.Message(role: $0.role, content: $0.content)
                }

                let finalText = try await self.llmService.sendContinuation(
                    messages: apiMessages,
                    model: self.model
                ) { [weak self] partialText in
                    guard let self else { return }
                    self.streamingText = partialText
                }

                // Streaming complete - add assistant message
                let assistantMessage = ChatMessage(role: "assistant", content: finalText)
                self.messages.append(assistantMessage)
                self.streamingText = ""
                self.isStreaming = false
            } catch is CancellationError {
                self.streamingText = ""
                self.isStreaming = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.streamingText = ""
                self.isStreaming = false
            }
        }
    }

    public func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil

        // If there was partial text, save it as an incomplete assistant message
        let partial = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            let assistantMessage = ChatMessage(role: "assistant", content: partial)
            messages.append(assistantMessage)
        }

        streamingText = ""
        isStreaming = false
    }
}
