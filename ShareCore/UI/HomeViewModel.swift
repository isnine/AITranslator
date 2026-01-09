//
//  HomeViewModel.swift
//  TLingo
//
//  Created by Zander Wang on 2025/10/19.
//
import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

@MainActor
public final class HomeViewModel: ObservableObject {
    public struct ProviderRunViewState: Identifiable {
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
            case failure(message: String, duration: TimeInterval)

            public var duration: TimeInterval? {
                switch self {
                case .idle, .running, .streaming, .streamingSentencePairs:
                    return nil
                case let .success(_, _, duration, _, _, _),
                     let .failure(_, duration):
                    return duration
                }
            }
        }

        public let provider: ProviderConfig
        public let deployment: String
        public var status: Status
        /// Whether to show diff view (only applicable when diff is available)
        public var showDiff: Bool = true

        /// Use a composite id to uniquely identify provider + deployment
        public var id: String { "\(provider.id.uuidString)-\(deployment)" }

        /// Model name for display (shows deployment name)
        public var modelDisplayName: String { deployment }

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
    @Published public private(set) var providers: [ProviderConfig]
    @Published public var selectedActionID: UUID?
    @Published public private(set) var providerRuns: [ProviderRunViewState] = []
    @Published public private(set) var speakingProviders: Set<String> = []
    @Published public private(set) var isSpeakingInputText: Bool = false
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
    private let textToSpeechService: TextToSpeechService
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
        textToSpeechService: TextToSpeechService = .shared,
        usageScene: ActionConfig.UsageScene = .app
    ) {
        let store = configurationStore ?? .shared
        self.configurationStore = store
        self.llmService = llmService
        self.textToSpeechService = textToSpeechService
        self.usageScene = usageScene
        self.allActions = store.actions
        self.providers = store.providers
        self.selectedActionID = store.defaultAction?.id
        self.actions = []
        self.isLoadingConfiguration = true

        refreshActions()

        store.$actions
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.allActions = $0
                self.refreshActions()
            }
            .store(in: &cancellables)

        store.$providers
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.providers = $0
            }
            .store(in: &cancellables)

        // Configuration is already loaded from the store's init
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

    /// Refresh configuration from store before performing actions.
    /// This ensures the extension/popover has the latest configuration.
    public func refreshConfiguration() {
        isLoadingConfiguration = true

        // Reload configuration from the store
        configurationStore.reloadCurrentConfiguration()

        // Update local state from refreshed store
        allActions = configurationStore.actions
        providers = configurationStore.providers
        refreshActions()

        // Update selected action to match the new configuration
        if let firstAction = actions.first {
            selectedActionID = firstAction.id
        }

        isLoadingConfiguration = false
    }

    /// Returns true if the Send button should be enabled.
    /// Disabled when: no actions available, or no enabled deployments across all providers.
    public var canSend: Bool {
        guard selectedAction != nil else {
            return false
        }
        // Check if any provider has enabled deployments
        return providers.contains { !$0.enabledDeployments.isEmpty }
    }

    /// Get all enabled provider deployments across all providers
    private func getAllEnabledDeployments() -> [(provider: ProviderConfig, deployment: String)] {
        var result: [(provider: ProviderConfig, deployment: String)] = []
        
        for provider in providers {
            for deployment in provider.deployments where provider.enabledDeployments.contains(deployment) {
                result.append((provider: provider, deployment: deployment))
            }
        }
        
        return result
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
            print("No action selected.")
            providerRuns = []
            return
        }

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            print("Input text is empty; skipping request.")
            providerRuns = []
            return
        }

        currentRequestInputText = text
        currentActionShowsDiff = action.showsDiff

        // Use all enabled deployments across all providers
        let deploymentsToUse = getAllEnabledDeployments()

        guard !deploymentsToUse.isEmpty else {
            print("No enabled deployments configured.")
            providerRuns = []
            return
        }

        let requestID = UUID()
        activeRequestID = requestID

        providerRuns = deploymentsToUse.map {
            ProviderRunViewState(provider: $0.provider, deployment: $0.deployment, status: .running(start: Date()))
        }

        currentRequestTask = Task { [weak self] in
            await self?.executeRequest(
                requestID: requestID,
                text: text,
                action: action,
                providerDeployments: deploymentsToUse
            )
        }
    }

    public func speakResult(_ text: String, runID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !speakingProviders.contains(runID) else { return }

        speakingProviders.insert(runID)

        _ = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.textToSpeechService.speak(text: trimmed)
            } catch {
                print("TTS playback failed for run \(runID): \(error)")
            }
            _ = await MainActor.run { [weak self] in
                self?.speakingProviders.remove(runID)
            }
        }
    }

    /// Speak the input text using TTS
    public func speakInputText() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isSpeakingInputText else { return }

        isSpeakingInputText = true

        _ = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.textToSpeechService.speak(text: trimmed)
            } catch {
                print("TTS playback failed for input text: \(error)")
            }
            _ = await MainActor.run { [weak self] in
                self?.isSpeakingInputText = false
            }
        }
    }

    public func isSpeaking(runID: String) -> Bool {
        speakingProviders.contains(runID)
    }

    /// Toggle diff display for a specific provider run
    public func toggleDiffDisplay(for runID: String) {
        guard let index = providerRuns.firstIndex(where: { $0.id == runID }) else {
            return
        }
        providerRuns[index].showDiff.toggle()
    }

    /// Check if diff is available for a specific provider run
    public func hasDiff(for runID: String) -> Bool {
        guard let run = providerRuns.first(where: { $0.id == runID }) else {
            return false
        }
        switch run.status {
        case let .success(_, _, _, diff, _, _):
            return diff != nil
        default:
            return false
        }
    }

    /// Check if diff is currently shown for a specific provider run
    public func isDiffShown(for runID: String) -> Bool {
        guard let run = providerRuns.first(where: { $0.id == runID }) else {
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
        providerDeployments: [(provider: ProviderConfig, deployment: String)]
    ) async {
        guard !Task.isCancelled else { return }

        let results = await llmService.perform(
            text: text,
            with: action,
            providerDeployments: providerDeployments,
            partialHandler: { [weak self] providerID, deployment, update in
                guard let self else { return }
                guard self.activeRequestID == requestID else { return }
                let compositeID = "\(providerID.uuidString)-\(deployment)"
                guard let index = self.providerRuns.firstIndex(where: { $0.id == compositeID }) else {
                    return
                }
                let startDate = self.providerRuns[index].startDate ?? Date()
                switch update {
                case let .text(partialText):
                    self.providerRuns[index].status = .streaming(
                        text: partialText,
                        start: startDate
                    )
                case let .sentencePairs(pairs):
                    self.providerRuns[index].status = .streamingSentencePairs(
                        pairs: pairs,
                        start: startDate
                    )
                }
            },
            completionHandler: { [weak self] result in
                guard let self else { return }
                guard self.activeRequestID == requestID else { return }
                self.apply(result: result, deployment: result.deployment, allowDiff: self.currentActionShowsDiff)
            }
        )

        guard !Task.isCancelled else { return }
        guard activeRequestID == requestID else { return }

        for result in results {
            let compositeID = "\(result.providerID.uuidString)-\(result.deployment)"
            if providerRuns.contains(where: { $0.id == compositeID }) {
                apply(result: result, deployment: result.deployment, allowDiff: currentActionShowsDiff)
            } else if let providerDeployment = providerDeployments.first(where: { $0.provider.id == result.providerID && $0.deployment == result.deployment }) {
                let runState: ProviderRunViewState.Status
                switch result.response {
                case let .success(message):
                    let diffTarget = result.diffSource ?? message
                    let diff = currentActionShowsDiff ? TextDiffBuilder.build(original: currentRequestInputText, revised: diffTarget) : nil
                    runState = .success(
                        text: message,
                        copyText: diffTarget,
                        duration: result.duration,
                        diff: diff,
                        supplementalTexts: result.supplementalTexts,
                        sentencePairs: result.sentencePairs
                    )
                case let .failure(error):
                    runState = .failure(message: error.localizedDescription, duration: result.duration)
                }
                providerRuns.append(.init(provider: providerDeployment.provider, deployment: result.deployment, status: runState))
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
            providerRuns = []
        }
    }

    private func apply(result: ProviderExecutionResult, deployment: String, allowDiff: Bool) {
        let compositeID = "\(result.providerID.uuidString)-\(deployment)"
        guard let index = providerRuns.firstIndex(where: { $0.id == compositeID }) else {
            return
        }

        switch result.response {
        case let .success(message):
            let diffTarget = result.diffSource ?? message
            let diff = allowDiff ? TextDiffBuilder.build(original: currentRequestInputText, revised: diffTarget) : nil
            providerRuns[index].status = .success(
                text: message,
                copyText: diffTarget,
                duration: result.duration,
                diff: diff,
                supplementalTexts: result.supplementalTexts,
                sentencePairs: result.sentencePairs
            )
        case let .failure(error):
            providerRuns[index].status = .failure(message: error.localizedDescription, duration: result.duration)
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
           filtered.contains(where: { $0.id == selectedID }) {
            return
        }

        selectedActionID = filtered.first?.id
    }
}
