//
//  HomeViewModel.swift
//  TLingo
//
//  Created by Zander Wang on 2025/10/19.
//
import Combine
import os
import SwiftUI

private let logger = os.Logger(subsystem: "com.zanderwang.AITranslator", category: "HomeViewModel")
#if DEBUG
    import Foundation
#endif
#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif
#if canImport(Translation)
    import Translation
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

    /// When set, `refreshConfiguration()` will select this action after loading.
    public internal(set) var pendingDeepLinkActionName: String?

    /// Non-nil when smart detection auto-switched the target language
    /// (i.e. the resolved target differs from the user's preference),
    /// or when the user manually overrode the target language.
    @Published public private(set) var resolvedTargetLanguage: TargetLanguageOption?

    /// Non-nil after a translation runs: the detected (or user-pinned) source language,
    /// used to show a strikethrough on the source selector with the detected name beside it.
    @Published public private(set) var detectedSourceLanguage: SourceLanguageOption?

    // MARK: - Apple Translation Bridge

    /// When false, Apple Translate is excluded from the model list even if enabled in preferences.
    /// Use the extension path (`TranslationSession(installedSource:target:)`) which requires pre-installed packs.
    public let supportsAppleTranslate: Bool

    /// Published by the view model to request a `.translationTask()` session from the view layer.
    /// HomeView observes this and creates a `TranslationSession.Configuration`.
    @Published public var appleTranslateTargetLanguage: TargetLanguageOption?

    /// Detected source language for the pending Apple Translate request.
    /// Used by HomeView to set `TranslationSession.Configuration.source`
    /// so the system does not show a "Choose Language" prompt.
    public private(set) var appleTranslateSourceLanguage: Locale.Language?

    /// Context captured when an Apple Translate request is pending, so that the
    /// `.translationTask()` callback in HomeView can relay it back.
    public private(set) var pendingAppleTranslateText: String?
    public private(set) var pendingAppleTranslateAction: ActionConfig?
    public private(set) var pendingAppleTranslateRequestID: UUID?
    private var pendingAppleTranslateResolvedTarget: TargetLanguageOption?

    /// When non-nil, bypasses automatic language detection and uses this
    /// target language for the current translation.
    private var targetLanguageOverride: TargetLanguageOption?

    /// Optional handler invoked on macOS to route Apple Translate requests through a
    /// real NSWindow (required for TranslationSession to work outside an NSPopover).
    /// Set by the host app (AITranslator) via `AppleTranslationWindowManager`.
    public var appleTranslationRequestHandler: ((Locale.Language?, TargetLanguageOption) -> Void)?

    // MARK: - TTS Playback State

    @Published public private(set) var speakingModels: Set<String> = []
    @Published public private(set) var isSpeakingInputText: Bool = false
    /// Set to `true` when the user triggers an action but has not yet accepted data sharing consent.
    @Published public var showDataConsentRequest: Bool = false
    /// Set to `true` when the satisfaction prompt toast should be displayed.
    @Published public var showSatisfactionPrompt: Bool = false
    /// Incremented each time a translation request completes with at least one success.
    @Published public private(set) var successfulTranslationCount: Int = 0
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
        ttsService: TTSPreviewService = .shared,
        supportsAppleTranslate: Bool = true
    ) {
        let store = configurationStore ?? .shared
        self.configurationStore = store
        self.llmService = llmService
        self.preferences = preferences
        self.ttsService = ttsService
        self.supportsAppleTranslate = supportsAppleTranslate
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
            outputType: .translate
        )
        let grammarAction = ActionConfig(
            name: NSLocalizedString("Grammar Check", comment: ""),
            prompt: "Check grammar",
            outputType: .grammarCheck
        )
        let polishAction = ActionConfig(
            name: NSLocalizedString("Polish Writing", comment: ""),
            prompt: "Polish the writing",
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
        logger.debug("refreshConfiguration() — \(self.actions.count, privacy: .public) actions: \(self.actions.map(\.name), privacy: .public)")

        // Apply pending deep link action, or fall back to first action
        if let pendingName = pendingDeepLinkActionName,
           let action = actions.first(where: { $0.name == pendingName })
        {
            selectedActionID = action.id
            pendingDeepLinkActionName = nil
        } else if let firstAction = actions.first {
            selectedActionID = firstAction.id
        }

        isLoadingConfiguration = false
    }

    /// Handles a deep link from the extension: switches config if needed, selects action, and runs.
    public func applyDeepLink(text: String, actionName: String?, configName: String?) {
        inputText = text

        // Switch configuration if the deep link specifies a different one
        if let configName,
           configurationStore.currentConfigurationName != configName
        {
            configurationStore.setCurrentConfigurationName(configName)
        }

        // Reload to pick up the (possibly switched) configuration
        refreshConfiguration()

        // Try to select the action by name now; also store as pending for cold launch
        pendingDeepLinkActionName = actionName
        if let actionName,
           let action = actions.first(where: { $0.name == actionName })
        {
            _ = selectAction(action)
            pendingDeepLinkActionName = nil
        }

        performSelectedAction()
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

        logger
            .debug(
                "getEnabledModels: enabledIDs=\(enabledIDs, privacy: .public), models.count=\(self.models.count, privacy: .public), isPremium=\(isPremium, privacy: .public)"
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
        // Skip fallback if Apple Translate or Google Translate is selected — either alone is sufficient.
        let directTranslateSelected = enabledIDs.contains(where: { ModelConfig.isDirectTranslationID($0) })
        if available.isEmpty && !models.isEmpty && !directTranslateSelected {
            available = models.filter { $0.isDefault && !$0.isPremium }
        }
        if available.isEmpty && !models.isEmpty && !directTranslateSelected {
            available = Array(models.filter { !$0.isPremium }.prefix(1))
        }

        // Inject Apple Translate only for translation actions.
        // In SwiftUI contexts (supportsAppleTranslate = true), the view layer provides a session
        // via .translationTask(). In non-SwiftUI contexts (e.g. extension), we fall back to
        // TranslationSession(installedSource:target:) which requires pre-installed language packs.
        if enabledIDs.contains(ModelConfig.appleTranslateID),
           AppleTranslationService.shared.isAvailable,
           let action = selectedAction, action.supportsAppleTranslate
        {
            available.insert(ModelConfig.appleTranslate, at: 0)
        }

        // Inject Google Translate for translation actions.
        if enabledIDs.contains(ModelConfig.googleTranslateID),
           let action = selectedAction, action.supportsAppleTranslate
        {
            // Insert after Apple Translate if present, otherwise at the beginning.
            let insertIndex = available.firstIndex(where: { $0.id == ModelConfig.appleTranslateID })
                .map { available.index(after: $0) } ?? 0
            available.insert(ModelConfig.googleTranslate, at: insertIndex)
        }

        logger.debug("getEnabledModels result: \(available.map(\.id), privacy: .public)")
        return available
    }

    private static let fallbackModels: [ModelConfig] = [
        ModelConfig(id: "gpt-4.1-nano", displayName: "GPT-4.1 Nano", isDefault: true, isPremium: false),
    ]

    private func loadModels() {
        // Display cached models immediately if available, then refresh in background.
        if let cached = ModelsService.shared.getCachedModels(), !cached.isEmpty {
            models = cached
            logger.debug("loadModels: loaded \(cached.count, privacy: .public) cached models")
            updateEnabledModels()
        } else {
            logger.debug("loadModels: no cached models, fetching from network")
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let fetchedModels = try await ModelsService.shared.fetchModels(forceRefresh: true)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.models = fetchedModels
                    logger.debug("loadModels: fetched \(fetchedModels.count, privacy: .public) models from network")
                    self.updateEnabledModels()

                    // If a request was attempted before models loaded, trigger it now.
                    if self.pendingAutoAction {
                        self.pendingAutoAction = false
                        self.performSelectedAction()
                    }
                }
            } catch {
                logger.error("Failed to fetch models: \(error, privacy: .public)")
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    // Use fallback models so the app is functional even offline
                    if self.models.isEmpty {
                        self.models = Self.fallbackModels
                        logger.debug("Using fallback models for offline mode")
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
        // Preserve local/direct-translation model IDs (e.g. apple-translate, google-translate)
        // that are not in the cloud/fallback models list but are still valid selections.
        let localIDs = currentEnabled.filter { ModelConfig.isDirectTranslationID($0) }
        var resolved = currentEnabled.intersection(availableIDs).union(localIDs)
        if resolved.isEmpty {
            let defaults = Set(models.filter { $0.isDefault }.map { $0.id })
            if !defaults.isEmpty {
                resolved = resolved.union(defaults)
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
        resolvedTargetLanguage = nil
        detectedSourceLanguage = nil
        return true
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
            logger.debug("No action selected.")
            modelRuns = []
            return
        }

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachedImages.isEmpty else {
            logger.debug("Input text is empty and no images attached; skipping request.")
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
                logger.debug("Models not loaded yet; marking pending auto-action.")
                pendingAutoAction = true
                modelRuns = []
            } else {
                // Models loaded but none available — show error to user.
                logger
                    .debug(
                        "No usable models found. models=\(self.models.map(\.id), privacy: .public), enabledIDs=\(self.preferences.enabledModelIDs, privacy: .public)"
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
        detectedSourceLanguage = nil

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
        // Use executeRequest so direct services (Apple/Google) get routed through their own
        // paths. executeSingleModelRequest only handles cloud LLM calls.
        perRunTasks[runID] = Task { [weak self] in
            await self?.executeRequest(
                requestID: requestID,
                text: text,
                action: action,
                models: [model],
                images: images,
                isPerRunRetry: true
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

    /// Manually override the target language for the next translation and re-execute.
    /// Used by the language switcher menu. Target is never automatically redirected,
    /// so `resolvedTargetLanguage` stays nil — the override is consumed once on the next request.
    public func overrideTargetLanguage(_ language: TargetLanguageOption) {
        targetLanguageOverride = language
        resolvedTargetLanguage = nil
        performSelectedAction()
    }

    /// Called when the user picks a new source language — clears the detected-source strikethrough state.
    public func clearDetectedSourceLanguage() {
        detectedSourceLanguage = nil
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

    public func openFeedbackEmail() {
        let isPremium = StoreManager.shared.isPremium
        let subject = isPremium ? "TLingo%20Feedback%20%5BPremium%5D" : "TLingo%20Feedback"
        guard let url = URL(string: "mailto:xiaozwan@outlook.com?subject=\(subject)") else { return }
        #if canImport(UIKit)
            UIApplication.shared.open(url)
        #elseif canImport(AppKit)
            NSWorkspace.shared.open(url)
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
            // Target language is always the user preference (never auto-redirected).
            let resolvedTarget = resolvedTargetLanguage ?? AppPreferences.shared.targetLanguage
            let processedPrompt = PromptSubstitution.substitute(
                prompt: prompt,
                text: text,
                targetLanguage: resolvedTarget.promptDescriptor,
                sourceLanguage: detectedSourceLanguage?.promptDescriptor ?? ""
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

    /// Result of `consumeResolvedTarget`: the resolved target language and
    /// the detected/pinned source language code (for reuse by Apple/Google/LLM engines).
    struct ResolvedLanguagePair {
        let target: TargetLanguageOption
        /// BCP 47 source code (e.g. "en", "zh-Hans"), or nil when detection failed.
        let sourceCode: String?

        var targetLanguageDescriptor: String { target.promptDescriptor }

        /// Human-readable source descriptor for LLM prompts, e.g. "日本語 (Japanese)".
        /// Empty when source is unknown (auto-detect failed).
        var sourceLanguageDescriptor: String {
            guard let code = sourceCode else { return "" }
            let option = SourceLanguageOption(rawValue: code)
                ?? SourceLanguageOption(rawValue: String(code.prefix(2)))
            return option?.promptDescriptor ?? ""
        }
    }

    /// Consumes `targetLanguageOverride` if set, otherwise returns the user's preferred target.
    /// Target language is never automatically redirected — it always honors the user's setting.
    /// Source language detection biases away from the target so mixed-language input
    /// (e.g. "你好, hello") picks the *other* language when the user is in `.auto` mode.
    private func consumeResolvedTarget(for text: String) -> ResolvedLanguagePair {
        let target: TargetLanguageOption
        if let override = targetLanguageOverride {
            targetLanguageOverride = nil
            target = override
        } else {
            target = AppPreferences.shared.targetLanguage
        }

        if target == .appLanguage {
            let candidates = TargetLanguageOption.matchCandidates
            let sourceCode = detectSourceCodeConstrained(for: text, candidateCodes: candidates.map(\.rawValue))
            let resolved = SourceLanguageDetector.resolveMatchTarget(sourceCode: sourceCode, candidates: candidates)
            return ResolvedLanguagePair(target: resolved, sourceCode: sourceCode)
        }

        let sourceCode = detectSourceCode(for: text, excluding: target)
        return ResolvedLanguagePair(target: target, sourceCode: sourceCode)
    }

    /// Detects the source language code and sets `detectedSourceLanguage` for UI.
    /// When `sourceLanguage` is `.auto`, biases detection away from `target` so that
    /// a Chinese+English input is detected as Chinese when the user is translating to English.
    private func detectSourceCode(for text: String, excluding target: TargetLanguageOption) -> String? {
        let sourceLanguage = AppPreferences.shared.sourceLanguage
        if sourceLanguage != .auto {
            detectedSourceLanguage = sourceLanguage
            return sourceLanguage.rawValue
        }
        let targetCode = target == .appLanguage ? TargetLanguageOption.appLanguageIdentifier : target.rawValue
        guard let detected = SourceLanguageDetector.detectLocaleLanguage(of: text, excludingTargetCode: targetCode) else {
            return nil
        }
        let code = detected.minimalIdentifier
        detectedSourceLanguage = SourceLanguageOption(rawValue: code)
            ?? SourceLanguageOption(rawValue: String(code.prefix(2)))
        return code
    }

    /// Match mode: detects source language constrained to candidate language codes only.
    private func detectSourceCodeConstrained(for text: String, candidateCodes: [String]) -> String? {
        let sourceLanguage = AppPreferences.shared.sourceLanguage
        if sourceLanguage != .auto {
            detectedSourceLanguage = sourceLanguage
            return sourceLanguage.rawValue
        }
        guard let detected = SourceLanguageDetector.detectLocaleLanguageConstrained(of: text, candidateCodes: candidateCodes) else {
            return nil
        }
        let code = detected.minimalIdentifier
        detectedSourceLanguage = SourceLanguageOption(rawValue: code)
            ?? SourceLanguageOption(rawValue: String(code.prefix(2)))
        return code
    }

    /// If user chose source==target (or auto-detected source matches target), Apple Translate
    /// physically can't translate — return a localized error result instead of calling the API.
    private func sameSourceAndTargetResult(
        sourceCode: String?,
        target: TargetLanguageOption
    ) -> ModelExecutionResult? {
        let targetCode = target == .appLanguage ? TargetLanguageOption.appLanguageIdentifier : target.rawValue
        guard let sourceCode,
              SourceLanguageDetector.languagesAreSame(sourceCode, targetCode)
        else {
            return nil
        }
        logger.error("Apple Translate: source==target (\(sourceCode, privacy: .public)), short-circuiting")
        return ModelExecutionResult(
            modelID: ModelConfig.appleTranslateID,
            duration: 0,
            response: .failure(LocalProviderError.sameSourceAndTarget(language: target.englishName))
        )
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

        let resolved = consumeResolvedTarget(for: text)

        let _ = await llmService.perform(
            text: text,
            with: action,
            models: [model],
            images: images,
            targetLanguageDescriptor: resolved.targetLanguageDescriptor,
            sourceLanguageDescriptor: resolved.sourceLanguageDescriptor,
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

    private func isRequestStillValid(_ requestID: UUID, isPerRunRetry: Bool) -> Bool {
        if isPerRunRetry {
            return perRunRequestIDs.values.contains(requestID)
        }
        return activeRequestID == requestID
    }

    private func executeRequest(
        requestID: UUID,
        text: String,
        action: ActionConfig,
        models: [ModelConfig],
        images: [ImageAttachment] = [],
        isPerRunRetry: Bool = false
    ) async {
        guard !Task.isCancelled else { return }

        let resolved = consumeResolvedTarget(for: text)
        let resolvedTarget = resolved.target

        // Separate direct translation services from cloud LLM models.
        let cloudModels = models.filter { !$0.isDirectTranslation }
        let hasAppleTranslate = models.contains { $0.isLocal }
        let hasGoogleTranslate = models.contains { $0.isGoogleTranslate }
        logger.debug("executeRequest: \(models.count, privacy: .public) models, apple=\(hasAppleTranslate, privacy: .public), google=\(hasGoogleTranslate, privacy: .public)")

        // Kick off Apple Translate if present.
        if hasAppleTranslate {
            if action.supportsAppleTranslate {
                if supportsAppleTranslate {
                    // SwiftUI context: prefer the direct TranslationSession(installedSource:target:)
                    // path when the language pack is already installed; fall back to .translationTask()
                    // only when a download is required.
                    let sourceLocale: Locale.Language? = resolved.sourceCode.map { Locale.Language(identifier: $0) }
                    let targetLocale = resolvedTarget.localeLanguage
                    if let shortCircuit = sameSourceAndTargetResult(sourceCode: resolved.sourceCode, target: resolvedTarget) {
                        apply(result: shortCircuit, allowDiff: false)
                    } else {
                        Task { [weak self] in
                        guard let self else { return }
                        if #available(iOS 17.4, macOS 14.4, *) {
                            let status = await AppleTranslationService.shared.languageAvailabilityStatus(
                                source: sourceLocale, target: targetLocale
                            )
                            if status == .installed {
                                // Language pack already on device — skip SwiftUI bridge entirely.
                                do {
                                    let result: ModelExecutionResult
                                    if action.outputType == .sentencePairs {
                                        result = try await AppleTranslationService.shared.translateSentencesWithInstalledLanguages(
                                            text: text, source: sourceLocale, target: targetLocale
                                        )
                                    } else {
                                        result = try await AppleTranslationService.shared.translateWithInstalledLanguages(
                                            text: text, source: sourceLocale, target: targetLocale
                                        )
                                    }
                                    guard self.isRequestStillValid(requestID, isPerRunRetry: isPerRunRetry) else { return }
                                    self.apply(result: result, allowDiff: false)
                                    if case let .success(message) = result.response,
                                       let idx = self.modelRuns.firstIndex(where: { $0.id == result.modelID })
                                    {
                                        TranslationHistoryService.shared.save(
                                            requestID: requestID,
                                            sourceText: self.currentRequestInputText,
                                            resultText: message,
                                            actionName: action.name,
                                            targetLanguage: resolvedTarget.englishName,
                                            modelID: result.modelID,
                                            modelDisplayName: self.modelRuns[idx].modelDisplayName,
                                            duration: result.duration
                                        )
                                    }
                                } catch {
                                    logger.error("Apple Translate (installed-pack path) failed: \(String(describing: error), privacy: .public), source=\(sourceLocale?.minimalIdentifier ?? "auto", privacy: .public), target=\(targetLocale.minimalIdentifier, privacy: .public)")
                                    guard self.isRequestStillValid(requestID, isPerRunRetry: isPerRunRetry) else { return }
                                    let fail = ModelExecutionResult(
                                        modelID: ModelConfig.appleTranslateID,
                                        duration: 0,
                                        response: .failure(LocalProviderError.translationFailed(error.localizedDescription))
                                    )
                                    self.apply(result: fail, allowDiff: false)
                                }
                            } else {
                                // Language pack not installed; need .translationTask() to trigger download UI.
                                // Set pending state then schedule a 10s timeout watchdog.
                                self.pendingAppleTranslateText = text
                                self.pendingAppleTranslateAction = action
                                self.pendingAppleTranslateRequestID = requestID
                                self.pendingAppleTranslateResolvedTarget = resolvedTarget
                                self.appleTranslateSourceLanguage = sourceLocale
                                self.appleTranslateTargetLanguage = resolvedTarget
                                logger.debug("Apple Translate: published target=\(resolvedTarget.englishName, privacy: .public), starting 10s timeout watchdog")
                                self.appleTranslationRequestHandler?(sourceLocale, resolvedTarget)

                                // Watchdog: if .translationTask() doesn't fire within 10s, surface an error.
                                try? await Task.sleep(nanoseconds: 10_000_000_000)
                                guard self.pendingAppleTranslateRequestID == requestID else { return }
                                logger.error("Apple Translate watchdog fired — .translationTask() did not respond in 10s, source=\(sourceLocale?.minimalIdentifier ?? "auto", privacy: .public), target=\(resolvedTarget.rawValue, privacy: .public), status=\(String(describing: status), privacy: .public)")
                                self.pendingAppleTranslateText = nil
                                self.pendingAppleTranslateAction = nil
                                self.pendingAppleTranslateRequestID = nil
                                self.pendingAppleTranslateResolvedTarget = nil
                                self.appleTranslateSourceLanguage = nil
                                self.appleTranslateTargetLanguage = nil
                                guard self.isRequestStillValid(requestID, isPerRunRetry: isPerRunRetry) else { return }
                                let timeoutResult = ModelExecutionResult(
                                    modelID: ModelConfig.appleTranslateID,
                                    duration: 10,
                                    response: .failure(LocalProviderError.translationFailed("Apple Translate timed out (10s). Language pack may not be available."))
                                )
                                self.apply(result: timeoutResult, allowDiff: false)
                            }
                        }
                    }
                    }
                } else {
                    // Non-SwiftUI context (e.g. extension): use TranslationSession(installedSource:target:)
                    // directly. Only works if language packs are already installed.
                    let sourceLocale: Locale.Language? = resolved.sourceCode.map { Locale.Language(identifier: $0) }
                    let targetLocale = resolvedTarget.localeLanguage
                    if let shortCircuit = sameSourceAndTargetResult(sourceCode: resolved.sourceCode, target: resolvedTarget) {
                        apply(result: shortCircuit, allowDiff: false)
                    } else {
                        Task { [weak self] in
                        guard let self else { return }
                        // Always true at runtime (guarded by isAvailable in getEnabledModels),
                        // but required for the compiler's availability check.
                        if #available(iOS 17.4, macOS 14.4, *) {
                            do {
                                let result: ModelExecutionResult
                                if action.outputType == .sentencePairs {
                                    result = try await AppleTranslationService.shared.translateSentencesWithInstalledLanguages(
                                        text: text, source: sourceLocale, target: targetLocale
                                    )
                                } else {
                                    result = try await AppleTranslationService.shared.translateWithInstalledLanguages(
                                        text: text, source: sourceLocale, target: targetLocale
                                    )
                                }
                                guard self.isRequestStillValid(requestID, isPerRunRetry: isPerRunRetry) else { return }
                                self.apply(result: result, allowDiff: false)
                            } catch {
                                logger.error("Apple Translate (non-SwiftUI path) failed: \(String(describing: error), privacy: .public), source=\(sourceLocale?.minimalIdentifier ?? "auto", privacy: .public), target=\(targetLocale.minimalIdentifier, privacy: .public)")
                                guard self.isRequestStillValid(requestID, isPerRunRetry: isPerRunRetry) else { return }
                                let fail = ModelExecutionResult(
                                    modelID: ModelConfig.appleTranslateID,
                                    duration: 0,
                                    response: .failure(LocalProviderError.translationFailed(error.localizedDescription))
                                )
                                self.apply(result: fail, allowDiff: false)
                            }
                        }
                    }
                    }
                }
            } else {
                // Unsupported action — show inline error immediately.
                logger.error("Apple Translate: action '\(action.name, privacy: .public)' does not support Apple Translate")
                let result = ModelExecutionResult(
                    modelID: ModelConfig.appleTranslateID,
                    duration: 0,
                    response: .failure(LocalProviderError.unsupportedAction)
                )
                apply(result: result, allowDiff: false)
            }
        }

        // Kick off Google Translate if present.
        if hasGoogleTranslate {
            if action.supportsAppleTranslate {
                let googleSourceCode: String? = resolved.sourceCode
                Task { [weak self] in
                    guard let self else { return }
                    let result = await GoogleTranslateService.shared.translate(
                        text: text,
                        sourceCode: googleSourceCode,
                        targetCode: resolvedTarget.rawValue
                    )
                    guard self.isRequestStillValid(requestID, isPerRunRetry: isPerRunRetry) else { return }
                    self.apply(result: result, allowDiff: false)
                    if case let .success(message) = result.response,
                       let idx = self.modelRuns.firstIndex(where: { $0.id == result.modelID })
                    {
                        TranslationHistoryService.shared.save(
                            requestID: requestID,
                            sourceText: self.currentRequestInputText,
                            resultText: message,
                            actionName: action.name,
                            targetLanguage: resolvedTarget.englishName,
                            modelID: result.modelID,
                            modelDisplayName: self.modelRuns[idx].modelDisplayName,
                            duration: result.duration
                        )
                    }
                }
            } else {
                let result = ModelExecutionResult(
                    modelID: ModelConfig.googleTranslateID,
                    duration: 0,
                    response: .failure(LocalProviderError.unsupportedAction)
                )
                apply(result: result, allowDiff: false)
            }
        }

        // Run cloud models through the existing LLM path.
        guard !cloudModels.isEmpty else {
            // Only direct translation services were selected; skip cloud path.
            if !hasAppleTranslate && !hasGoogleTranslate {
                // No models at all — shouldn't reach here but guard anyway.
                if isRequestStillValid(requestID, isPerRunRetry: isPerRunRetry) {
                    currentRequestTask = nil
                    if !isPerRunRetry { activeRequestID = nil }
                }
            }
            return
        }

        let results = await llmService.perform(
            text: text,
            with: action,
            models: cloudModels,
            images: images,
            targetLanguageDescriptor: resolved.targetLanguageDescriptor,
            sourceLanguageDescriptor: resolved.sourceLanguageDescriptor,
            partialHandler: { [weak self] modelID, update in
                guard let self else { return }
                guard self.isRequestStillValid(requestID, isPerRunRetry: isPerRunRetry) else { return }
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
                guard self.isRequestStillValid(requestID, isPerRunRetry: isPerRunRetry) else { return }
                self.apply(result: result, allowDiff: self.currentActionShowsDiff)

                if case let .success(message) = result.response,
                   let idx = self.modelRuns.firstIndex(where: { $0.id == result.modelID })
                {
                    TranslationHistoryService.shared.save(
                        requestID: requestID,
                        sourceText: self.currentRequestInputText,
                        resultText: message,
                        actionName: self.selectedAction?.name ?? "",
                        targetLanguage: resolvedTarget.englishName,
                        modelID: result.modelID,
                        modelDisplayName: self.modelRuns[idx].modelDisplayName,
                        duration: result.duration
                    )
                }
            }
        )

        guard !Task.isCancelled else { return }
        guard isRequestStillValid(requestID, isPerRunRetry: isPerRunRetry) else { return }

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

        if isRequestStillValid(requestID, isPerRunRetry: isPerRunRetry) {
            if !isPerRunRetry {
                currentRequestTask = nil
                activeRequestID = nil
            }

            // Signal view layer for satisfaction prompt if any model succeeded
            let hasSuccess = modelRuns.contains { run in
                if case .success = run.status { return true }
                return false
            }
            if hasSuccess {
                successfulTranslationCount += 1
                if AppPreferences.shared.shouldShowSatisfactionPrompt {
                    showSatisfactionPrompt = true
                }
            }
        }
    }

    private func cancelActiveRequest(clearResults: Bool) {
        currentRequestTask?.cancel()
        currentRequestTask = nil
        activeRequestID = nil
        pendingAppleTranslateText = nil
        pendingAppleTranslateAction = nil
        pendingAppleTranslateRequestID = nil
        pendingAppleTranslateResolvedTarget = nil
        appleTranslateSourceLanguage = nil
        appleTranslateTargetLanguage = nil
        detectedSourceLanguage = nil
        if clearResults {
            if !modelRuns.isEmpty { modelRuns = [] }
            targetLanguageOverride = nil
        }
    }

    // MARK: - Apple Translation Execution

    /// Called from HomeView's `.translationTask()` callback once a TranslationSession is available.
    #if canImport(Translation)
        @available(iOS 17.4, macOS 14.4, *)
        public func executeAppleTranslation(session: TranslationSession) {
            logger.debug("executeAppleTranslation: hasText=\(self.pendingAppleTranslateText != nil, privacy: .public), hasAction=\(self.pendingAppleTranslateAction != nil, privacy: .public)")
            guard let text = pendingAppleTranslateText,
                  let action = pendingAppleTranslateAction,
                  let requestID = pendingAppleTranslateRequestID
            else {
                logger.error("executeAppleTranslation: missing pending state, aborting (text=\(self.pendingAppleTranslateText != nil, privacy: .public), action=\(self.pendingAppleTranslateAction != nil, privacy: .public), requestID=\(self.pendingAppleTranslateRequestID != nil, privacy: .public))")
                return
            }

            // Clear pending state.
            let resolvedTarget = pendingAppleTranslateResolvedTarget ?? AppPreferences.shared.targetLanguage
            pendingAppleTranslateText = nil
            pendingAppleTranslateAction = nil
            pendingAppleTranslateRequestID = nil
            pendingAppleTranslateResolvedTarget = nil
            appleTranslateSourceLanguage = nil
            appleTranslateTargetLanguage = nil

            Task { [weak self] in
                guard let self else { return }
                do {
                    let result: ModelExecutionResult
                    if action.outputType == .sentencePairs {
                        result = try await AppleTranslationService.shared.translateSentences(
                            text: text, using: session
                        )
                    } else {
                        result = try await AppleTranslationService.shared.translate(
                            text: text, using: session
                        )
                    }
                    guard self.activeRequestID == requestID else { return }
                    self.apply(result: result, allowDiff: false)

                    if case let .success(message) = result.response,
                       let idx = self.modelRuns.firstIndex(where: { $0.id == result.modelID })
                    {
                        TranslationHistoryService.shared.save(
                            requestID: requestID,
                            sourceText: self.currentRequestInputText,
                            resultText: message,
                            actionName: action.name,
                            targetLanguage: resolvedTarget.englishName,
                            modelID: result.modelID,
                            modelDisplayName: self.modelRuns[idx].modelDisplayName,
                            duration: result.duration
                        )
                    }
                } catch {
                    logger.error("executeAppleTranslation failed: \(String(describing: error), privacy: .public)")
                    guard self.activeRequestID == requestID else { return }
                    let failResult = ModelExecutionResult(
                        modelID: ModelConfig.appleTranslateID,
                        duration: 0,
                        response: .failure(LocalProviderError.translationFailed(error.localizedDescription))
                    )
                    self.apply(result: failResult, allowDiff: false)
                }
            }
        }
    #endif

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
            let failedRun = modelRuns.remove(at: index)
            modelRuns.append(failedRun)
        }
    }

    private func refreshActions() {
        actions = allActions
        logger.debug("refreshActions() — \(self.allActions.count, privacy: .public) total")

        guard !allActions.isEmpty else {
            selectedActionID = nil
            return
        }

        if let selectedID = selectedActionID,
           allActions.contains(where: { $0.id == selectedID })
        {
            return
        }

        selectedActionID = allActions.first?.id
    }
}
