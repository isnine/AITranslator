//
//  HomeViewModel.swift
//  TLingo
//
//  Created by Zander Wang on 2025/10/19.
//
import Combine
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif

@MainActor
public final class HomeViewModel: ObservableObject {
    public struct ModelRunViewState: Identifiable {
        public enum Status {
            case idle
            case running(start: Date)
            case streaming(text: String, start: Date)
            case streamingSentencePairs(pairs: [SentencePair], start: Date)
            case success(
                text: String,
                copyText: String,
                duration: TimeInterval,
                diff: TextDiffBuilder.Presentation? = nil,
                supplementalTexts: [String] = [],
                sentencePairs: [SentencePair] = []
            )
            case failure(message: String, duration: TimeInterval, responseBody: String? = nil)

            public var duration: TimeInterval? {
                switch self {
                case .idle, .running, .streaming, .streamingSentencePairs:
                    return nil
                case let .success(_, _, duration, _, _, _),
                     let .failure(_, duration, _):
                    return duration
                }
            }
        }

        public let model: ModelConfig
        public var status: Status
        public var showDiff: Bool = true

        public var id: String { model.id }

        public var modelDisplayName: String { model.displayName }

        public var durationText: String? {
            guard let duration = status.duration else { return nil }
            return String(format: "%.1fs", duration)
        }

        public var isRunning: Bool {
            switch status {
            case .running, .streaming, .streamingSentencePairs:
                return true
            default:
                return false
            }
        }

        public var startDate: Date? {
            switch status {
            case let .running(start), let .streaming(_, start), let .streamingSentencePairs(_, start):
                return start
            default:
                return nil
            }
        }
    }

    @Published public var inputText: String = "" {
        didSet {
            guard inputText != oldValue else { return }
            self.cancelActiveRequest(clearResults: true)
        }
    }

    @Published public var attachedImages: [ImageAttachment] = [] {
        didSet {
            guard attachedImages.count != oldValue.count else { return }
            self.cancelActiveRequest(clearResults: true)
        }
    }

    public func addImage(_ image: ImageAttachment) {
        attachedImages.append(image)
    }

    public func removeImage(id: UUID) {
        attachedImages.removeAll { $0.id == id }
    }

    public func clearImages() {
        attachedImages.removeAll()
    }

    @Published public private(set) var actions: [ActionConfig]
    @Published public private(set) var models: [ModelConfig] = []
    @Published public var selectedActionID: UUID?
    @Published public private(set) var modelRuns: [ModelRunViewState] = []
    @Published public private(set) var isLoadingConfiguration: Bool = true

    // MARK: - TTS Playback State

    @Published public private(set) var speakingModels: Set<String> = []
    @Published public private(set) var isSpeakingInputText: Bool = false
    private let ttsService: TTSPreviewService

    public let placeholderHint: String = NSLocalizedString(
        "Enter text and choose an action to get started",
        comment: "Hint shown above the action list when no input or results exist"
    )
    public let inputPlaceholder: String = NSLocalizedString(
        "Enter text to translate or process...",
        comment: "Placeholder text for the main input editor"
    )

    private let configurationStore: AppConfigurationStore
    private let llmService: LLMService
    private let preferences: AppPreferences
    private var cancellables = Set<AnyCancellable>()
    private var currentRequestTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var allActions: [ActionConfig]
    private var usageScene: ActionConfig.UsageScene
    public private(set) var currentRequestInputText: String = ""
    private var currentRequestImages: [ImageAttachment] = []
    private var currentActionShowsDiff: Bool = false
    /// Timestamp-based throttle for streaming UI updates (~15Hz).
    private var lastStreamingUpdateTime: [String: Date] = [:]
    /// When true, `performSelectedAction()` will be called automatically once models finish loading.
    private var pendingAutoAction: Bool = false

    // MARK: - Snapshot Mode

