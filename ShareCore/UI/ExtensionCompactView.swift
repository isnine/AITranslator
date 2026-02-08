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

        private let context: TranslationUIProviderContext

        private var colors: AppColorPalette {
            AppColors.palette(for: colorScheme)
        }

        private var usageScene: ActionConfig.UsageScene {
            context.allowsReplacement ? .contextEdit : .contextRead
        }

        private var inputText: String {
            guard let text = context.inputText else { return "" }
            return String(text.characters)
        }

        public init(context: TranslationUIProviderContext) {
            self.context = context
            let initialScene: ActionConfig.UsageScene = context.allowsReplacement ? .contextEdit : .contextRead
            _viewModel = StateObject(wrappedValue: HomeViewModel(usageScene: initialScene))
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
                    viewModel.inputText = inputText
                    hasTriggeredAutoRequest = true
                    viewModel.performSelectedAction()
                }
            }
            // When the user changes the selection in the host app, the system may reuse the same
            // extension instance and only update the context's selected text. We need to re-run the
            // currently selected action so results update immediately (without requiring the user to
            // switch actions back-and-forth).
            .onChange(of: inputText) {
                guard hasTriggeredAutoRequest else { return }
                // Avoid redundant requests.
                guard viewModel.inputText != inputText else { return }

                viewModel.inputText = inputText
                if !inputText.isEmpty {
                    viewModel.performSelectedAction()
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
                    selectedTextPreview

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

        // MARK: - Selected Text Preview

        private var selectedTextPreview: some View {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12))
                    // Use system dynamic colors instead of relying on SwiftUI colorScheme in the
                    // Translation UI extension; iOS 26 + Liquid Glass can produce unexpected
                    // foreground contrast if we pin to a palette value.
                    .foregroundStyle(.secondary)

                Text(inputText)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                inputSpeakButton

                LanguageSwitcherView(
                    globeFont: .system(size: 10),
                    textFont: .system(size: 11, weight: .medium),
                    chevronFont: .system(size: 7),
                    foregroundColor: colors.textSecondary.opacity(0.7)
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selectedTextPreviewBackground)
        }

        @ViewBuilder
        private var inputSpeakButton: some View {
            let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button {
                if viewModel.isSpeakingInputText {
                    viewModel.stopSpeaking()
                } else {
                    viewModel.speakInputText()
                }
            } label: {
                Image(systemName: viewModel.isSpeakingInputText ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundColor(viewModel.isSpeakingInputText ? colors.error : colors.accent)
            }
            .buttonStyle(.plain)
            .disabled(!hasText && !viewModel.isSpeakingInputText)
        }

        // MARK: - Action Chips

        private var actionChips: some View {
            ActionChipsView(
                actions: viewModel.actions,
                selectedActionID: viewModel.selectedAction?.id,
                spacing: 8,
                font: .system(size: 13, weight: .medium),
                // NOTE: In the iOS Translation UI extension we render chips using a glassEffect
                // background (not a solid accent fill). Using white text (chipPrimaryText) makes the
                // selected action illegible in Light Mode with Liquid Glass.
                textColor: { isSelected in
                    isSelected ? colors.textPrimary : colors.textSecondary
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

        // MARK: - Liquid Glass Backgrounds

        @ViewBuilder
        private var selectedTextPreviewBackground: some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 8))
        }

        @ViewBuilder
        private func chipBackground(isSelected: Bool) -> some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.clear)
                .glassEffect(isSelected ? .regular : .regular.interactive(), in: .rect(cornerRadius: 8))
        }
    }
#endif
