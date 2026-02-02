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
            cancelActiveRequest(clearResults: true)
        }
    }

    @Published public private(set) var actions: [ActionConfig]
    @Published public private(set) var models: [ModelConfig] = []
    @Published public var selectedActionID: UUID?
    @Published public private(set) var modelRuns: [ModelRunViewState] = []
    @Published public private(set) var isLoadingConfiguration: Bool = true

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
    private var currentRequestInputText: String = ""
    private var currentActionShowsDiff: Bool = false

    public init(
        configurationStore: AppConfigurationStore? = nil,
        llmService: LLMService = .shared,
        preferences: AppPreferences = .shared,
        usageScene: ActionConfig.UsageScene = .app
    ) {
        let store = configurationStore ?? .shared
        self.configurationStore = store
        self.llmService = llmService
        self.preferences = preferences
        self.usageScene = usageScene
        allActions = store.actions
        selectedActionID = store.defaultAction?.id
        actions = []
        isLoadingConfiguration = true

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

        isLoadingConfiguration = false
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
        if enabledIDs.isEmpty {
            return models.filter { $0.isDefault }
        }
        return models.filter { enabledIDs.contains($0.id) }
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
        guard !text.isEmpty else {
            Logger.debug("[HomeViewModel] Input text is empty; skipping request.")
            modelRuns = []
            return
        }

        currentRequestInputText = text
        currentActionShowsDiff = action.showsDiff

        let modelsToUse = getEnabledModels()

        guard !modelsToUse.isEmpty else {
            Logger.debug("[HomeViewModel] No enabled models configured.")
            modelRuns = []
            return
        }

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
                models: modelsToUse
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

    deinit {
        currentRequestTask?.cancel()
    }

    private func executeRequest(
        requestID: UUID,
        text: String,
        action: ActionConfig,
        models: [ModelConfig]
    ) async {
        guard !Task.isCancelled else { return }

        let results = await llmService.perform(
            text: text,
            with: action,
            models: models,
            partialHandler: { [weak self] modelID, update in
                guard let self else { return }
                guard self.activeRequestID == requestID else { return }
                guard let index = self.modelRuns.firstIndex(where: { $0.id == modelID }) else {
                    return
                }
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
                    let diff = currentActionShowsDiff ? TextDiffBuilder.build(
                        original: currentRequestInputText,
                        revised: diffTarget
                    ) : nil
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
            let diff = allowDiff ? TextDiffBuilder.build(original: currentRequestInputText, revised: diffTarget) : nil
            modelRuns[index].status = .success(
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