    /// Returns `true` when the app is launched with `-FASTLANE_SNAPSHOT`
    /// (used by Fastlane's snapshot tool to capture App Store screenshots).
    public static var isSnapshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT")
    }

    public init(
        configurationStore: AppConfigurationStore? = nil,
        llmService: LLMService = .shared,
        preferences: AppPreferences = .shared,
        usageScene: ActionConfig.UsageScene = .app,
        ttsService: TTSPreviewService = .shared
    ) {
        let store = configurationStore ?? .shared
        self.configurationStore = store
        self.llmService = llmService
        self.preferences = preferences
        self.usageScene = usageScene
        self.ttsService = ttsService
        allActions = store.actions
        selectedActionID = store.defaultAction?.id
        actions = []
        isLoadingConfiguration = true

        if Self.isSnapshotMode {
            populateSnapshotData()
        } else {
            refreshActions()
            loadModels()

            store.$actions
                .receive(on: RunLoop.main)
                .sink { [weak self] in
                    guard let self else { return }
                    self.allActions = $0
                    self.refreshActions()
                }
                .store(in: &cancellables)

            preferences.$enabledModelIDs
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.updateEnabledModels()
                }
                .store(in: &cancellables)
        }

        isLoadingConfiguration = false
    }

    // MARK: - Snapshot Mock Data

    /// Populates the view model with realistic-looking mock data for
    /// Fastlane App Store screenshot capture.
    private func populateSnapshotData() {
        // Mock models
        let gpt4Model = ModelConfig(id: "gpt-4.1", displayName: "GPT-4.1", isDefault: true)
        let claudeModel = ModelConfig(id: "claude-sonnet-4", displayName: "Claude Sonnet 4")
        let geminiModel = ModelConfig(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash")
        models = [gpt4Model, claudeModel, geminiModel]

        // Mock actions
        let translateAction = ActionConfig(
            name: NSLocalizedString("Translate", comment: ""),
            prompt: "Translate the following text",
            usageScenes: .all,
            outputType: .plain
        )
        let grammarAction = ActionConfig(
            name: NSLocalizedString("Grammar Check", comment: ""),
            prompt: "Check grammar",
            usageScenes: .all,
            outputType: .grammarCheck
        )
        let polishAction = ActionConfig(
            name: NSLocalizedString("Polish Writing", comment: ""),
            prompt: "Polish the writing",
            usageScenes: .all,
            outputType: .diff
        )

        allActions = [translateAction, grammarAction, polishAction]
        actions = [translateAction, grammarAction, polishAction]
        selectedActionID = translateAction.id

        // Set input text — this will trigger didSet which clears modelRuns,
        // so we set modelRuns AFTER setting inputText.
        inputText = NSLocalizedString(
            "The quick brown fox jumps over the lazy dog. This sentence contains every letter of the alphabet.",
            comment: "Snapshot mock input text"
        )

        // Mock translation results (set after inputText to avoid being cleared)
        let translatedText = NSLocalizedString(
            "敏捷的棕色狐狸跳过了懒惰的狗。这句话包含了字母表中的每个字母。",
            comment: "Snapshot mock translation result"
        )
        modelRuns = [
            ModelRunViewState(
                model: gpt4Model,
                status: .success(
                    text: translatedText,
                    copyText: translatedText,
                    duration: 1.2
                )
            ),
            ModelRunViewState(
                model: claudeModel,
                status: .success(
                    text: NSLocalizedString(
                        "那只敏捷的棕色狐狸跃过了那条懒狗。这个句子包含了英文字母表里的每一个字母。",
                        comment: "Snapshot mock translation result alt"
                    ),
                    copyText: "那只敏捷的棕色狐狸跃过了那条懒狗。这个句子包含了英文字母表里的每一个字母。",
                    duration: 1.5
                )
            ),
        ]
    }

    public var defaultAction: ActionConfig? {
        actions.first
    }

    public var selectedAction: ActionConfig? {
        guard let id = selectedActionID else {
            return actions.first
        }
        return actions.first(where: { $0.id == id }) ?? actions.first
    }

    public func refreshConfiguration() {
        isLoadingConfiguration = true

        configurationStore.reloadCurrentConfiguration()

        allActions = configurationStore.actions
        refreshActions()
        loadModels()

        if let firstAction = actions.first {
            selectedActionID = firstAction.id
        }

        isLoadingConfiguration = false
    }

    public var canSend: Bool {
        guard selectedAction != nil else {
            return false
        }
        return !getEnabledModels().isEmpty
    }

    private func getEnabledModels() -> [ModelConfig] {
        let enabledIDs = preferences.enabledModelIDs
        let isPremium = preferences.isPremium

        var available: [ModelConfig]
        if enabledIDs.isEmpty {
            available = models.filter { $0.isDefault }
        } else {
            available = models.filter { enabledIDs.contains($0.id) }
        }

        // Filter out premium models if user is not subscribed
        if !isPremium {
            available = available.filter { !$0.isPremium }
        }

        return available
    }

    private func loadModels() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let fetchedModels = try await ModelsService.shared.fetchModels()
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.models = fetchedModels
                    self.updateEnabledModels()

                    // If a request was attempted before models loaded, trigger it now.
                    if self.pendingAutoAction {
                        self.pendingAutoAction = false
                        self.performSelectedAction()
                    }
                }
            } catch {
                Logger.debug("[HomeViewModel] Failed to fetch models: \(error)")
            }
        }
    }

    private func updateEnabledModels() {
        let availableIDs = Set(models.map { $0.id })
        guard !availableIDs.isEmpty else { return }

        let currentEnabled = preferences.enabledModelIDs
        var resolved = currentEnabled.intersection(availableIDs)
        if resolved.isEmpty {
            let defaults = Set(models.filter { $0.isDefault }.map { $0.id })
            if !defaults.isEmpty {
                resolved = defaults
            }
        }

        if resolved != currentEnabled {
            preferences.setEnabledModelIDs(resolved)
        }
    }

    @discardableResult
    public func selectAction(_ action: ActionConfig) -> Bool {
        guard selectedActionID != action.id else { return false }
        selectedActionID = action.id
        return true
    }

    public func updateUsageScene(_ scene: ActionConfig.UsageScene) {
        guard usageScene != scene else { return }
        usageScene = scene
        refreshActions()
    }

    public func performSelectedAction() {
        cancelActiveRequest(clearResults: false)

        guard let action = selectedAction else {
            Logger.debug("[HomeViewModel] No action selected.")
            modelRuns = []
            return
        }

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachedImages.isEmpty else {
            Logger.debug("[HomeViewModel] Input text is empty and no images attached; skipping request.")
            modelRuns = []
            return
        }

        currentRequestInputText = text
        currentRequestImages = attachedImages
        currentActionShowsDiff = action.showsDiff

        let modelsToUse = getEnabledModels()

        guard !modelsToUse.isEmpty else {
            // Models may still be loading asynchronously. Mark as pending so we
            // auto-trigger once models become available.
            Logger.debug("[HomeViewModel] No enabled models yet; marking pending auto-action.")
            pendingAutoAction = true
            modelRuns = []
            return
        }

        // Clear pending flag since we're now executing
        pendingAutoAction = false

        // Clear throttle timestamps for this request
        lastStreamingUpdateTime.removeAll()

        let requestID = UUID()
        activeRequestID = requestID

        modelRuns = modelsToUse.map {
            ModelRunViewState(model: $0, status: .running(start: Date()))
        }

        currentRequestTask = Task { [weak self] in
            await self?.executeRequest(
                requestID: requestID,
                text: text,
                action: action,
                models: modelsToUse,
                images: attachedImages
            )
        }
    }

    public func toggleDiffDisplay(for runID: String) {
        guard let index = modelRuns.firstIndex(where: { $0.id == runID }) else {
            return
        }
        modelRuns[index].showDiff.toggle()
    }

    public func hasDiff(for runID: String) -> Bool {
        guard let run = modelRuns.first(where: { $0.id == runID }) else {
            return false
        }
        switch run.status {
        case let .success(_, _, _, diff, _, _):
            return diff != nil
        default:
            return false
        }
    }

    public func isDiffShown(for runID: String) -> Bool {
        guard let run = modelRuns.first(where: { $0.id == runID }) else {
            return false
        }
        return run.showDiff
    }

    public func openAppSettings() {
        #if canImport(UIKit)
            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                return
            }
            UIApplication.shared.open(settingsURL)
        #elseif canImport(AppKit)
            guard let settingsURL = URL(string: "x-apple.systempreferences:") else {
                return
            }
            NSWorkspace.shared.open(settingsURL)
        #endif
    }

    // MARK: - TTS Playback

    /// Speaks the result text for a specific run
    public func speakResult(_ text: String, runID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !speakingModels.contains(runID) else { return }

        speakingModels.insert(runID)

        Task { [weak self] in
            guard let self else { return }
            await self.ttsService.speak(text: trimmed, textID: runID)
            await MainActor.run { [weak self] in
                self?.speakingModels.remove(runID)
            }
        }
    }

    /// Speaks the current input text
    public func speakInputText() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isSpeakingInputText else { return }

        isSpeakingInputText = true

        Task { [weak self] in
            guard let self else { return }
            await self.ttsService.speak(text: trimmed, textID: "input")
            await MainActor.run { [weak self] in
                self?.isSpeakingInputText = false
            }
        }
    }

    /// Check if a specific run is currently being spoken
    public func isSpeaking(runID: String) -> Bool {
        speakingModels.contains(runID)
    }

    /// Stop any current TTS playback
    public func stopSpeaking() {
        ttsService.stopPlayback()
        speakingModels.removeAll()
        isSpeakingInputText = false
    }

    // MARK: - Continue Conversation

    /// Creates a ``ConversationSession`` from a completed model run,
    /// reconstructing the original prompt messages so the conversation
    /// starts with full context.
    public func createConversation(from run: ModelRunViewState) -> ConversationSession? {
        guard let action = selectedAction else { return nil }

        // Extract the assistant's response text from the success state
        let assistantText: String
        switch run.status {
        case let .success(_, copyText, _, _, _, _):
            assistantText = copyText
        default:
            return nil
        }

        // Reconstruct the original messages using the same logic as LLMService
        var chatMessages: [ChatMessage] = []

        let text = currentRequestInputText
        let prompt = action.prompt

        if prompt.isEmpty {
            chatMessages.append(ChatMessage(role: "user", content: text, images: currentRequestImages))
        } else {
            let processedPrompt = PromptSubstitution.substitute(
                prompt: prompt,
                text: text,
                targetLanguage: AppPreferences.shared.targetLanguage.promptDescriptor,
                sourceLanguage: ""
            )
            let promptContainsTextPlaceholder = PromptSubstitution.containsTextPlaceholder(prompt)

            if promptContainsTextPlaceholder {
                chatMessages.append(ChatMessage(role: "user", content: processedPrompt, images: currentRequestImages))
            } else {
                chatMessages.append(ChatMessage(role: "system", content: processedPrompt))
                chatMessages.append(ChatMessage(role: "user", content: text, images: currentRequestImages))
            }
        }

        // Add the assistant's response
        chatMessages.append(ChatMessage(role: "assistant", content: assistantText))

        return ConversationSession(
            model: run.model,
            action: action,
            availableModels: preferences.isPremium ? models : models.filter { !$0.isPremium },
            messages: chatMessages
        )
    }

    deinit {
        currentRequestTask?.cancel()
    }

    private func executeRequest(
        requestID: UUID,
        text: String,
        action: ActionConfig,
        models: [ModelConfig],
        images: [ImageAttachment] = []
    ) async {
        guard !Task.isCancelled else { return }

        let results = await llmService.perform(
            text: text,
            with: action,
            models: models,
            images: images,
            partialHandler: { [weak self] modelID, update in
                guard let self else { return }
                guard self.activeRequestID == requestID else { return }
                guard let index = self.modelRuns.firstIndex(where: { $0.id == modelID }) else {
                    return
                }

                // Throttle streaming UI updates to ~15Hz (66ms)
                let now = Date()
                if let lastUpdate = self.lastStreamingUpdateTime[modelID],
                   now.timeIntervalSince(lastUpdate) < 0.066
                {
                    return
                }
                self.lastStreamingUpdateTime[modelID] = now

                let startDate = self.modelRuns[index].startDate ?? Date()
                switch update {
                case let .text(partialText):
                    self.modelRuns[index].status = .streaming(
                        text: partialText,
                        start: startDate
                    )
                case let .sentencePairs(pairs):
                    self.modelRuns[index].status = .streamingSentencePairs(
                        pairs: pairs,
                        start: startDate
                    )
                }
            },
            completionHandler: { [weak self] result in
                guard let self else { return }
                guard self.activeRequestID == requestID else { return }
                self.apply(result: result, allowDiff: self.currentActionShowsDiff)
            }
        )

        guard !Task.isCancelled else { return }
        guard activeRequestID == requestID else { return }

        for result in results {
            if modelRuns.contains(where: { $0.id == result.modelID }) {
                apply(result: result, allowDiff: currentActionShowsDiff)
            } else if let model = models.first(where: { $0.id == result.modelID }) {
                let runState: ModelRunViewState.Status
                switch result.response {
                case let .success(message):
                    let diffTarget = result.diffSource ?? message
                    let diff: TextDiffBuilder.Presentation?
                    if currentActionShowsDiff {
                        let inputText = currentRequestInputText
                        diff = await Task.detached(priority: .userInitiated) {
                            TextDiffBuilder.build(original: inputText, revised: diffTarget)
                        }.value
                    } else {
                        diff = nil
                    }
                    runState = .success(
                        text: message,
                        copyText: diffTarget,
                        duration: result.duration,
                        diff: diff,
                        supplementalTexts: result.supplementalTexts,
                        sentencePairs: result.sentencePairs
                    )
                case let .failure(error):
                    let responseBody: String?
                    if let llmError = error as? LLMServiceError,
                       case let .httpError(_, body) = llmError
                    {
                        responseBody = body
                    } else {
                        responseBody = nil
                    }
                    runState = .failure(
                        message: error.localizedDescription,
                        duration: result.duration,
                        responseBody: responseBody
                    )
                }
                modelRuns.append(ModelRunViewState(model: model, status: runState))
            }
        }

        if activeRequestID == requestID {
            currentRequestTask = nil
            activeRequestID = nil
        }
    }

    private func cancelActiveRequest(clearResults: Bool) {
        currentRequestTask?.cancel()
        currentRequestTask = nil
        activeRequestID = nil
        if clearResults {
            modelRuns = []
        }
    }

    private func apply(result: ModelExecutionResult, allowDiff: Bool) {
        guard let index = modelRuns.firstIndex(where: { $0.id == result.modelID }) else {
            return
        }

        switch result.response {
        case let .success(message):
            let diffTarget = result.diffSource ?? message
            if allowDiff {
                // Compute diff off main thread
                let inputText = currentRequestInputText
                Task {
                    let diff = await Task.detached(priority: .userInitiated) {
                        TextDiffBuilder.build(original: inputText, revised: diffTarget)
                    }.value
                    guard self.modelRuns.indices.contains(index),
                          self.modelRuns[index].id == result.modelID else { return }
                    self.modelRuns[index].status = .success(
                        text: message,
                        copyText: diffTarget,
                        duration: result.duration,
                        diff: diff,
                        supplementalTexts: result.supplementalTexts,
                        sentencePairs: result.sentencePairs
                    )
                }
            } else {
                modelRuns[index].status = .success(
                    text: message,
                    copyText: diffTarget,
                    duration: result.duration,
                    diff: nil,
                    supplementalTexts: result.supplementalTexts,
                    sentencePairs: result.sentencePairs
                )
            }
        case let .failure(error):
            let responseBody: String?
            if let llmError = error as? LLMServiceError,
               case let .httpError(_, body) = llmError
            {
                responseBody = body
            } else {
                responseBody = nil
            }
            modelRuns[index].status = .failure(
                message: error.localizedDescription,
                duration: result.duration,
                responseBody: responseBody
            )
        }
    }

    private func refreshActions() {
        let filtered = allActions.filter { $0.usageScenes.contains(usageScene) }
        actions = filtered

        guard !filtered.isEmpty else {
            selectedActionID = nil
            return
        }

        if let selectedID = selectedActionID,
           filtered.contains(where: { $0.id == selectedID })
        {
            return
        }

        selectedActionID = filtered.first?.id
    }
}
