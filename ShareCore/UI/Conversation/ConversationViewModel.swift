import Combine
import Foundation

@MainActor
public final class ConversationViewModel: ObservableObject {
    @Published public var messages: [ChatMessage]
    @Published public var isStreaming: Bool = false
    @Published public var streamingText: String = ""
    @Published public var inputText: String = ""
    @Published public var attachedImages: [ImageAttachment] = []
    @Published public var errorMessage: String?

    @Published public var model: ModelConfig
    public let action: ActionConfig
    public let availableModels: [ModelConfig]

    private let llmService: LLMService
    private var streamingTask: Task<Void, Never>?
    private var lastStreamingUpdateTime = Date.distantPast

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
        (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedImages.isEmpty) && !isStreaming
    }

    // MARK: - Image Management

    public func addImage(_ image: ImageAttachment) {
        attachedImages.append(image)
    }

    public func removeImage(id: UUID) {
        attachedImages.removeAll { $0.id == id }
    }

    public func clearImages() {
        attachedImages.removeAll()
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
        guard !text.isEmpty || !attachedImages.isEmpty, !isStreaming else { return }

        let currentImages = attachedImages
        inputText = ""
        attachedImages.removeAll()
        errorMessage = nil

        // Add user message
        let userMessage = ChatMessage(role: "user", content: text, images: currentImages)
        messages.append(userMessage)

        // Start streaming
        isStreaming = true
        streamingText = ""

        streamingTask = Task { [weak self] in
            guard let self else { return }
            self.lastStreamingUpdateTime = .distantPast
            do {
                // Build the full messages array for the API
                let apiMessages = self.messages.map { msg in
                    LLMRequestPayload.Message(
                        role: msg.role,
                        text: msg.content,
                        imageDataURLs: msg.images.map { $0.base64DataURL }
                    )
                }

                let finalText = try await self.llmService.sendContinuation(
                    messages: apiMessages,
                    model: self.model
                ) { [weak self] partialText in
                    guard let self else { return }
                    let now = Date()
                    guard now.timeIntervalSince(self.lastStreamingUpdateTime) >= 0.066 else { return }
                    self.lastStreamingUpdateTime = now
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
