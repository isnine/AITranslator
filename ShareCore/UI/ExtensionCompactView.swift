//
//  ExtensionCompactView.swift
//  ShareCore
//
//  Created by AI Assistant on 2026/01/04.
//

#if canImport(UIKit) && canImport(TranslationUIProvider)
    import SwiftUI
    import TranslationUIProvider

    /// A compact view for iOS Translation Extension, mirroring the Mac MenuBarPopoverView style
    public struct ExtensionCompactView: View {
        @Environment(\.colorScheme) private var colorScheme
        @StateObject private var viewModel: HomeViewModel
        @State private var hasTriggeredAutoRequest = false
        @State private var activeConversationSession: ConversationSession?
        @State private var displayText: String = ""

        private let context: TranslationUIProviderContext

        private var colors: AppColorPalette {
            AppColors.palette(for: colorScheme)
        }

        private var usageScene: ActionConfig.UsageScene {
            context.allowsReplacement ? .contextEdit : .contextRead
        }

        public init(context: TranslationUIProviderContext) {
            self.context = context
            let initialScene: ActionConfig.UsageScene = context.allowsReplacement ? .contextEdit : .contextRead
            _viewModel = StateObject(wrappedValue: HomeViewModel(usageScene: initialScene))
        }

        /// Reads the current input text from the translation context.
        private func readContextText() -> String {
            guard let text = context.inputText else { return "" }
            return String(text.characters)
        }

        /// Syncs context text into local state and triggers action if non-empty.
        private func syncContextText() {
            let text = readContextText()
            guard text != displayText else { return }
            displayText = text
            viewModel.inputText = text
            if !text.isEmpty {
                viewModel.performSelectedAction()
            }
        }

        public var body: some View {
            ZStack {
                if let session = activeConversationSession {
                    ConversationContentView(
                        session: session,
                        onBack: { activeConversationSession = nil }
                    )
                    .transition(.move(edge: .trailing))
                } else {
                    translateContent
                        .transition(.move(edge: .leading))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: activeConversationSession != nil)
            .onAppear {
                AppPreferences.shared.refreshFromDefaults()

                if !hasTriggeredAutoRequest {
                    viewModel.refreshConfiguration()
                    viewModel.updateUsageScene(usageScene)
                    hasTriggeredAutoRequest = true

                    let text = readContextText()
                    displayText = text
                    viewModel.inputText = text
                    if !text.isEmpty {
                        viewModel.performSelectedAction()
                    }
                }
            }
            .task {
                guard displayText.isEmpty else { return }

                while !Task.isCancelled {
                    await withCheckedContinuation { continuation in
                        withObservationTracking {
                            _ = context.inputText
                        } onChange: {
                            continuation.resume()
                        }
                    }
                    guard !Task.isCancelled else { break }
                    syncContextText()
                    if !displayText.isEmpty { break }
                }
            }
            .onChange(of: context.allowsReplacement) {
                viewModel.updateUsageScene(usageScene)
            }
        }

        // MARK: - Translate Content

        private var translateContent: some View {
            ZStack {
                VStack(alignment: .leading, spacing: 12) {
                    headerBar

                    Divider()
                        .background(colors.divider)

                    actionChips

                    if !viewModel.modelRuns.isEmpty {
                        resultSection
                    } else if !viewModel.isLoadingConfiguration {
                        hintLabel
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)

                if viewModel.isLoadingConfiguration {
                    configurationLoadingOverlay
                }
            }
        }

        // MARK: - Header Bar

        private var headerBar: some View {
            HStack(spacing: 8) {
                LanguageSwitcherView(
                    globeFont: .system(size: 12),
                    textFont: .system(size: 13, weight: .medium),
                    chevronFont: .system(size: 8),
                    foregroundColor: colors.textSecondary
                )

                if let resolved = viewModel.resolvedTargetLanguage {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text(resolved.primaryLabel)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(colors.textSecondary)
                }

                Spacer(minLength: 0)

                inputSpeakButton

                chatButton
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }

        @ViewBuilder
        private var inputSpeakButton: some View {
            let hasText = !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button {
                if viewModel.isSpeakingInputText {
                    viewModel.stopSpeaking()
                } else {
                    viewModel.speakInputText()
                }
            } label: {
                Image(systemName: viewModel.isSpeakingInputText ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(viewModel.isSpeakingInputText ? colors.error : colors.accent)
            }
            .buttonStyle(.plain)
            .disabled(!hasText && !viewModel.isSpeakingInputText)
        }

        private var chatButton: some View {
            Button {
                if let session = viewModel.createContextConversation(contextText: viewModel.inputText) {
                    activeConversationSession = session
                }
            } label: {
                Image(systemName: "text.bubble")
                    .font(.system(size: 14))
                    .foregroundColor(colors.accent)
            }
            .buttonStyle(.plain)
        }

        // MARK: - Action Chips

        private var actionChips: some View {
            ActionChipsView(
                actions: viewModel.actions,
                selectedActionID: viewModel.selectedAction?.id,
                spacing: 8,
                font: .system(size: 13, weight: .medium),
                textColor: { isSelected in
                    isSelected ? .white : colors.textSecondary
                },
                background: { isSelected in
                    chipBackground(isSelected: isSelected)
                },
                horizontalPadding: 14,
                verticalPadding: 8
            ) { action in
                if viewModel.selectAction(action) {
                    viewModel.performSelectedAction()
                }
            }
        }

        // MARK: - Hint Label

        private var hintLabel: some View {
            Text(viewModel.placeholderHint)
                .font(.system(size: 13))
                .foregroundColor(colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }

        // MARK: - Result Section

        @ViewBuilder
        private var resultSection: some View {
            let showModelName = viewModel.modelRuns.count > 1
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.modelRuns) { run in
                        ProviderResultCardView(
                            run: run,
                            showModelName: showModelName,
                            viewModel: viewModel,
                            onCopy: { text in
                                UIPasteboard.general.string = text
                            },
                            onReplace: context.allowsReplacement ? { text in
                                context.finish(translation: AttributedString(text))
                            } : nil,
                            onChat: {
                                if let session = viewModel.createConversation(from: run) {
                                    activeConversationSession = session
                                }
                            }
                        )
                    }
                }
            }
        }

        // MARK: - Loading Overlay

        private var configurationLoadingOverlay: some View {
            LoadingOverlay(
                backgroundColor: Color(UIColor.systemBackground).opacity(0.95),
                messageFont: .system(size: 13),
                textColor: colors.textSecondary,
                accentColor: colors.accent
            )
        }

        // MARK: - Backgrounds

        @ViewBuilder
        private func chipBackground(isSelected: Bool) -> some View {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colors.accent)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
    }
#endif
