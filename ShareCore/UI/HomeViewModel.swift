//
//  HomeViewModel.swift
//  AITranslator
//
//  Created by Zander Wang on 2025/10/19.
//
import SwiftUI
import Combine
import UIKit
import TranslationUIProvider

@MainActor
final class HomeViewModel: ObservableObject {
    struct ProviderRunViewState: Identifiable {
        enum Status {
            case idle
            case running(start: Date)
            case streaming(text: String, start: Date)
            case success(text: String, duration: TimeInterval)
            case failure(message: String, duration: TimeInterval)

            var duration: TimeInterval? {
                switch self {
                case .idle, .running, .streaming:
                    return nil
                case let .success(_, duration),
                     let .failure(_, duration):
                    return duration
                }
            }
        }

        let provider: ProviderConfig
        var status: Status

        var id: UUID { provider.id }

        var durationText: String? {
            guard let duration = status.duration else { return nil }
            return String(format: "%.1fs", duration)
        }

        var isRunning: Bool {
            switch status {
            case .running, .streaming:
                return true
            default:
                return false
            }
        }

        var startDate: Date? {
            switch status {
            case let .running(start), let .streaming(_, start):
                return start
            default:
                return nil
            }
        }
    }

    @Published var inputText: String = "" {
        didSet {
            guard inputText != oldValue else { return }
            cancelActiveRequest(clearResults: true)
        }
    }
    @Published private(set) var actions: [ActionConfig]
    @Published private(set) var providers: [ProviderConfig]
    @Published var selectedActionID: UUID?
    @Published private(set) var providerRuns: [ProviderRunViewState] = []

    let placeholderHint: String = "输入文本并选择操作开始使用"
    let inputPlaceholder: String = "输入要翻译或处理的文本…"

    private let configurationStore: AppConfigurationStore
    private let llmService: LLMService
    private var cancellables = Set<AnyCancellable>()
    private var currentRequestTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var allActions: [ActionConfig]
    private var usageScene: ActionConfig.UsageScene

    init(
        configurationStore: AppConfigurationStore = .shared,
        llmService: LLMService = .shared,
        usageScene: ActionConfig.UsageScene = .app
    ) {
        self.configurationStore = configurationStore
        self.llmService = llmService
        self.usageScene = usageScene
        self.allActions = configurationStore.actions
        self.providers = configurationStore.providers
        self.selectedActionID = configurationStore.defaultAction?.id
        self.actions = []

        refreshActions()

        configurationStore.$actions
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.allActions = $0
                self.refreshActions()
            }
            .store(in: &cancellables)

        configurationStore.$providers
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.providers = $0
            }
            .store(in: &cancellables)
    }

    var defaultAction: ActionConfig? {
        actions.first
    }

    var selectedAction: ActionConfig? {
        guard let id = selectedActionID else {
            return actions.first
        }
        return actions.first(where: { $0.id == id }) ?? actions.first
    }

    @discardableResult
    func selectAction(_ action: ActionConfig) -> Bool {
        guard selectedActionID != action.id else { return false }
        selectedActionID = action.id
        return true
    }

    func updateUsageScene(_ scene: ActionConfig.UsageScene) {
        guard usageScene != scene else { return }
        usageScene = scene
        refreshActions()
    }

    func performSelectedAction() {
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

        let mappedProviders = providers.filter { action.providerIDs.contains($0.id) }
        let providersToUse = mappedProviders.isEmpty ? providers.prefix(1).map { $0 } : mappedProviders

        guard !providersToUse.isEmpty else {
            print("No providers configured.")
            providerRuns = []
            return
        }

        let requestID = UUID()
        activeRequestID = requestID

        providerRuns = providersToUse.map {
            ProviderRunViewState(provider: $0, status: .running(start: Date()))
        }

        currentRequestTask = Task { [weak self] in
            await self?.executeRequest(
                requestID: requestID,
                text: text,
                action: action,
                providers: Array(providersToUse)
            )
        }
    }

    func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(settingsURL)
    }

    deinit {
        currentRequestTask?.cancel()
    }

    private func executeRequest(
        requestID: UUID,
        text: String,
        action: ActionConfig,
        providers: [ProviderConfig]
    ) async {
        guard !Task.isCancelled else { return }

        let results = await llmService.perform(
            text: text,
            with: action,
            providers: providers,
            partialHandler: { [weak self] providerID, partialText in
                guard let self else { return }
                guard self.activeRequestID == requestID else { return }
                guard let index = self.providerRuns.firstIndex(where: { $0.provider.id == providerID }) else {
                    return
                }
                let startDate = self.providerRuns[index].startDate ?? Date()
                self.providerRuns[index].status = .streaming(
                    text: partialText,
                    start: startDate
                )
            },
            completionHandler: { [weak self] result in
                guard let self else { return }
                guard self.activeRequestID == requestID else { return }
                guard let index = self.providerRuns.firstIndex(where: { $0.provider.id == result.providerID }) else {
                    return
                }

                switch result.response {
                case let .success(message):
                    self.providerRuns[index].status = .success(text: message, duration: result.duration)
                case let .failure(error):
                    self.providerRuns[index].status = .failure(message: error.localizedDescription, duration: result.duration)
                }
            }
        )

        guard !Task.isCancelled else { return }
        guard activeRequestID == requestID else { return }

        for result in results {
            if let index = providerRuns.firstIndex(where: { $0.provider.id == result.providerID }) {
                switch result.response {
                case let .success(message):
                    providerRuns[index].status = .success(text: message, duration: result.duration)
                case let .failure(error):
                    providerRuns[index].status = .failure(message: error.localizedDescription, duration: result.duration)
                }
            } else if let provider = providers.first(where: { $0.id == result.providerID }) {
                let runState: ProviderRunViewState.Status
                switch result.response {
                case let .success(message):
                    runState = .success(text: message, duration: result.duration)
                case let .failure(error):
                    runState = .failure(message: error.localizedDescription, duration: result.duration)
                }
                providerRuns.append(.init(provider: provider, status: runState))
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
