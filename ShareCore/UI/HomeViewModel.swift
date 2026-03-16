//
//  HomeViewModel.swift
//  TLingo
//
//  Created by Zander Wang on 2025/10/19.
//
import Combine
import SwiftUI
#if DEBUG
    import Foundation
#endif
#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif

@MainActor
public final class HomeViewModel: ObservableObject {
    #if DEBUG
        @Published public var selectedDebugNetworkRecord: NetworkRequestRecord?
    #endif
    public struct ModelRunViewState: Identifiable {
        public struct SuccessResult {
            public let text: String
            public let copyText: String
            public let duration: TimeInterval
            public var diff: TextDiffBuilder.Presentation?
            public var supplementalTexts: [String]
            public var sentencePairs: [SentencePair]
            public var latencyBreakdown: LatencyBreakdown?
            public var suggestedActions: [String]

            public init(
                text: String,
                copyText: String,
                duration: TimeInterval,
                diff: TextDiffBuilder.Presentation? = nil,
                supplementalTexts: [String] = [],
                sentencePairs: [SentencePair] = [],
                latencyBreakdown: LatencyBreakdown? = nil,
                suggestedActions: [String] = []
            ) {
                self.text = text
                self.copyText = copyText
                self.duration = duration
                self.diff = diff
                self.supplementalTexts = supplementalTexts
                self.sentencePairs = sentencePairs
                self.latencyBreakdown = latencyBreakdown
                self.suggestedActions = suggestedActions
            }
        }

        public enum Status {
            case idle
            case running(start: Date)
            case streaming(text: String, start: Date)
            case streamingSentencePairs(pairs: [SentencePair], start: Date)
            case success(SuccessResult)
            case failure(message: String, duration: TimeInterval, responseBody: String? = nil)

            public var duration: TimeInterval? {
                switch self {
                case .idle, .running, .streaming, .streamingSentencePairs:
                    return nil
                case let .success(result):
                    return result.duration
                case let .failure(_, duration, _):
                    return duration
                }
            }

            public var latencyBreakdown: LatencyBreakdown? {
                switch self {
                case let .success(result):
                    return result.latencyBreakdown
                default:
                    return nil
                }
            }
        }

        public struct LatencyBreakdown {
            /// Azure Functions ↔ Model (upstream TTFB)
            public let upstreamTTFB: TimeInterval
            /// Client ↔ Azure Functions (estimated)
            public let clientToAzure: TimeInterval
            /// Detailed network timing from URLSessionTaskMetrics
            public let networkMetrics: NetworkTimingMetrics?

            public var upstreamText: String {
                formatLatency(upstreamTTFB)
            }

            public var clientToAzureText: String {
                formatLatency(clientToAzure)
            }

            private func formatLatency(_ value: TimeInterval) -> String {
                if value < 1 {
                    return String(format: "%.0fms", value * 1000)
                }
                return String(format: "%.1fs", value)
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
            cancelActiveRequest(clearResults: true)
        }
    }

