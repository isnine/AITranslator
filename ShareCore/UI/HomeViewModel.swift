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
            case success(text: String, duration: TimeInterval)
            case failure(message: String, duration: TimeInterval)

            var duration: TimeInterval? {
                switch self {
                case .idle, .running:
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
            if case .running = status { return true }
            return false
        }
    }

    @Published var inputText: String = ""
    @Published private(set) var actions: [ActionConfig]
    @Published private(set) var providers: [ProviderConfig]
    @Published var selectedActionID: UUID?
    @Published private(set) var providerRuns: [ProviderRunViewState] = []

    let placeholderHint: String = "输入文本并选择操作开始使用"
    let inputPlaceholder: String = "输入要翻译或处理的文本…"

    private let configurationStore: AppConfigurationStore
    private let llmService: LLMService
    private var cancellables = Set<AnyCancellable>()

    init(
        configurationStore: AppConfigurationStore = .shared,
        llmService: LLMService = .shared
    ) {
        self.configurationStore = configurationStore
        self.actions = configurationStore.actions
        self.providers = configurationStore.providers
        self.llmService = llmService
        self.selectedActionID = configurationStore.defaultAction?.id

        configurationStore.$actions
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.actions = $0
                if let selectedID = self.selectedActionID, $0.contains(where: { $0.id == selectedID }) {
                    return
                }
                self.selectedActionID = $0.first?.id
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

    func performSelectedAction() async {
        guard let action = selectedAction else {
            print("No action selected.")
            return
        }

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            print("Input text is empty; skipping request.")
            return
        }

        let mappedProviders = providers.filter { action.providerIDs.contains($0.id) }
        let providersToUse = mappedProviders.isEmpty ? providers.prefix(1).map { $0 } : mappedProviders

        guard !providersToUse.isEmpty else {
            print("No providers configured.")
            return
        }

        providerRuns = providersToUse.map {
            ProviderRunViewState(provider: $0, status: .running(start: Date()))
        }

        let results = await llmService.perform(
            text: text,
            with: action,
            providers: Array(providersToUse)
        )

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
    }

    func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(settingsURL)
    }
}
