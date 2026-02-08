import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Bottom input bar for the conversation view.
/// Contains a text field, model selector row, and a send/stop button
/// all within a single rounded-rect stroke container.
public struct ConversationInputBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    @Binding var selectedModel: ModelConfig
    let isStreaming: Bool
    let canSend: Bool
    let availableModels: [ModelConfig]
    let images: [ImageAttachment]
    let onRemoveImage: ((UUID) -> Void)?
    let onAddImages: (([PlatformImage]) -> Void)?
    let onSend: () -> Void
    let onStop: () -> Void

    #if os(iOS)
        @State private var selectedPhotoItems: [PhotosPickerItem] = []
    #endif

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    public init(
        text: Binding<String>,
        selectedModel: Binding<ModelConfig>,
        isStreaming: Bool,
        canSend: Bool,
        availableModels: [ModelConfig] = [],
        images: [ImageAttachment] = [],
        onRemoveImage: ((UUID) -> Void)? = nil,
        onAddImages: (([PlatformImage]) -> Void)? = nil,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        _text = text
        _selectedModel = selectedModel
        self.isStreaming = isStreaming
        self.canSend = canSend
        self.availableModels = availableModels
        self.images = images
        self.onRemoveImage = onRemoveImage
        self.onAddImages = onAddImages
        self.onSend = onSend
        self.onStop = onStop
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Image attachment preview
            if !images.isEmpty {
                ImageAttachmentPreview(
                    images: images,
                    onRemove: { id in
                        onRemoveImage?(id)
                    }
                )
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }

            // Text input area
            #if os(macOS)
                ConversationPasteTextEditor(
                    text: $text,
                    placeholder: "Ask for follow-up changes",
                    onImagePaste: { nsImages in
                        onAddImages?(nsImages)
                    },
                    onSubmit: {
                        if canSend {
                            onSend()
                        }
                    }
                )
                .frame(minHeight: 20, maxHeight: 100)
                .padding(.horizontal, 10)
                .padding(.top, images.isEmpty ? 8 : 4)
                .padding(.bottom, availableModels.isEmpty && !isStreaming ? 8 : 4)
            #else
                TextField("Ask for follow-up changes", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1 ... 5)
                    .padding(.horizontal, 14)
                    .padding(.top, images.isEmpty ? 10 : 6)
                    .padding(.bottom, availableModels.isEmpty && !isStreaming ? 10 : 6)
                    .onSubmit {
                        if canSend {
                            onSend()
                        }
                    }
            #endif

            // Bottom toolbar row
            HStack(spacing: 0) {
                if !availableModels.isEmpty {
                    modelPicker
                }

                imageAddButton

                Spacer()

                actionButton
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(colors.textSecondary.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Image Add Button

    private var imageAddButton: some View {
        Group {
            if onAddImages != nil {
                #if os(iOS)
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 14))
                            .foregroundColor(colors.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .onChange(of: selectedPhotoItems) {
                        let items = selectedPhotoItems
                        guard !items.isEmpty else { return }
                        Task {
                            for item in items {
                                if let data = try? await item.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data)
                                {
                                    onAddImages?([uiImage])
                                }
                            }
                            selectedPhotoItems = []
                        }
                    }
                #else
                    Button {
                        pasteImageFromClipboard()
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 14))
                            .foregroundColor(colors.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .help("Paste image from clipboard")
                #endif
            }
        }
    }

    #if os(macOS)
        private func pasteImageFromClipboard() {
            let pb = NSPasteboard.general
            let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png, NSPasteboard.PasteboardType("public.jpeg")]
            if let availableType = pb.availableType(from: imageTypes),
               let data = pb.data(forType: availableType),
               let image = NSImage(data: data)
            {
                onAddImages?([image])
                return
            }
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingContentsConformToTypes: [UTType.image.identifier],
            ]) as? [URL], !urls.isEmpty {
                let images = urls.compactMap { NSImage(contentsOf: $0) }
                if !images.isEmpty {
                    onAddImages?(images)
                }
            }
        }
    #endif

    // MARK: - Model Picker

    private var modelPicker: some View {
        Menu {
            ForEach(availableModels) { model in
                Button {
                    selectedModel = model
                } label: {
                    HStack {
                        Text(model.displayName)
                        if model.id == selectedModel.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedModel.displayName)
                    .font(.system(size: 12))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Send / Stop Button

    private var actionButton: some View {
        Group {
            if isStreaming {
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(colors.error)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(canSend ? colors.accent : colors.textSecondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
    }
}

// MARK: - macOS Paste-Aware Text Editor for Conversation Input

#if os(macOS)
    /// A lightweight NSViewRepresentable text editor that supports image paste and drag & drop
    /// for use inside ConversationInputBar.
    private struct ConversationPasteTextEditor: NSViewRepresentable {
        @Binding var text: String
        let placeholder: String
        var onImagePaste: (([NSImage]) -> Void)?
        var onSubmit: (() -> Void)?

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        func makeNSView(context: Context) -> NSScrollView {
            let textView = ConversationPasteTextView()
            textView.delegate = context.coordinator
            textView.isRichText = false
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 4, height: 2)
            textView.textContainer?.lineFragmentPadding = 0
            textView.font = NSFont.systemFont(ofSize: 13)
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = true
            textView.string = text
            textView.onImagePaste = onImagePaste
            textView.onSubmit = onSubmit
            textView.placeholderString = placeholder

            textView.registerForDraggedTypes([.fileURL, .tiff, .png, NSPasteboard.PasteboardType("public.jpeg")])

            context.coordinator.textView = textView

            let scrollView = NSScrollView()
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = false
            scrollView.contentView.drawsBackground = false
            scrollView.documentView = textView
            return scrollView
        }

        func updateNSView(_ nsView: NSScrollView, context _: Context) {
            guard let textView = nsView.documentView as? ConversationPasteTextView else { return }
            if textView.string != text {
                textView.string = text
            }
            textView.onImagePaste = onImagePaste
            textView.onSubmit = onSubmit
        }

        final class Coordinator: NSObject, NSTextViewDelegate {
            private let parent: ConversationPasteTextEditor
            private var eventMonitor: Any?
            weak var textView: ConversationPasteTextView?

            init(parent: ConversationPasteTextEditor) {
                self.parent = parent
                super.init()
                eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let textView = self.textView else { return event }
                    guard textView.window?.isKeyWindow == true,
                          textView.window?.firstResponder === textView else { return event }

                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                    // Intercept Cmd+Return to send chat message,
                    // consuming the event so it doesn't reach the translation
                    // Send button's .keyboardShortcut(.return, modifiers: .command)
                    if event.keyCode == 36, flags == .command {
                        textView.onSubmit?()
                        return nil
                    }

                    // Intercept Cmd+V for image paste
                    if flags == .command,
                       event.charactersIgnoringModifiers == "v"
                    {
                        textView.paste(nil)
                        return nil
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

    private final class ConversationPasteTextView: NSTextView {
        var onImagePaste: (([NSImage]) -> Void)?
        var onSubmit: (() -> Void)?
        var placeholderString: String? {
            didSet { needsDisplay = true }
        }

        override func paste(_ sender: Any?) {
            // Only handle image paste when this text view has focus.
            // Prevents images from appearing in the wrong input field
            // when multiple text views coexist.
            guard window?.firstResponder === self else {
                super.paste(sender)
                return
            }

            let pb = NSPasteboard.general
            let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png, NSPasteboard.PasteboardType("public.jpeg")]

            if let availableType = pb.availableType(from: imageTypes),
               let data = pb.data(forType: availableType),
               let image = NSImage(data: data)
            {
                onImagePaste?([image])
                return
            }

            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingContentsConformToTypes: [UTType.image.identifier],
            ]) as? [URL], !urls.isEmpty {
                let images = urls.compactMap { NSImage(contentsOf: $0) }
                if !images.isEmpty {
                    onImagePaste?(images)
                    return
                }
            }

            super.paste(sender)
        }

        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Return/Enter without modifiers triggers submit
            if event.keyCode == 36, flags.isEmpty {
                onSubmit?()
                return
            }
            // ⌘+Return also triggers submit (send chat message),
            // preventing the event from reaching the translation Send button's .keyboardShortcut
            if event.keyCode == 36, flags == .command {
                onSubmit?()
                return
            }
            super.keyDown(with: event)
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

            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingContentsConformToTypes: [UTType.image.identifier],
            ]) as? [URL], !urls.isEmpty {
                let images = urls.compactMap { NSImage(contentsOf: $0) }
                if !images.isEmpty {
                    onImagePaste?(images)
                    return true
                }
            }

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

        // MARK: - Placeholder

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard string.isEmpty,
                  window?.firstResponder !== self,
                  let placeholder = placeholderString
            else {
                return
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: font ?? NSFont.systemFont(ofSize: 13),
            ]
            let inset = textContainerInset
            let padding = textContainer?.lineFragmentPadding ?? 0
            let origin = CGPoint(x: inset.width + padding, y: inset.height)
            NSAttributedString(string: placeholder, attributes: attrs).draw(at: origin)
        }

        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            if result { needsDisplay = true }
            return result
        }

        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()
            if result { needsDisplay = true }
            return result
        }

        override func didChangeText() {
            super.didChangeText()
            needsDisplay = true
        }
    }
#endif
