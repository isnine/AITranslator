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
    import UniformTypeIdentifiers

    /// A compact popover view for menu bar quick translation
    struct MenuBarPopoverView: View {
        @Environment(\.colorScheme) private var colorScheme
        @StateObject private var viewModel: HomeViewModel
        @ObservedObject private var hotKeyManager = HotKeyManager.shared
        @ObservedObject private var preferences = AppPreferences.shared
        @State private var inputText: String = ""
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
            _viewModel = StateObject(wrappedValue: HomeViewModel(usageScene: .app))
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
            InlineConversationContent(
                session: session,
                colors: colors,
                onBack: {
                    activeConversationSession = nil
                },
                onClose: onClose
            )
        }

        private func loadClipboardAndExecute() {
            let pb = NSPasteboard.general
            let clipboardContent = pb.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hasRecentClipboard = ClipboardMonitor.shared.hasRecentContent(within: 5)

            // Only auto-load clipboard images when the main app window is NOT visible.
            // When both the popover and main window are shown, the user likely intended
            // clipboard images for the main app — let explicit Cmd+V handle image paste
            // based on which input field has focus.
            let mainWindowVisible = NSApp.windows.contains { window in
                window.isVisible && window.level == .normal
                    && !(window is NSPanel)
            }

            var clipboardImages: [ImageAttachment] = []
            if !mainWindowVisible {
                let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
                if let availableType = pb.availableType(from: imageTypes),
                   let data = pb.data(forType: availableType),
                   let nsImage = NSImage(data: data),
                   let attachment = ImageAttachment.from(nsImage: nsImage)
                {
                    clipboardImages.append(attachment)
                }
            }

            if hasRecentClipboard && (!clipboardContent.isEmpty || !clipboardImages.isEmpty) {
                inputText = clipboardContent
                viewModel.inputText = inputText
                for img in clipboardImages {
                    viewModel.addImage(img)
                }
                viewModel.performSelectedAction()
            } else if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                inputText = clipboardContent
            }
        }

        private func executeTranslation() {
            let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty || !viewModel.attachedImages.isEmpty else { return }
            viewModel.inputText = trimmedText
            viewModel.performSelectedAction()
        }

        // MARK: - Header Section

        private var headerSection: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Quick Translate")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colors.textPrimary)

                    Spacer()

                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(colors.textSecondary)
                    }
                    .buttonStyle(.plain)
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
                VStack(spacing: 0) {
                    SelectableTextEditor(
                        text: $inputText,
                        textColor: colors.textPrimary,
                    onImagePaste: { nsImages in
                        Logger.debug("MenuBar onImagePaste called with \(nsImages.count) images", tag: "ImagePaste")
                        for nsImage in nsImages {
                            Logger.debug("MenuBar processing NSImage: \(nsImage.size)", tag: "ImagePaste")
                            if let attachment = ImageAttachment.from(nsImage: nsImage) {
                                Logger.debug("MenuBar created attachment: \(attachment.sizeMB)MB", tag: "ImagePaste")
                                viewModel.addImage(attachment)
                            } else {
                                Logger.debug("MenuBar failed to create ImageAttachment from NSImage", tag: "ImagePaste")
                            }
                        }
                    }
                    )
                    .font(.system(size: 13))
                    .frame(height: viewModel.attachedImages.isEmpty ? 60 : 36)

                    if !viewModel.attachedImages.isEmpty {
                        ImageAttachmentPreview(
                            images: viewModel.attachedImages,
                            onRemove: { id in
                                viewModel.removeImage(id: id)
                            }
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 2)
                    }
                }
                .padding(8)
                .background(inputSectionBackground)

                HStack(spacing: 8) {
                    LanguageSwitcherView(
                        globeFont: .system(size: 10),
                        textFont: .system(size: 11, weight: .medium),
                        chevronFont: .system(size: 7),
                        foregroundColor: colors.textSecondary.opacity(0.7)
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
                                    inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                                        .isEmpty && viewModel.attachedImages
                                        .isEmpty ? colors.accent.opacity(0.5) : colors.accent
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty && viewModel.attachedImages.isEmpty
                    )
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }

        @ViewBuilder
        private var inputSpeakButton: some View {
            let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button {
                if viewModel.isSpeakingInputText {
                    viewModel.stopSpeaking()
                } else {
                    viewModel.inputText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    viewModel.inputText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        ProviderResultCardView(
                            run: run,
                            showModelName: showModelName,
                            viewModel: viewModel,
                            onCopy: { text in
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(text, forType: .string)
                            },
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

        // MARK: - Liquid Glass Backgrounds

        private func chipTextColor(isSelected: Bool) -> Color {
            return isSelected ? .white : colors.textPrimary
        }

        @ViewBuilder
        private var inputSectionBackground: some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 8))
        }

        @ViewBuilder
        private func chipBackground(isSelected: Bool) -> some View {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colors.accent)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
            }
        }
    }

    // MARK: - SelectableTextEditor

    /// A custom TextEditor wrapper that ensures selected text is always readable
    /// by setting high-contrast selection colors. Supports image paste and drag & drop.
    private struct SelectableTextEditor: NSViewRepresentable {
        @Binding var text: String
        let textColor: Color
        var onImagePaste: (([NSImage]) -> Void)?

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        func makeNSView(context: Context) -> NSScrollView {
            let textView = SelectablePastingTextView()
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
            textView.onImagePaste = onImagePaste

            textView.selectedTextAttributes = [
                .backgroundColor: NSColor.controlAccentColor,
                .foregroundColor: NSColor.white,
            ]

            // Register for drag & drop of image files and image pasteboard types
            textView.registerForDraggedTypes([.fileURL, .tiff, .png, NSPasteboard.PasteboardType("public.jpeg")])

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

            // Store reference for the local event monitor in Coordinator
            context.coordinator.textView = textView

            return scrollView
        }

        func updateNSView(_ nsView: NSScrollView, context _: Context) {
            guard let textView = nsView.documentView as? SelectablePastingTextView else { return }
            if textView.string != text {
                textView.string = text
            }
            textView.textColor = NSColor(textColor)
            textView.insertionPointColor = NSColor(textColor)
            textView.onImagePaste = onImagePaste
        }

        final class Coordinator: NSObject, NSTextViewDelegate {
            private let parent: SelectableTextEditor
            private var eventMonitor: Any?
            weak var textView: SelectablePastingTextView?

            init(parent: SelectableTextEditor) {
                self.parent = parent
                super.init()
                // Install local event monitor to intercept Cmd+V before SwiftUI's
                // NSHostingView routes it to the auto-generated Edit > Paste menu item.
                eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let textView = self.textView else { return event }
                    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                       event.charactersIgnoringModifiers == "v",
                       textView.window?.isKeyWindow == true,
                       textView.window?.firstResponder === textView
                    {
                        textView.paste(nil)
                        return nil // consume event
                    }
                    return event
                }
            }

            deinit {
                if let monitor = eventMonitor {
                    NSEvent.removeMonitor(monitor)
                }
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

    /// Custom NSTextView subclass for SelectableTextEditor that supports image paste and drag & drop.
    private final class SelectablePastingTextView: NSTextView {
        var onImagePaste: (([NSImage]) -> Void)?

        override func paste(_ sender: Any?) {
            // Only handle image paste when this text view has focus.
            // When both the popover and main window are visible, this prevents
            // images from appearing in the wrong input field.
            guard window?.firstResponder === self else {
                super.paste(sender)
                return
            }

            let pb = NSPasteboard.general
            let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png, NSPasteboard.PasteboardType("public.jpeg")]

            // Check for raw image data first
            if let availableType = pb.availableType(from: imageTypes),
               let data = pb.data(forType: availableType),
               let image = NSImage(data: data)
            {
                Logger.debug("MenuBar Paste: image from raw data, size: \(image.size)", tag: "ImagePaste")
                onImagePaste?([image])
                return
            }

            // Check for image file URLs
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingContentsConformToTypes: [UTType.image.identifier],
            ]) as? [URL], !urls.isEmpty {
                let images = urls.compactMap { NSImage(contentsOf: $0) }
                if !images.isEmpty {
                    Logger.debug("MenuBar Paste: \(images.count) image(s) from file URLs", tag: "ImagePaste")
                    onImagePaste?(images)
                    return
                }
            }

            // Fall through to text paste
            super.paste(sender)
        }

        // MARK: - Drag & Drop

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            let pb = sender.draggingPasteboard
            if pb.canReadObject(forClasses: [NSURL.self], options: [
                .urlReadingContentsConformToTypes: [UTType.image.identifier],
            ]) {
                return .copy
            }
            if pb.availableType(from: [.tiff, .png, NSPasteboard.PasteboardType("public.jpeg")]) != nil {
                return .copy
            }
            return super.draggingEntered(sender)
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            let pb = sender.draggingPasteboard

            // Check for image file URLs
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingContentsConformToTypes: [UTType.image.identifier],
            ]) as? [URL], !urls.isEmpty {
                let images = urls.compactMap { NSImage(contentsOf: $0) }
                if !images.isEmpty {
                    onImagePaste?(images)
                    return true
                }
            }

            // Check for raw image data
            let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png, NSPasteboard.PasteboardType("public.jpeg")]
            if let availableType = pb.availableType(from: imageTypes),
               let data = pb.data(forType: availableType),
               let image = NSImage(data: data)
            {
                onImagePaste?([image])
                return true
            }

            return super.performDragOperation(sender)
        }
    }

    // MARK: - Inline Conversation Content

    /// A compact conversation view designed to be embedded inline within the menu bar popover.
    /// Replaces the translate content when a conversation session is active.
    private struct InlineConversationContent: View {
        @Environment(\.colorScheme) private var colorScheme
        @StateObject private var viewModel: ConversationViewModel
        let onBack: () -> Void
        let onClose: () -> Void

        private var colors: AppColorPalette {
            AppColors.palette(for: colorScheme)
        }

        init(
            session: ConversationSession,
            colors _: AppColorPalette,
            onBack: @escaping () -> Void,
            onClose: @escaping () -> Void
        ) {
            _viewModel = StateObject(wrappedValue: ConversationViewModel(session: session))
            self.onBack = onBack
            self.onClose = onClose
        }

        var body: some View {
            VStack(spacing: 0) {
                // Header with back button
                conversationHeader

                Divider()
                    .foregroundColor(colors.divider)

                // Message list
                messageList

                // Error banner
                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }

                Divider()
                    .foregroundColor(colors.divider)

                // Input bar
                ConversationInputBar(
                    text: $viewModel.inputText,
                    selectedModel: $viewModel.model,
                    isStreaming: viewModel.isStreaming,
                    canSend: viewModel.canSend,
                    availableModels: viewModel.availableModels,
                    images: viewModel.attachedImages,
                    onRemoveImage: { id in viewModel.removeImage(id: id) },
                    onAddImages: { nsImages in
                        for img in nsImages {
                            if let attachment = ImageAttachment.from(nsImage: img) {
                                viewModel.addImage(attachment)
                            }
                        }
                    },
                    onSend: { viewModel.send() },
                    onStop: { viewModel.stopStreaming() }
                )
            }
            .frame(width: 360, height: 420)
            .background(colors.background)
            .onKeyPress(.tab) {
                viewModel.cycleModel()
                return .handled
            }
        }

        private var conversationHeader: some View {
            HStack(spacing: 8) {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.accent)
                }
                .buttonStyle(.plain)

                Text(viewModel.action.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }

        private var messageList: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        if viewModel.isStreaming {
                            StreamingBubbleView(text: viewModel.streamingText)
                                .id("streaming")
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.streamingText) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }
        }

        private func scrollToBottom(proxy: ScrollViewProxy) {
            withAnimation(.easeOut(duration: 0.2)) {
                if viewModel.isStreaming {
                    proxy.scrollTo("streaming", anchor: .bottom)
                } else if let lastMessage = viewModel.messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }

        private func errorBanner(_ message: String) -> some View {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(colors.error)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(colors.error)
                    .lineLimit(2)
                Spacer()
                Button {
                    viewModel.errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(colors.error.opacity(0.1))
        }
    }
#endif