    @Published public var attachedImages: [ImageAttachment] = [] {
        didSet {
            guard attachedImages.count != oldValue.count else { return }
            cancelActiveRequest(clearResults: true)
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

    /// Non-nil when smart detection auto-switched the target language
    /// (i.e. the resolved target differs from the user's preference),
    /// or when the user manually overrode the target language.
    @Published public private(set) var resolvedTargetLanguage: TargetLanguageOption?

    /// When non-nil, bypasses automatic language detection and uses this
    /// target language for the current translation.
    private var targetLanguageOverride: TargetLanguageOption?

    // MARK: - TTS Playback State

    @Published public private(set) var speakingModels: Set<String> = []
    @Published public private(set) var isSpeakingInputText: Bool = false
    /// Set to `true` when the user triggers an action but has not yet accepted data sharing consent.
    @Published public var showDataConsentRequest: Bool = false
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

    // Per-run retry support (so tapping retry on one card doesn't re-run every model)
    private var perRunTasks: [String: Task<Void, Never>] = [:]
    private var perRunRequestIDs: [String: UUID] = [:]
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

    /// Returns `true` when the app should auto-present the conversation
    /// sheet for screenshot capture.
    public static var isSnapshotConversationMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-SNAPSHOT_CONVERSATION")
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

        // Allow selecting which action to showcase in screenshots.
        // Args: -SNAPSHOT_ACTION translate|grammar|polish
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-SNAPSHOT_ACTION"), idx + 1 < args.count {
            switch args[idx + 1].lowercased() {
            case "grammar": selectedActionID = grammarAction.id
            case "polish": selectedActionID = polishAction.id
            default: selectedActionID = translateAction.id
            }
        } else {
            selectedActionID = translateAction.id
        }

        // Set input text — this will trigger didSet which clears modelRuns,
        // so we set modelRuns AFTER setting inputText.
        inputText = NSLocalizedString(
            "The quick brown fox jumps over the lazy dog. This sentence contains every letter of the alphabet.",
            comment: "Snapshot mock input text"
        )

        // Also set currentRequestInputText so createConversation(from:) can
        // reconstruct the full prompt messages for the conversation screen.
        currentRequestInputText = inputText

        // Mock results (set after inputText to avoid being cleared)
        let translatedText = NSLocalizedString(
            "The quick brown fox jumps over the lazy dog. This sentence contains every letter of the alphabet.",
            comment: "Snapshot mock translation result"
        )

        let polishedText = NSLocalizedString(
            "A nimble brown fox leapt over the lazy dog. This sentence contains every letter of the English alphabet.",
            comment: "Snapshot mock polish result"
        )

        let wantsDiff = (selectedActionID == polishAction.id)
        let diffPresentation = wantsDiff ? TextDiffBuilder.build(original: inputText, revised: polishedText) : nil

        modelRuns = [
            ModelRunViewState(
                model: gpt4Model,
                status: .success(ModelRunViewState.SuccessResult(
                    text: wantsDiff ? polishedText : translatedText,
                    copyText: wantsDiff ? polishedText : translatedText,
                    duration: 1.2,
                    diff: diffPresentation
                ))
            ),
            ModelRunViewState(
                model: claudeModel,
                status: .success(ModelRunViewState.SuccessResult(
                    text: wantsDiff ? polishedText : polishedText,
                    copyText: wantsDiff ? polishedText : polishedText,
                    duration: 1.5,
                    diff: wantsDiff ? diffPresentation : nil
                ))
            ),
        ]
    }

    /// Creates a pre-built ``ConversationSession`` for snapshot mode,
    /// so the conversation sheet can be presented immediately without
    /// needing to tap a UI button.
    ///
    /// Builds a 4-message conversation:
    /// 1. User (locale language): "The quick brown fox..." pangram
    /// 2. Assistant (English): English translation
    /// 3. User (locale language): "Make it shorter"
    /// 4. Assistant (English): Shortened version
    public func createSnapshotConversationSession() -> ConversationSession? {
        guard let firstRun = modelRuns.first,
              let action = selectedAction else { return nil }

        let userText = NSLocalizedString(
            "The quick brown fox jumps over the lazy dog. This sentence contains every letter of the alphabet.",
            comment: "Snapshot mock input text"
        )
        let assistantReply = "The quick brown fox jumps over the lazy dog. This sentence contains every letter of the alphabet."

        let followUp = NSLocalizedString(
            "Make it shorter",
            comment: "Snapshot conversation follow-up"
        )
        let shortReply = "A quick fox jumps over a lazy dog."

        let messages: [ChatMessage] = [
            ChatMessage(role: "user", content: userText),
            ChatMessage(role: "assistant", content: assistantReply),
            ChatMessage(role: "user", content: followUp),
            ChatMessage(role: "assistant", content: shortReply),
        ]

        return ConversationSession(
            model: firstRun.model,
            action: action,
            availableModels: models,
            messages: messages
        )
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
        // Always allow sending — if models aren't loaded yet we queue via
        // pendingAutoAction; if no models match we show an error to the user.
        return true
    }

