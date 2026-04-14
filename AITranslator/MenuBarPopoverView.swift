//
//  MenuBarPopoverView.swift
//  TLingo
//
//  Created by AI Assistant on 2025/12/31.
//

#if os(macOS)
    import AppKit
    import Combine
    import ShareCore
    import SwiftUI

    /// A compact popover view for menu bar quick translation
    struct MenuBarPopoverView: View {
        @Environment(\.colorScheme) private var colorScheme
        @StateObject private var viewModel: HomeViewModel
        @ObservedObject private var hotKeyManager = HotKeyManager.shared
        @ObservedObject private var preferences = AppPreferences.shared
        @State private var showHotkeyHint: Bool = true
        @State private var activeConversationSession: ConversationSession?
        // Focus is managed via AppKit's first responder, not SwiftUI's @FocusState,
        // because @FocusState on NSViewRepresentable competes with AppKit's responder chain.
        let onClose: () -> Void

        private var colors: AppColorPalette {
            AppColors.palette(for: colorScheme)
        }

        /// Whether the quick translate hotkey is configured
        private var isHotkeyConfigured: Bool {
            !hotKeyManager.quickTranslateConfiguration.isEmpty
        }

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
            _viewModel = StateObject(wrappedValue: HomeViewModel())
        }

        var body: some View {
            ZStack {
                if let session = activeConversationSession {
                    inlineConversationView(session: session)
                        .transition(.move(edge: .trailing))
                } else {
                    translateContent
                        .transition(.move(edge: .leading))
                }
            }
            .frame(width: 360, height: 420)
            .animation(.easeInOut(duration: 0.25), value: activeConversationSession != nil)
            .onReceive(NotificationCenter.default.publisher(for: .menuBarPopoverDidShow)) { _ in
                viewModel.refreshConfiguration()
                loadClipboardAndExecute()
            }
            #if DEBUG
            .sheet(item: $viewModel.selectedDebugNetworkRecord) { record in
                    NavigationStack {
                        NetworkRequestDetailView(record: record)
                    }
                    .frame(minWidth: 520, minHeight: 520)
                }
            #endif
        }

        private var configurationLoadingOverlay: some View {
            LoadingOverlay(
                backgroundColor: colors.background.opacity(0.95),
                messageFont: .system(size: 13),
                textColor: colors.textSecondary,
                accentColor: colors.accent
            )
        }

        // MARK: - Translate Content

        private var translateContent: some View {
            ZStack {
                VStack(alignment: .leading, spacing: 12) {
                    headerSection

                    Divider()
                        .background(colors.divider)

                    inputSection
                    actionChips

                    if !viewModel.modelRuns.isEmpty {
                        Divider()
                            .background(colors.divider)
                        resultSection
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(width: 360, height: 420)
                .background(colors.background)

                if viewModel.isLoadingConfiguration {
                    configurationLoadingOverlay
                }
            }
        }

        // MARK: - Inline Conversation View

        private func inlineConversationView(session: ConversationSession) -> some View {
            ConversationContentView(
                session: session,
                onBack: {
                    activeConversationSession = nil
                },
                onDismiss: onClose
            )
            .frame(width: 360, height: 420)
        }

        private func loadClipboardAndExecute() {
            let pb = NSPasteboard.general
            let clipboardContent = pb.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hasRecentClipboard = ClipboardMonitor.shared.hasRecentContent(within: 5)

            if hasRecentClipboard && !clipboardContent.isEmpty {
                viewModel.inputText = clipboardContent
                viewModel.performSelectedAction()
            } else if viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.inputText = clipboardContent
            }
        }

        private func executeTranslation() {
            let trimmedText = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return }
            viewModel.inputText = trimmedText
            viewModel.performSelectedAction()
        }

        private func openMainWindow() {
            onClose()
            AppDelegate.shared?.openMainWindow()
        }

        // MARK: - Header Section

        private var headerSection: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Quick Translate")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colors.textPrimary)

                    Spacer()

                    Menu {
                        Button {
                            openMainWindow()
                        } label: {
                            Label("Open Main Window", systemImage: "macwindow")
                        }

                        Divider()

                        Button(role: .destructive) {
                            NSApp.terminate(nil)
                        } label: {
                            Label("Quit TLingo", systemImage: "power")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundColor(colors.textSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }

                if !isHotkeyConfigured && showHotkeyHint {
                    hotkeyHintView
                }
            }
        }

        private var hotkeyHintView: some View {
            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                    .font(.system(size: 10))
                    .foregroundColor(colors.textSecondary.opacity(0.8))

                Text("Set a shortcut in Settings → Hotkeys")
                    .font(.system(size: 11))
                    .foregroundColor(colors.textSecondary.opacity(0.8))

                Spacer()

                Button {
                    showHotkeyHint = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(colors.textSecondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }

        // MARK: - Input Section

        private var inputSection: some View {
            VStack(spacing: 8) {
                SelectableTextEditor(
                    text: $viewModel.inputText,
                    textColor: colors.textPrimary
                )
                .font(.system(size: 13))
                .frame(height: 60)
                .padding(8)
                .background(inputSectionBackground)

                HStack(spacing: 8) {
                    LanguageSwitcherView(
                        globeFont: .system(size: 10),
                        textFont: .system(size: 11, weight: .medium),
                        chevronFont: .system(size: 7),
                        foregroundColor: colors.textSecondary.opacity(0.7),
                        isTranslateAction: viewModel.selectedAction?.supportsAppleTranslate ?? false,
                        resolvedTarget: viewModel.resolvedTargetLanguage,
                        onOverrideTarget: { viewModel.overrideTargetLanguage($0) }
                    )

                    Spacer()

                    inputSpeakButton

                    Button {
                        executeTranslation()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 12))
                            Text("Translate")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? colors.accent.opacity(0.5) : colors.accent
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
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
                    .font(.system(size: 12))
                    .foregroundColor(viewModel.isSpeakingInputText ? colors.error : colors.accent)
            }
            .buttonStyle(.plain)
            .disabled(!hasText && !viewModel.isSpeakingInputText)
            .help(viewModel.isSpeakingInputText ? "Stop speaking" : "Speak input text")
        }

        // MARK: - Action Chips

        private var actionChips: some View {
            ActionChipsView(
                actions: viewModel.actions,
                selectedActionID: viewModel.selectedAction?.id,
                spacing: 8,
                font: .system(size: 13, weight: .medium),
                textColor: { isSelected in
                    chipTextColor(isSelected: isSelected)
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

        // MARK: - Result Section

        @ViewBuilder
        private var resultSection: some View {
            let showModelName = viewModel.modelRuns.count > 1
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
                }
            }
        }

        // MARK: - Liquid Glass Backgrounds

        private func chipTextColor(isSelected: Bool) -> Color {
            return isSelected ? .white : colors.textPrimary
        }

        @ViewBuilder
        private var inputSectionBackground: some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colors.cardBackground)
        }

        @ViewBuilder
        private func chipBackground(isSelected: Bool) -> some View {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colors.accent)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colors.cardBackground)
            }
        }
    }

    // MARK: - SelectableTextEditor

    /// A custom TextEditor wrapper that ensures selected text is always readable
    /// by setting high-contrast selection colors.
    private struct SelectableTextEditor: NSViewRepresentable {
        @Binding var text: String
        let textColor: Color

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        func makeNSView(context: Context) -> NSScrollView {
            let textView = NSTextView()
            textView.delegate = context.coordinator
            textView.isRichText = false
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 4, height: 4)
            textView.textContainer?.lineFragmentPadding = 0
            textView.font = NSFont.systemFont(ofSize: 13)
            textView.textColor = NSColor(textColor)
            textView.insertionPointColor = NSColor(textColor)
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = true
            textView.string = text

            textView.selectedTextAttributes = [
                .backgroundColor: NSColor.controlAccentColor,
                .foregroundColor: NSColor.white,
            ]

            let scrollView = NSScrollView()
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.contentView.drawsBackground = false
            scrollView.documentView = textView

            // Make the text view first responder via AppKit after the view is installed
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }

            context.coordinator.textView = textView

            return scrollView
        }

        func updateNSView(_ nsView: NSScrollView, context _: Context) {
            guard let textView = nsView.documentView as? NSTextView else { return }
            if textView.string != text {
                textView.string = text
            }
            textView.textColor = NSColor(textColor)
            textView.insertionPointColor = NSColor(textColor)
        }

        final class Coordinator: NSObject, NSTextViewDelegate {
            private let parent: SelectableTextEditor
            weak var textView: NSTextView?

            init(parent: SelectableTextEditor) {
                self.parent = parent
                super.init()
            }

            func textDidChange(_ notification: Notification) {
                guard let textView = notification.object as? NSTextView else { return }
                let updated = textView.string
                if parent.text != updated {
                    parent.text = updated
                }
            }
        }
    }

#endif
