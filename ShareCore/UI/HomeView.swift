//
//  HomeView.swift
//  TLingo
//
//  Created by Zander Wang on 2025/10/19.
//

import StoreKit
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif
#if canImport(PhotosUI)
    import PhotosUI
#endif
#if os(iOS) && !targetEnvironment(macCatalyst)
    import TranslationUIProvider
#endif
import UniformTypeIdentifiers
import WebKit
#if canImport(Translation)
    import Translation
#endif

#if os(iOS) && !targetEnvironment(macCatalyst)
    public typealias AppTranslationContext = TranslationUIProviderContext
#else
    public typealias AppTranslationContext = Never
#endif

public struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.requestReview) private var requestReview
    @StateObject private var viewModel: HomeViewModel
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var hasTriggeredAutoRequest = false
    @State private var isInputExpanded: Bool
    @State private var showingProviderInfo: String?
    @State private var showDefaultAppGuide = false
    @State private var activeConversationSession: ConversationSession?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showSatisfactionToast = false
    #if canImport(Translation)
        @State private var appleTranslationConfig: TranslationSession.Configuration?
    #endif
    #if os(macOS)
        @State private var showDataConsent = false
    #endif
    @Namespace private var chipNamespace

    #if os(macOS)
        private var conversationInspectorBinding: Binding<Bool> {
            Binding(
                get: { activeConversationSession != nil },
                set: { if !$0 { activeConversationSession = nil } }
            )
        }
    #endif

    var openFromExtension: Bool {
        #if os(iOS)
            return context != nil
        #else
            return false
        #endif
    }

    private let context: AppTranslationContext?
    private let onHistoryTap: (() -> Void)?

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    /// Hides the keyboard on iOS
    private func hideKeyboard() {
        #if os(iOS)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private var shouldShowDefaultAppCard: Bool {
        #if os(macOS)
            return false
        #else
            return !preferences.defaultAppHintDismissed
        #endif
    }

    private var initialContextInput: String? {
        #if os(iOS)
            guard let inputText = context?.inputText else { return nil }
            return String(inputText.characters)
        #else
            return nil
        #endif
    }

    public init(context: AppTranslationContext? = nil, onHistoryTap: (() -> Void)? = nil) {
        self.context = context
        self.onHistoryTap = onHistoryTap
        _viewModel = StateObject(wrappedValue: HomeViewModel())
        #if os(iOS)
            _isInputExpanded = State(initialValue: context == nil)
        #else
            _isInputExpanded = State(initialValue: true)
        #endif
    }

    public var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !openFromExtension {
                        #if !os(macOS)
                            header
                        #endif
                        if shouldShowDefaultAppCard {
                            defaultAppCard
                        }
                        inputComposer
                    }
                    actionChips
                    if viewModel.modelRuns.isEmpty {
                        hintLabel
                    } else {
                        providerResultsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
            .background(colors.background.ignoresSafeArea())
            .scrollIndicators(.hidden)
            #if os(iOS)
                .onTapGesture {
                    hideKeyboard()
                }
            #endif

            // Loading overlay when configuration is loading
            if viewModel.isLoadingConfiguration {
                configurationLoadingOverlay
            }

            if showSatisfactionToast {
                VStack {
                    Spacer()
                    SatisfactionPromptView(
                        colors: colors,
                        onSatisfied: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showSatisfactionToast = false
                            }
                            requestReview()
                        },
                        onFeedback: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showSatisfactionToast = false
                            }
                            viewModel.openFeedbackEmail()
                        },
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showSatisfactionToast = false
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .task {
                    try? await Task.sleep(for: .seconds(10))
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSatisfactionToast = false
                    }
                }
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .onAppear {
            AppPreferences.shared.refreshFromDefaults()

            // In snapshot conversation mode, auto-present the conversation
            // sheet so the UI test doesn't need to find and tap the chat button.
            if HomeViewModel.isSnapshotConversationMode {
                // On macOS the inspector binding needs the view hierarchy to be
                // fully laid out before it will open. A short async delay ensures
                // the window and splitter have finished first layout.
                #if os(macOS)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        if let session = viewModel.createSnapshotConversationSession() {
                            activeConversationSession = session
                        }
                    }
                #else
                    if let session = viewModel.createSnapshotConversationSession() {
                        activeConversationSession = session
                    }
                #endif
            }

            #if os(iOS)
                // For extension context: refresh configuration first, then execute
                if openFromExtension, !hasTriggeredAutoRequest {
                    viewModel.refreshConfiguration()
                    if let inputText = initialContextInput {
                        viewModel.inputText = inputText
                    }
                    hasTriggeredAutoRequest = true
                    viewModel.performSelectedAction()
                }
            #endif
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .serviceTextReceived)) { notification in
            if let text = notification.userInfo?["text"] as? String {
                viewModel.inputText = text
                isInputExpanded = true
                viewModel.performSelectedAction()
            }
        }
        .onAppear {
            // Notify the host app (macOS only) so AppleTranslationWindowManager can register
            // this viewModel with the hidden translation window bridge.
            NotificationCenter.default.post(
                name: .appleTranslationViewModelRegister,
                object: nil,
                userInfo: ["viewModel": viewModel]
            )
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkTextReceived)) { notification in
            if let text = notification.userInfo?[DeepLink.NotificationKey.text] as? String {
                let configName = notification.userInfo?[DeepLink.NotificationKey.configName] as? String
                let actionName = notification.userInfo?[DeepLink.NotificationKey.actionName] as? String

                // Switch configuration if needed before looking up the action
                viewModel.applyDeepLink(text: text, actionName: actionName, configName: configName)
                isInputExpanded = true
            }
        }
        .onChange(of: viewModel.showSatisfactionPrompt) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showSatisfactionToast = true
                }
                AppPreferences.shared.markSatisfactionPromptShown()
                viewModel.showSatisfactionPrompt = false
            }
        }
        .sheet(isPresented: $showDefaultAppGuide) {
            DefaultAppGuideSheet(colors: colors, onOpenSettings: {
                viewModel.openAppSettings()
            }, onDismiss: {
                showDefaultAppGuide = false
            })
            .presentationDetents([.height(520)])
            .presentationDragIndicator(.visible)
        }
        #if os(macOS)
        .inspector(isPresented: conversationInspectorBinding) {
            if let session = activeConversationSession {
                ConversationContentView(session: session) {
                    activeConversationSession = nil
                }
                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
            }
        }
        #else
        .sheet(item: $activeConversationSession) { session in
                    ConversationView(session: session)
                        .presentationDetents(
                            HomeViewModel.isSnapshotConversationMode ? [.large] : [.medium, .large]
                        )
                        .presentationDragIndicator(
                            HomeViewModel.isSnapshotConversationMode ? .hidden : .visible
                        )
                }
        #endif
        #if DEBUG
        .sheet(item: $viewModel.selectedDebugNetworkRecord) { record in
                NavigationStack {
                    NetworkRequestDetailView(record: record)
                }
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 520)
                #endif
            }
        #endif
        #if os(macOS)
        .sheet(isPresented: $showDataConsent) {
            DataConsentView {
                preferences.setHasAcceptedDataSharing(true)
                viewModel.performSelectedAction()
            }
            .interactiveDismissDisabled()
        }
        .onChange(of: viewModel.showDataConsentRequest) { _, newValue in
            if newValue {
                showDataConsent = true
                viewModel.showDataConsentRequest = false
            }
        }
        #endif
        #if canImport(Translation)
        .translationTask(appleTranslationConfig) { session in
            Logger.debug("[HomeView] .translationTask fired, session received")
            if #available(iOS 17.4, macOS 14.4, *) {
                viewModel.executeAppleTranslation(session: session)
            }
        }
        .onChange(of: viewModel.appleTranslateTargetLanguage) { newTarget in
            Logger.debug("[HomeView] onChange appleTranslateTargetLanguage: \(String(describing: newTarget)), existingConfig=\(appleTranslationConfig != nil)")
            #if os(macOS)
            // On macOS, Apple Translate is routed through the hidden translation window
            // (AppleTranslationBridge) to avoid Code=14 / _EXUISceneSession errors.
            // HomeView's .translationTask is iOS-only; skip config updates on macOS.
            _ = newTarget
            #else
            if let target = newTarget {
                let sourceLocale = viewModel.appleTranslateSourceLanguage
                Logger.debug("[HomeView] Apple Translate config: source=\(sourceLocale.map { $0.languageCode?.identifier ?? "unknown" } ?? "nil (auto-detect)"), target=\(target.localeLanguage.languageCode?.identifier ?? "unknown")")
                if appleTranslationConfig != nil {
                    appleTranslationConfig?.invalidate()
                    appleTranslationConfig = nil
                    Task { @MainActor in
                        appleTranslationConfig = .init(source: sourceLocale, target: target.localeLanguage)
                    }
                } else {
                    appleTranslationConfig = .init(source: sourceLocale, target: target.localeLanguage)
                }
            }
            #endif
        }
        #endif
    }

    private var configurationLoadingOverlay: some View {
        LoadingOverlay(
            message: "Loading configuration...",
            backgroundColor: colors.background.opacity(0.9),
            messageFont: .system(size: 14),
            textColor: colors.textSecondary,
            accentColor: colors.accent,
            ignoresSafeArea: true
        )
    }

    private var header: some View {
        HStack {
            Text("TLingo")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(colors.textPrimary)
            Spacer()
            #if !os(macOS)
                if let onHistoryTap {
                    Button(action: onHistoryTap) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 20))
                            .foregroundColor(colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home_history_button")
                }
            #endif
        }
    }

    private var defaultAppCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(colors.accent)
                .font(.system(size: 18))

            Text("Set TLingo as the default translation app")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: {
                AppPreferences.shared.setDefaultAppHintDismissed(true)
                showDefaultAppGuide = true
            }) {
                Text("How to Set Up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.chipPrimaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(colors.accent)
                    )
            }
            .buttonStyle(.plain)

            Button {
                AppPreferences.shared.setDefaultAppHintDismissed(true)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                    .padding(5)
                    .background(
                        Circle()
                            .fill(colors.inputBackground)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(defaultAppCardBackground)
    }

    @ViewBuilder
    private var defaultAppCardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(colors.cardBackground)
    }

    @ViewBuilder
    private var inputComposerBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(colors.cardBackground)
    }

    private var inputComposer: some View {
        let isCollapsed = openFromExtension && !isInputExpanded

        return ZStack {
            inputComposerBackground

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
            .padding(.bottom, isCollapsed ? 0 : 48)

            VStack {
                Spacer()
                HStack {
                    if openFromExtension && !isCollapsed {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isInputExpanded = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Collapse")
                                    .font(.system(size: 14, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(colors.textSecondary)
                    }

                    if !isCollapsed {
                        LanguageSwitcherView(
                            globeFont: .system(size: 12),
                            textFont: .system(size: 13, weight: .medium),
                            foregroundColor: colors.accent,
                            isTranslateAction: viewModel.selectedAction?.supportsAppleTranslate ?? false,
                            resolvedTarget: viewModel.resolvedTargetLanguage,
                            onOverrideTarget: { viewModel.overrideTargetLanguage($0) }
                        )

                        #if os(macOS)
                            Button {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.image]
                                panel.allowsMultipleSelection = true
                                panel.canChooseDirectories = false
                                if panel.runModal() == .OK {
                                    for url in panel.urls {
                                        if let nsImage = NSImage(contentsOf: url),
                                           let attachment = ImageAttachment.from(nsImage: nsImage)
                                        {
                                            viewModel.addImage(attachment)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(colors.accent)
                        #elseif os(iOS)
                            PhotosPicker(
                                selection: $selectedPhotoItems,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(colors.accent)
                            .onChange(of: selectedPhotoItems) {
                                let items = selectedPhotoItems
                                guard !items.isEmpty else { return }
                                Task {
                                    for item in items {
                                        if let data = try? await item.loadTransferable(type: Data.self),
                                           let uiImage = UIImage(data: data),
                                           let attachment = ImageAttachment.from(uiImage: uiImage)
                                        {
                                            viewModel.addImage(attachment)
                                        }
                                    }
                                    selectedPhotoItems = []
                                }
                            }
                        #endif
                    }

                    Spacer()

                    if !isCollapsed {
                        inputSpeakButton

                        Button {
                            hideKeyboard()
                            viewModel.performSelectedAction()
                        } label: {
                            HStack(spacing: 6) {
                                Text("Send")
                                    .font(.system(size: 15, weight: .semibold))
                                #if os(macOS)
                                    Text("Cmd+Return")
                                        .font(.system(size: 12, weight: .medium))
                                        .opacity(0.9)
                                #endif
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(colors.accent)
                        .disabled(!viewModel.canSend)
                        .opacity(viewModel.canSend ? 1.0 : 0.5)
                        #if os(macOS)
                            .keyboardShortcut(.return, modifiers: [.command])
                        #endif
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, isCollapsed ? 0 : 12)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: isInputExpanded)
        .animation(.easeInOut(duration: 0.25), value: viewModel.resolvedTargetLanguage)
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
            if viewModel.isSpeakingInputText {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14))
            } else {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 14))
            }
        }
        .buttonStyle(.glass)
        .tint(viewModel.isSpeakingInputText ? .red : colors.accent)
        .buttonBorderShape(.circle)
        .disabled(!hasText && !viewModel.isSpeakingInputText)
        .opacity(hasText || viewModel.isSpeakingInputText ? 1.0 : 0.5)
    }

    private var collapsedInputSummary: some View {
        let displayText = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isInputExpanded = true
            }
        } label: {
            HStack(spacing: 12) {
                Text(displayText.isEmpty ? viewModel.inputPlaceholder : displayText)
                    .font(.system(size: 15))
                    .foregroundColor(displayText.isEmpty ? colors.textSecondary : colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedInputEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                #if !os(macOS)
                    if viewModel.inputText.isEmpty {
                        Text(viewModel.inputPlaceholder)
                            .foregroundColor(colors.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                    }
                #endif

                #if os(macOS)
                    AutoPasteTextEditor(
                        text: $viewModel.inputText,
                        placeholder: viewModel.inputPlaceholder,
                        onPaste: { pastedText in
                            applyPastedTextIfNeeded(pastedText)
                        },
                        onImagePaste: { nsImages in
                            Logger.debug("onImagePaste callback: received \(nsImages.count) NSImage(s)", tag: "ImagePaste")
                            for nsImage in nsImages {
                                if let attachment = ImageAttachment.from(nsImage: nsImage) {
                                    Logger.debug(
                                        "onImagePaste: attachment created, size: \(String(format: "%.2f", attachment.sizeMB))MB",
                                        tag: "ImagePaste"
                                    )
                                    viewModel.addImage(attachment)
                                } else {
                                    Logger.debug(
                                        "onImagePaste: ImageAttachment.from(nsImage:) returned nil for image size \(nsImage.size)",
                                        tag: "ImagePaste"
                                    )
                                }
                            }
                        }
                    )
                    .frame(minHeight: 140, maxHeight: 160)
                    .padding(12)
                #elseif os(iOS)
                    AutoPasteTextEditor(
                        text: $viewModel.inputText,
                        placeholder: viewModel.inputPlaceholder,
                        onPaste: { pastedText in
                            applyPastedTextIfNeeded(pastedText)
                        },
                        onImagePaste: { uiImages in
                            for uiImage in uiImages {
                                if let attachment = ImageAttachment.from(uiImage: uiImage) {
                                    viewModel.addImage(attachment)
                                }
                            }
                        }
                    )
                    .frame(minHeight: 140, maxHeight: 160)
                    .padding(12)
                #else
                    TextEditor(text: $viewModel.inputText)
                        .scrollContentBackground(.hidden)
                        .foregroundColor(colors.textPrimary)
                        .padding(12)
                        .frame(minHeight: 140, maxHeight: 160)
                        .onPasteCommand(of: [.plainText]) { providers in
                            handlePasteCommand(providers: providers)
                        }
                #endif
            }

            // Image attachment preview
            if !viewModel.attachedImages.isEmpty {
                ImageAttachmentPreview(
                    images: viewModel.attachedImages,
                    onRemove: { id in
                        viewModel.removeImage(id: id)
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
    }

    private var actionChips: some View {
        ActionChipsView(
            actions: viewModel.actions,
            selectedActionID: viewModel.selectedAction?.id,
            spacing: 12,
            contentVerticalPadding: 4,
            font: .system(size: 14, weight: .medium),
            textColor: { isSelected in
                isSelected ? Color.white : Color.primary
            },
            background: { isSelected in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(colors.chipPrimaryBackground)
                            : AnyShapeStyle(.regularMaterial)
                    )
            },
            horizontalPadding: 18,
            verticalPadding: 10
        ) { action in
            if viewModel.selectAction(action) {
                viewModel.performSelectedAction()
            }
        }
    }

    private var hintLabel: some View {
        Text(viewModel.placeholderHint)
            .font(.system(size: 14))
            .foregroundColor(colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }

    @ViewBuilder
    private var providerResultCardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(colors.cardBackground)
    }

    private var providerResultsSection: some View {
        VStack(spacing: 16) {
            ForEach(viewModel.modelRuns) { run in
                providerResultCard(for: run)
            }
        }
    }

    private func providerResultCard(for run: HomeViewModel.ModelRunViewState) -> some View {
        let runID = run.id
        return VStack(alignment: .leading, spacing: 12) {
            content(for: run)

            // Bottom info bar
            bottomInfoBar(for: run)
        }
        .padding(16)
        .background(providerResultCardBackground)
        .overlay(alignment: .topTrailing) {
            if showingProviderInfo == runID {
                providerInfoPopover(for: run)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showingProviderInfo)
    }

    @ViewBuilder
    private func bottomInfoBar(
        for run: HomeViewModel.ModelRunViewState
    ) -> some View {
        let runID = run.id
        let showModelName = true

        switch run.status {
        case .idle, .running:
            EmptyView()

        case let .streaming(_, start):
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(colors.accent)
                if showModelName {
                    Text(run.modelDisplayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }
                Text("Generating...")
                    .font(.system(size: 13))
                    .foregroundColor(colors.textSecondary)
                Spacer()
                liveTimer(start: start)
            }

        case let .streamingSentencePairs(_, start):
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(colors.accent)
                if showModelName {
                    Text(run.modelDisplayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }
                Text("Translating...")
                    .font(.system(size: 13))
                    .foregroundColor(colors.textSecondary)
                Spacer()
                liveTimer(start: start)
            }

        case let .success(result):
            HStack(spacing: 12) {
                // Status + Duration + Model Name + Info
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(colors.success)
                        .font(.system(size: 14))

                    if let duration = run.durationText {
                        Text(duration)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                    }

                    if showModelName {
                        Text(run.modelDisplayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                    }

                    providerInfoButton(runID: runID)
                }

                Spacer()

                // Action buttons (only show here when no supplementalTexts, i.e., plain text mode)
                if result.sentencePairs.isEmpty && result.supplementalTexts.isEmpty {
                    actionButtons(copyText: result.copyText, runID: runID)
                }
            }

        case .failure:
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(colors.error)
                        .font(.system(size: 14))

                    if let duration = run.durationText {
                        Text(duration)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                    }

                    if showModelName {
                        Text(run.modelDisplayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                    }

                    providerInfoButton(runID: runID)
                }

                Spacer()

                // Retry button (retry only this run)
                Button {
                    viewModel.retryRun(runID: runID)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func actionButtons(copyText: String, runID: String) -> some View {
        // Full action buttons for bottom bar (plain text mode)
        diffToggleButton(for: runID)
        compactCopyButton(for: copyText)
        chatButton(for: runID)
        #if os(iOS)
            if let context, context.allowsReplacement {
                Button {
                    context.finish(translation: AttributedString(copyText))
                } label: {
                    Label("Replace", systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(colors.accent)
            }
        #endif
    }

    @ViewBuilder
    private func diffToggleButton(for runID: String) -> some View {
        if viewModel.hasDiff(for: runID) {
            let isShowingDiff = viewModel.isDiffShown(for: runID)
            Button {
                viewModel.toggleDiffDisplay(for: runID)
            } label: {
                Image(systemName: isShowingDiff ? "eye.slash" : "eye")
                    .font(.system(size: 14))
                    .foregroundColor(colors.accent)
            }
            .buttonStyle(.plain)
            .help(isShowingDiff ? "Hide changes" : "Show changes")
        }
    }

    @ViewBuilder
    private func providerInfoButton(runID: String) -> some View {
        Button {
            #if DEBUG
                // In Debug, the "info" button is used as a quick jump to the recorded request details.
                // (Provider meta is still available via logs; this keeps the UI one-tap.)
                viewModel.presentDebugRequestDetails(for: runID)
            #else
                withAnimation {
                    if showingProviderInfo == runID {
                        showingProviderInfo = nil
                    } else {
                        showingProviderInfo = runID
                    }
                }
            #endif
        } label: {
            #if DEBUG
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)
            #else
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)
            #endif
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func providerInfoPopover(for run: HomeViewModel.ModelRunViewState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(run.modelDisplayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colors.textPrimary)
            if let duration = run.durationText {
                Text(
                    String(
                        format: NSLocalizedString("Duration: %@", comment: "Provider run duration"),
                        duration
                    )
                )
                .font(.system(size: 12))
                .foregroundColor(colors.textSecondary)
            }
            if let breakdown = run.status.latencyBreakdown {
                Divider()
                HStack(spacing: 4) {
                    Text("Client → Azure:")
                        .font(.system(size: 11))
                        .foregroundColor(colors.textSecondary)
                    Text(breakdown.clientToAzureText)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(colors.textPrimary)
                }
                HStack(spacing: 4) {
                    Text("Azure → Model:")
                        .font(.system(size: 11))
                        .foregroundColor(colors.textSecondary)
                    Text(breakdown.upstreamText)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(colors.textPrimary)
                }
            }
        }
        .fixedSize()
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colors.cardBackground)
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
        )
        .padding(.top, 8)
        .padding(.trailing, 8)
        .onTapGesture {
            withAnimation {
                showingProviderInfo = nil
            }
        }
    }

    private func liveTimer(start: Date) -> some View {
        TimelineView(.periodic(from: start, by: 1.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Text(String(format: "%.0fs", elapsed))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundColor(colors.textSecondary)
        }
    }

    private func skeletonPlaceholder() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0 ..< 3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(colors.skeleton)
                    .frame(height: 10)
                    .frame(maxWidth: index == 2 ? 180 : .infinity)
                    .shimmer()
            }
        }
    }

    @ViewBuilder
    private func compactCopyButton(for text: String) -> some View {
        Button {
            copyToPasteboard(text)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 14))
                .foregroundColor(colors.accent)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func chatButton(for runID: String) -> some View {
        if let run = viewModel.modelRuns.first(where: { $0.id == runID }),
           !run.model.isLocal
        {
            Button {
                if let session = viewModel.createConversation(from: run) {
                    activeConversationSession = session
                }
            } label: {
                Image(systemName: "text.bubble")
                    .font(.system(size: 14))
                    .foregroundColor(colors.accent)
            }
            .buttonStyle(.plain)
            .help("Continue conversation")
            .accessibilityIdentifier("chat_button")
        }
    }

    @ViewBuilder
    private func suggestedActionChips(actions: [String], runID: String) -> some View {
        SuggestedActionChips(actions: actions) { action in
            if let run = viewModel.modelRuns.first(where: { $0.id == runID }),
               let session = viewModel.createConversationWithFollowUp(from: run, followUp: action)
            {
                activeConversationSession = session
            }
        }
    }

    @ViewBuilder
    private func content(for run: HomeViewModel.ModelRunViewState) -> some View {
        switch run.status {
        case .idle, .running:
            skeletonPlaceholder()

        case let .streaming(text, _):
            if text.isEmpty {
                skeletonPlaceholder()
            } else {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(colors.textPrimary)
                    .textSelection(.enabled)
            }

        case let .streamingSentencePairs(pairs, _):
            if pairs.isEmpty {
                skeletonPlaceholder()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(pair.original)
                                .font(.system(size: 14))
                                .foregroundColor(colors.textSecondary)
                                .textSelection(.enabled)
                            Text(pair.translation)
                                .font(.system(size: 14))
                                .foregroundColor(colors.textPrimary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 8)

                        if index < pairs.count - 1 {
                            Divider()
                        }
                    }
                }
            }

        case let .success(result):
            let showDiff = run.showDiff
            let runID = run.id
            VStack(alignment: .leading, spacing: 12) {
                if !result.sentencePairs.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(result.sentencePairs.enumerated()), id: \.offset) { index, pair in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(pair.original)
                                    .font(.system(size: 14))
                                    .foregroundColor(colors.textSecondary)
                                    .textSelection(.enabled)
                                Text(pair.translation)
                                    .font(.system(size: 14))
                                    .foregroundColor(colors.textPrimary)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 8)

                            if index < result.sentencePairs.count - 1 {
                                Divider()
                            }
                        }
                    }
                } else if let diff = result.diff, showDiff {
                    VStack(alignment: .leading, spacing: 8) {
                        if diff.hasRemovals {
                            let originalText = TextDiffBuilder.attributedString(
                                for: diff.originalSegments,
                                palette: colors,
                                colorScheme: colorScheme
                            )
                            Text(originalText)
                                .font(.system(size: 14))
                                .textSelection(.enabled)
                        }

                        if diff.hasAdditions || (!diff.hasRemovals && !diff.hasAdditions) {
                            let revisedText = TextDiffBuilder.attributedString(
                                for: diff.revisedSegments,
                                palette: colors,
                                colorScheme: colorScheme
                            )
                            Text(revisedText)
                                .font(.system(size: 14))
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    let mainText = !result.supplementalTexts.isEmpty ? result.copyText : result.text
                    Text(mainText)
                        .font(.system(size: 14))
                        .foregroundColor(colors.textPrimary)
                        .textSelection(.enabled)
                }

                // Suggested action chips
                if !result.suggestedActions.isEmpty {
                    suggestedActionChips(actions: result.suggestedActions, runID: runID)
                }

                // Action buttons above divider (only when supplementalTexts exist)
                if result.sentencePairs.isEmpty && !result.supplementalTexts.isEmpty {
                    HStack(spacing: 12) {
                        Spacer()
                        actionButtons(copyText: result.copyText, runID: runID)
                    }
                }

                if !result.supplementalTexts.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(result.supplementalTexts.enumerated()), id: \.offset) { entry in
                            Text(entry.element)
                                .font(.system(size: 14))
                                .foregroundColor(colors.textPrimary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

        case let .failure(message, _, _):
            VStack(alignment: .leading, spacing: 10) {
                Text("Request Failed")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colors.error)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        PasteboardHelper.copy(text)
    }

    private func handlePasteCommand(providers: [NSItemProvider]) {
        if let clipboardText = readImmediatePasteboardText() {
            Task { @MainActor in
                applyPastedTextIfNeeded(clipboardText)
            }
            return
        }

        guard !providers.isEmpty else { return }

        let plainTextIdentifier = UTType.plainText.identifier

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(plainTextIdentifier) {
                provider.loadItem(forTypeIdentifier: plainTextIdentifier, options: nil) { item, _ in
                    guard let text = Self.coerceLoadedItemToString(item) else { return }
                    Task { @MainActor in
                        applyPastedTextIfNeeded(text)
                    }
                }
                return
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String else { return }
                    Task { @MainActor in
                        applyPastedTextIfNeeded(text)
                    }
                }
                return
            }
        }
    }

    private func readImmediatePasteboardText() -> String? {
        #if canImport(AppKit)
            if let text = NSPasteboard.general.string(forType: .string) {
                return text
            }
        #endif
        #if canImport(UIKit)
            if let text = UIPasteboard.general.string {
                return text
            }
        #endif
        return nil
    }

    @MainActor
    private func applyPastedTextIfNeeded(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        viewModel.inputText = text
        isInputExpanded = true
        viewModel.performSelectedAction()
    }

    private static func coerceLoadedItemToString(_ item: NSSecureCoding?) -> String? {
        switch item {
        case let data as Data:
            return String(data: data, encoding: .utf8)
        case let string as String:
            return string
        case let attributed as NSAttributedString:
            return attributed.string
        default:
            return nil
        }
    }
}

// MARK: - Default App Guide Sheet

public struct DefaultAppGuideSheet: View {
    let colors: AppColorPalette
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    public init(colors: AppColorPalette, onOpenSettings: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.colors = colors
        self.onOpenSettings = onOpenSettings
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "translate")
                    .font(.system(size: 44))
                    .foregroundColor(colors.accent)
                Text("Set as System Translator")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(colors.textPrimary)
            }
            .padding(.top, 32)

            // Steps
            VStack(alignment: .leading, spacing: 20) {
                guideStep(
                    number: 1,
                    icon: "gearshape.fill",
                    title: "Set as Default",
                    description: "Tap \"Open Settings\" below, then select TLingo as your default translation app"
                )

                guideStep(
                    number: 2,
                    icon: "text.cursor",
                    title: "Select Text",
                    description: "In any app, long press to select the text you want to translate"
                )

                guideStep(
                    number: 3,
                    icon: "hand.tap.fill",
                    title: "Tap Translate",
                    description: "In the context menu, swipe left and tap \"Translate\" — TLingo will handle the rest"
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button {
                    onOpenSettings()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gear")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Open Settings")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(colors.accent)
                    )
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Text("Got it")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(colors.background.ignoresSafeArea())
    }

    private func guideStep(number: Int, icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(colors.accent.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(colors.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(verbatim: "\(number).")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(colors.accent)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                }
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Shimmer Animation

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            .white.opacity(0.4),
                            .clear,
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: -geometry.size.width * 0.3 + phase * geometry.size.width * 1.6)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

private extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

#Preview {
    HomeView(context: nil)
        .preferredColorScheme(.dark)
}

#if os(macOS)
    public extension Notification.Name {
        /// Notification posted when text is received from macOS Services (right-click menu)
        static let serviceTextReceived = Notification.Name("serviceTextReceived")
        /// Notification posted by AppleTranslationWindowManager to register a HomeViewModel
        /// with the hidden translation window bridge. userInfo["register"] is (HomeViewModel) -> Void.
        static let appleTranslationViewModelRegister = Notification.Name("appleTranslationViewModelRegister")
    }
#endif

public extension Notification.Name {
    /// Notification posted when text is received via deep link (tlingo://translate?text=...)
    static let deepLinkTextReceived = Notification.Name("deepLinkTextReceived")
}