    private func getEnabledModels() -> [ModelConfig] {
        let enabledIDs = preferences.enabledModelIDs
        let isPremium = StoreManager.shared.isPremium

        Logger
            .debug(
                "[HomeViewModel] getEnabledModels: enabledIDs=\(enabledIDs), models.count=\(models.count), isPremium=\(isPremium)"
            )

        var available: [ModelConfig]
        if enabledIDs.isEmpty {
            available = models.filter { $0.isDefault }
        } else {
            available = models.filter { enabledIDs.contains($0.id) }
        }

        if !isPremium {
            available = available.filter { !$0.isPremium }
        }

        // Fallback: if all selected models were filtered out (e.g. user downgraded),
        // use the default free model so the send button never silently fails.
        if available.isEmpty && !models.isEmpty {
            available = models.filter { $0.isDefault && !$0.isPremium }
        }
        if available.isEmpty && !models.isEmpty {
            available = Array(models.filter { !$0.isPremium }.prefix(1))
        }

        Logger.debug("[HomeViewModel] getEnabledModels result: \(available.map(\.id))")
        return available
    }

    private static let fallbackModels: [ModelConfig] = [
        ModelConfig(id: "gpt-4.1-nano", displayName: "GPT-4.1 Nano", isDefault: true, isPremium: false),
    ]

    private func loadModels() {
        // Display cached models immediately if available, then refresh in background.
        if let cached = ModelsService.shared.getCachedModels(), !cached.isEmpty {
            models = cached
            Logger.debug("[HomeViewModel] loadModels: loaded \(cached.count) cached models")
            updateEnabledModels()
        } else {
            Logger.debug("[HomeViewModel] loadModels: no cached models, fetching from network")
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let fetchedModels = try await ModelsService.shared.fetchModels(forceRefresh: true)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.models = fetchedModels
                    Logger.debug("[HomeViewModel] loadModels: fetched \(fetchedModels.count) models from network")
                    self.updateEnabledModels()

                    // If a request was attempted before models loaded, trigger it now.
                    if self.pendingAutoAction {
                        self.pendingAutoAction = false
                        self.performSelectedAction()
                    }
                }
            } catch {
                Logger.debug("[HomeViewModel] Failed to fetch models: \(error)")
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    // Use fallback models so the app is functional even offline
                    if self.models.isEmpty {
                        self.models = Self.fallbackModels
                        Logger.debug("[HomeViewModel] Using fallback models for offline mode")
                        self.updateEnabledModels()

                        if self.pendingAutoAction {
                            self.pendingAutoAction = false
                            self.performSelectedAction()
                        }
                    }
                }
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
        // Check data sharing consent before sending any data (macOS only)
        #if os(macOS)
            if !AppPreferences.shared.hasAcceptedDataSharing {
                showDataConsentRequest = true
                return
            }
        #endif

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
            if models.isEmpty {
                // Models still loading from network; queue for auto-trigger.
                Logger.debug("[HomeViewModel] Models not loaded yet; marking pending auto-action.")
                pendingAutoAction = true
                modelRuns = []
            } else {
                // Models loaded but none available — show error to user.
                Logger
                    .debug(
                        "[HomeViewModel] No usable models found. models=\(models.map(\.id)), enabledIDs=\(preferences.enabledModelIDs)"
                    )
                modelRuns = [
                    ModelRunViewState(
                        model: ModelConfig(id: "error", displayName: "Error"),
                        status: .failure(
                            message: "No models available. Please select a model in the Models tab.",
                            duration: 0
                        )
                    ),
                ]
            }
            return
        }

        // Clear pending flag since we're now executing
        pendingAutoAction = false

        // Clear throttle timestamps for this request
        lastStreamingUpdateTime.removeAll()

        let requestID = UUID()
        activeRequestID = requestID

        resolvedTargetLanguage = nil

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

    /// Retry a single model run (used by the per-result-card Retry button).
    /// This should NOT cancel or restart other model runs.
    public func retryRun(runID: String) {
        guard let action = selectedAction else { return }
        guard let index = modelRuns.firstIndex(where: { $0.id == runID }) else { return }

        let text = currentRequestInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !currentRequestImages.isEmpty else { return }

        let model = modelRuns[index].model

        // Cancel any in-flight retry for this run only
        perRunTasks[runID]?.cancel()

        let requestID = UUID()
        perRunRequestIDs[runID] = requestID

        // Reset UI state for this specific run
        modelRuns[index].status = .running(start: Date())

        let images = currentRequestImages
        perRunTasks[runID] = Task { [weak self] in
            await self?.executeSingleModelRequest(
                runID: runID,
                requestID: requestID,
                text: text,
                action: action,
                model: model,
                images: images
            )
        }
    }

