//
//  HomeView.swift
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

    func selectAction(_ action: ActionConfig) {
        selectedActionID = action.id
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

public struct HomeView: View {
  @StateObject private var viewModel = HomeViewModel()
  @State private var hasTriggeredAutoRequest = false
  @State private var isInputExpanded: Bool
  var openFromExtension: Bool {
    context != nil
  }
  let context: TranslationUIProviderContext?


  public init(context: TranslationUIProviderContext?) {
    self.context = context
    _isInputExpanded = State(initialValue: context == nil)
  }

  public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
              if !openFromExtension {
                header
                defaultAppCard
              }
                inputComposer
                actionChips
                if viewModel.providerRuns.isEmpty {
                    hintLabel
                } else {
                    providerResultsSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
        .background(AppColors.background.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .onAppear {
          guard openFromExtension, !hasTriggeredAutoRequest else { return }
          if let inputText = context?.inputText {
            viewModel.inputText = String(inputText.characters)
          }
          hasTriggeredAutoRequest = true
          Task {
            await viewModel.performSelectedAction()
          }
        }
    }

    private var header: some View {
        Text("AITranslator")
            .font(.system(size: 28, weight: .semibold))
            .foregroundColor(AppColors.textPrimary)
    }

    private var defaultAppCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(AppColors.accent)
                    .font(.system(size: 20))

                Text("将 AITranslator 设为系统默认翻译应用")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppColors.textPrimary)
            }

            Button(action: viewModel.openAppSettings) {
                Text("尝试一下")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppColors.cardBackground)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(AppColors.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.cardBackground)
        )
    }

    private var inputComposer: some View {
        let isCollapsed = openFromExtension && !isInputExpanded

        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.inputBackground)

            VStack(alignment: .leading, spacing: 0) {
                if isCollapsed {
                    collapsedInputSummary
                } else {
                    expandedInputEditor
                }

                if !isCollapsed {
                    Spacer(minLength: 0)
                }
            }
            .padding(.bottom, isCollapsed ? 0 : 16)

            if shouldShowSendButton {
                Button {
                    Task {
                        await viewModel.performSelectedAction()
                    }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.chipPrimaryText)
                        .padding(16)
                        .background(
                            Circle()
                                .fill(AppColors.accent)
                        )
                }
                .buttonStyle(.plain)
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: isCollapsed ? 64 : 170)
        .animation(.easeInOut(duration: 0.2), value: isInputExpanded)
    }

    private var shouldShowSendButton: Bool {
        !(openFromExtension && !isInputExpanded)
    }

    private var collapsedInputSummary: some View {
        HStack(spacing: 12) {
            let displayText = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(displayText.isEmpty ? viewModel.inputPlaceholder : displayText)
                .font(.system(size: 15))
                .foregroundColor(displayText.isEmpty ? AppColors.textSecondary : AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isInputExpanded = true
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var expandedInputEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if viewModel.inputText.isEmpty {
                    Text(viewModel.inputPlaceholder)
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }

                TextEditor(text: $viewModel.inputText)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(AppColors.textPrimary)
                    .padding(12)
                    .frame(minHeight: 140, maxHeight: 160)
            }

            if openFromExtension {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isInputExpanded = false
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.trailing, shouldShowSendButton ? 48 : 0)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private var actionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.actions) { action in
                    chip(for: action, isSelected: action.id == viewModel.selectedAction?.id)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(for action: ActionConfig, isSelected: Bool) -> some View {
        Button {
            viewModel.selectAction(action)
        } label: {
            Text(action.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? AppColors.chipPrimaryText : AppColors.chipSecondaryText)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? AppColors.chipPrimaryBackground : AppColors.chipSecondaryBackground)
                )
        }
        .buttonStyle(.plain)
    }

    private var hintLabel: some View {
        Text(viewModel.placeholderHint)
            .font(.system(size: 14))
            .foregroundColor(AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }

    private var providerResultsSection: some View {
        VStack(spacing: 16) {
            ForEach(viewModel.providerRuns) { run in
                providerResultCard(for: run)
            }
        }
    }

    private func providerResultCard(for run: HomeViewModel.ProviderRunViewState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                statusIndicator(for: run.status)

                VStack(alignment: .leading, spacing: 2) {
                    Text(run.provider.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppColors.textPrimary)
                    Text(run.provider.modelName)
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                if let duration = run.durationText {
                    Text(duration)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            content(for: run.status, providerName: run.provider.displayName)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColors.cardBackground)
        )
    }

    @ViewBuilder
    private func content(
        for status: HomeViewModel.ProviderRunViewState.Status,
        providerName: String
    ) -> some View {
        switch status {
        case .idle, .running:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppColors.skeleton)
                        .frame(height: 10)
                }
            }
        case let .success(text, _):
            VStack(alignment: .leading, spacing: 12) {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textPrimary)
                HStack(spacing: 16) {
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accent)

                    if let context, context.allowsReplacement {
                        Button {
                            context.finish(translation: AttributedString(text))
                        } label: {
                            Label("替换", systemImage: "arrow.left.arrow.right")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(AppColors.accent)
                    }
                }
            }
        case let .failure(message, _):
            VStack(alignment: .leading, spacing: 10) {
                Text("请求失败")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppColors.error)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func statusIndicator(
        for status: HomeViewModel.ProviderRunViewState.Status
    ) -> some View {
        switch status {
        case .idle, .running:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(AppColors.accent)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppColors.success)
                .font(.system(size: 18))
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.error)
                .font(.system(size: 18))
        }
    }
}

#Preview {
  HomeView(context: nil)
        .preferredColorScheme(.dark)
}
