//
//  ExtensionCompactView.swift
//  ShareCore
//
//  Created by AI Assistant on 2026/01/04.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
    import SwiftUI
    import TranslationUIProvider

    /// A compact view for iOS Translation Extension, mirroring the Mac MenuBarPopoverView style
    public struct ExtensionCompactView: View {
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.openURL) private var openURL
        @StateObject private var viewModel: HomeViewModel
        @ObservedObject private var preferences = AppPreferences.shared
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
                    Logger.debug("[ExtCompactView] onAppear — \(viewModel.actions.count) actions loaded")
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
                // TranslationUIProviderContext doesn't always emit reliable SwiftUI/Observation
                // change notifications for inputText. To ensure we always pick up the selected
                // text from the host app, do a short best-effort poll on appear.
                //
                // We stop early once we have non-empty text.
                for delayMs in [0, 150, 400, 800, 1500] {
                    if Task.isCancelled { break }
                    if delayMs > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                    }
                    syncContextText()
                    if !displayText.isEmpty { break }
                }
            }
            .onChange(of: context.allowsReplacement) {
                viewModel.updateUsageScene(usageScene)
            }
            .onChange(of: preferences.targetLanguage) {
                // Re-trigger translation when the user manually changes the target language
                guard hasTriggeredAutoRequest, !displayText.isEmpty else { return }
                viewModel.overrideTargetLanguage(preferences.targetLanguage)
            }
            #if DEBUG
            .sheet(item: $viewModel.selectedDebugNetworkRecord) { record in
                NavigationStack {
                    NetworkRequestDetailView(record: record)
                }
            }
            #endif
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
                Text("Translate to", comment: "Label before the target language picker in the extension")
                    .font(.system(size: 13))
                    .foregroundColor(colors.textSecondary)

                LanguageSwitcherView(
                    globeFont: .system(size: 12),
                    textFont: .system(size: 13, weight: .medium),
                    chevronFont: .system(size: 8),
                    foregroundColor: colors.accent
                )

                if let resolved = viewModel.resolvedTargetLanguage {
                    Menu {
                        let preferred = AppPreferences.shared.targetLanguage
                        if resolved != preferred {
                            Button {
                                viewModel.overrideTargetLanguage(preferred)
                            } label: {
                                Label(preferred.primaryLabel, systemImage: "arrow.uturn.backward")
                            }
                            Divider()
                        }
                        ForEach(TargetLanguageOption.filteredSelectionOptions(
                            appleTranslateEnabled: preferences.enabledModelIDs.contains(ModelConfig.appleTranslateID),
                            installedLanguages: preferences.appleTranslateInstalledLanguages
                        ).filter { $0 != resolved }) { option in
                            Button(option.primaryLabel) {
                                viewModel.overrideTargetLanguage(option)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                            Text(resolved.primaryLabel)
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 7))
                                .opacity(0.6)
                        }
                        .foregroundColor(colors.textSecondary)
                    }
                    .fixedSize()
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
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
            let showModelName = true
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.modelRuns) { run in
                        #if DEBUG
                            let inspectRequest: (() -> Void)? = {
                                viewModel.presentDebugRequestDetails(for: run.id)
                            }
                        #else
                            let inspectRequest: (() -> Void)? = nil
                        #endif

                        ProviderResultCardView(
                            run: run,
                            showModelName: showModelName,
                            viewModel: viewModel,
                            onCopy: { text in
                                PasteboardHelper.copy(text)
                            },
                            onReplace: context.allowsReplacement ? { text in
                                context.finish(translation: AttributedString(text))
                            } : nil,
                            onChat: run.model.isLocal ? nil : {
                                if let session = viewModel.createConversation(from: run) {
                                    activeConversationSession = session
                                }
                            },
                            onSuggestedAction: run.model.isLocal ? nil : { action in
                                if let session = viewModel.createConversationWithFollowUp(from: run, followUp: action) {
                                    activeConversationSession = session
                                }
                            },
                            onInspectRequest: inspectRequest
                        )
                    }

                    openInAppBar
                }
            }
        }

        private var openInAppBar: some View {
            Button {
                openInMainApp()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 14, weight: .medium))
                    Text("Open in TLingo", comment: "Button in extension to open selected text in the main app")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(colors.accent.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }

        private func openInMainApp() {
            guard let url = DeepLink.translateURL(
                text: displayText,
                actionName: viewModel.selectedAction?.name,
                configName: AppConfigurationStore.shared.currentConfigurationName
            ) else { return }
            openURL(url)
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