    #if DEBUG
        /// Present the debug request detail sheet for a specific model run.
        public func presentDebugRequestDetails(for runID: String) {
            // Pull latest cross-process logs (extension may have written to file)
            NetworkRequestLogger.shared.reloadFromFile()

            let path = "/\(runID)/chat/completions"

            // Best-effort match: choose the most recent request that hit this model route.
            if let record = NetworkRequestLogger.shared.records.first(where: { $0.urlPath == path }) {
                selectedDebugNetworkRecord = record
                return
            }

            // Fallback: contains match (handles query params / different host formatting)
            if let record = NetworkRequestLogger.shared.records.first(where: { $0.url.contains(path) }) {
                selectedDebugNetworkRecord = record
                return
            }

            selectedDebugNetworkRecord = nil
        }
    #endif

    /// Manually override the auto-detected target language and re-execute
    /// the current translation. Pass the user's preferred language to revert
    /// the automatic redirect.
    public func overrideTargetLanguage(_ language: TargetLanguageOption) {
        targetLanguageOverride = language
        let preferred = AppPreferences.shared.targetLanguage
        resolvedTargetLanguage = language != preferred ? language : nil
        performSelectedAction()
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
        case let .success(result):
            return result.diff != nil
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
        case let .success(result):
            assistantText = result.copyText
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
            // Use the resolved target language that was shown in the UI,
            // falling back to auto-detection if no override was applied
            let preferred = AppPreferences.shared.targetLanguage
            let resolvedTarget = resolvedTargetLanguage ?? SourceLanguageDetector.resolveTargetLanguage(
                for: text,
                preferred: preferred
            )
            let processedPrompt = PromptSubstitution.substitute(
                prompt: prompt,
                text: text,
                targetLanguage: resolvedTarget.promptDescriptor,
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

    /// Creates a conversation from a completed run with a pre-filled follow-up message.
    /// Used when the user taps a suggested action chip.
    public func createConversationWithFollowUp(from run: ModelRunViewState, followUp: String) -> ConversationSession? {
        guard var session = createConversation(from: run) else { return nil }
        session.pendingInput = followUp
        return session
    }

    /// Creates a conversation session with the selected text as context,
    /// without any prior translation results. Used by the extension's Chat button.
    public func createContextConversation(contextText: String) -> ConversationSession? {
        let availableModels = getEnabledModels()
        guard let model = availableModels.first,
              let action = selectedAction else { return nil }

        let trimmed = contextText.trimmingCharacters(in: .whitespacesAndNewlines)

        var chatMessages: [ChatMessage] = []
        if !trimmed.isEmpty {
            chatMessages.append(ChatMessage(
                role: "system",
                content: "The user has selected the following text. Use it as context for the conversation:\n\n\(trimmed)"
            ))
        }

        return ConversationSession(
            model: model,
            action: action,
            availableModels: preferences.isPremium ? models : models.filter { !$0.isPremium },
            messages: chatMessages
        )
    }

    deinit {
        currentRequestTask?.cancel()
        perRunTasks.values.forEach { $0.cancel() }
    }

    private func executeSingleModelRequest(
        runID: String,
        requestID: UUID,
        text: String,
        action: ActionConfig,
        model: ModelConfig,
        images: [ImageAttachment] = []
    ) async {
        guard !Task.isCancelled else { return }

        // Resolve target language (same logic as batch requests)
        let preferred = AppPreferences.shared.targetLanguage
        let resolvedTarget: TargetLanguageOption
        if let override = targetLanguageOverride {
            resolvedTarget = override
            targetLanguageOverride = nil
        } else {
            resolvedTarget = SourceLanguageDetector.resolveTargetLanguage(
                for: text,
                preferred: preferred
            )
        }
        let targetLanguageDescriptor = resolvedTarget.promptDescriptor

        let _ = await llmService.perform(
            text: text,
            with: action,
            models: [model],
            images: images,
            targetLanguageDescriptor: targetLanguageDescriptor,
            partialHandler: { [weak self] modelID, update in
                guard let self else { return }
                guard self.perRunRequestIDs[runID] == requestID else { return }
                guard modelID == runID else { return }
                guard let index = self.modelRuns.firstIndex(where: { $0.id == runID }) else { return }

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
                    self.modelRuns[index].status = .streaming(text: partialText, start: startDate)
                case let .sentencePairs(pairs):
                    self.modelRuns[index].status = .streamingSentencePairs(pairs: pairs, start: startDate)
                }
            },
            completionHandler: { [weak self] result in
                guard let self else { return }
                guard self.perRunRequestIDs[runID] == requestID else { return }
                self.apply(result: result, allowDiff: self.currentActionShowsDiff)
            }
        )

        // Clear task handle only if this is still the latest retry for this run
        if perRunRequestIDs[runID] == requestID {
            perRunTasks[runID] = nil
        }
    }

    private func executeRequest(
        requestID: UUID,
        text: String,
        action: ActionConfig,
        models: [ModelConfig],
        images: [ImageAttachment] = []
    ) async {
        guard !Task.isCancelled else { return }

        // Resolve target language: use manual override if set,
        // otherwise detect source and auto-switch if source == target
        let preferred = AppPreferences.shared.targetLanguage
        let resolvedTarget: TargetLanguageOption
        if let override = targetLanguageOverride {
            resolvedTarget = override
            targetLanguageOverride = nil
        } else {
            resolvedTarget = SourceLanguageDetector.resolveTargetLanguage(
                for: text,
                preferred: preferred
            )
        }
        let targetLanguageDescriptor = resolvedTarget.promptDescriptor

        // Surface the resolved language in the UI only when it differs from the preference
        if resolvedTarget != preferred {
            resolvedTargetLanguage = resolvedTarget
        }

        let results = await llmService.perform(
            text: text,
            with: action,
            models: models,
            images: images,
            targetLanguageDescriptor: targetLanguageDescriptor,
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

                if case let .success(message) = result.response,
                   let idx = self.modelRuns.firstIndex(where: { $0.id == result.modelID })
                {
                    TranslationHistoryService.shared.save(
                        requestID: requestID,
                        sourceText: self.currentRequestInputText,
                        resultText: message,
                        actionName: self.selectedAction?.name ?? "",
                        targetLanguage: self.resolvedTargetLanguage?.englishName ?? "",
                        modelID: result.modelID,
                        modelDisplayName: self.modelRuns[idx].modelDisplayName,
                        duration: result.duration
                    )
                }
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
                    runState = .success(ModelRunViewState.SuccessResult(
                        text: message,
                        copyText: diffTarget,
                        duration: result.duration,
                        diff: diff,
                        supplementalTexts: result.supplementalTexts,
                        sentencePairs: result.sentencePairs,
                        suggestedActions: result.suggestedActions
                    ))
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
            if !modelRuns.isEmpty { modelRuns = [] }
            targetLanguageOverride = nil
        }
    }

    private func apply(result: ModelExecutionResult, allowDiff: Bool) {
        guard let index = modelRuns.firstIndex(where: { $0.id == result.modelID }) else {
            return
        }

        let latencyBreakdown: ModelRunViewState.LatencyBreakdown?
        if let upstream = result.upstreamTTFB, let clientAzure = result.clientToAzureLatency {
            latencyBreakdown = .init(upstreamTTFB: upstream, clientToAzure: clientAzure, networkMetrics: result.networkMetrics)
        } else {
            latencyBreakdown = nil
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
                    self.modelRuns[index].status = .success(ModelRunViewState.SuccessResult(
                        text: message,
                        copyText: diffTarget,
                        duration: result.duration,
                        diff: diff,
                        supplementalTexts: result.supplementalTexts,
                        sentencePairs: result.sentencePairs,
                        latencyBreakdown: latencyBreakdown,
                        suggestedActions: result.suggestedActions
                    ))
                }
            } else {
                modelRuns[index].status = .success(ModelRunViewState.SuccessResult(
                    text: message,
                    copyText: diffTarget,
                    duration: result.duration,
                    diff: nil,
                    supplementalTexts: result.supplementalTexts,
                    sentencePairs: result.sentencePairs,
                    latencyBreakdown: latencyBreakdown,
                    suggestedActions: result.suggestedActions
                ))
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
