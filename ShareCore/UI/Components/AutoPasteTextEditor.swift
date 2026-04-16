import os
import SwiftUI
import UniformTypeIdentifiers

private let logger = os.Logger(subsystem: "com.zanderwang.AITranslator", category: "ImagePaste")
#if canImport(AppKit)
    import AppKit
#endif
#if canImport(UIKit)
    import UIKit
#endif

#if os(macOS)
    struct AutoPasteTextEditor: NSViewRepresentable {
        @Binding var text: String
        let placeholder: String
        let onPaste: (String) -> Void
        var onImagePaste: (([NSImage]) -> Void)?

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        func makeNSView(context: Context) -> NSScrollView {
            let textView = PastingTextView()
            textView.delegate = context.coordinator
            textView.isRichText = false
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 16, height: 12)
            textView.textContainer?.lineFragmentPadding = 0
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = true
            textView.string = text
            textView.onPaste = onPaste
            textView.onImagePaste = onImagePaste
            textView.placeholderAttributedString = makePlaceholderAttributedString()

            // Register for drag & drop of image files and image pasteboard types
            textView.registerForDraggedTypes([.fileURL, .tiff, .png, NSPasteboard.PasteboardType("public.jpeg")])

            // Store reference for the local event monitor in Coordinator
            context.coordinator.textView = textView

            let scrollView = NSScrollView()
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = true
            scrollView.contentView.drawsBackground = false
            scrollView.documentView = textView
            return scrollView
        }

        func updateNSView(_ nsView: NSScrollView, context _: Context) {
            guard let textView = nsView.documentView as? PastingTextView else {
                return
            }

            if textView.string != text {
                textView.string = text
            }

            textView.onPaste = onPaste
            textView.onImagePaste = onImagePaste
            if textView.placeholderAttributedString?.string != placeholder {
                textView.placeholderAttributedString = makePlaceholderAttributedString()
            }
        }

        final class Coordinator: NSObject, NSTextViewDelegate {
            private let parent: AutoPasteTextEditor
            private var eventMonitor: Any?
            weak var textView: PastingTextView?

            init(parent: AutoPasteTextEditor) {
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

        private func makePlaceholderAttributedString() -> NSAttributedString {
            NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
        }
    }

    final class PastingTextView: NSTextView {
        var onPaste: ((String) -> Void)?
        var onImagePaste: (([NSImage]) -> Void)?
        var placeholderAttributedString: NSAttributedString? {
            didSet { needsDisplay = true }
        }

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
                logger.debug("Paste: image from raw data (\(availableType.rawValue, privacy: .public)), size: \(image.size.debugDescription, privacy: .public)")
                onImagePaste?([image])
                return
            }

            // Check for image file URLs
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingContentsConformToTypes: [UTType.image.identifier],
            ]) as? [URL], !urls.isEmpty {
                let images = urls.compactMap { NSImage(contentsOf: $0) }
                if !images.isEmpty {
                    logger.debug("Paste: \(images.count, privacy: .public) image(s) from file URLs")
                    onImagePaste?(images)
                    return
                }
            }

            // Fall through to text paste
            super.paste(sender)
            let current = string
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onPaste?(current)
            needsDisplay = true
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

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard string.isEmpty,
                  window?.firstResponder !== self,
                  let placeholder = placeholderAttributedString
            else {
                return
            }

            let inset = textContainerInset
            let padding = textContainer?.lineFragmentPadding ?? 0
            // Draw placeholder at top-left (text cursor position), not vertically centered
            let origin = CGPoint(
                x: inset.width + padding,
                y: inset.height
            )
            placeholder.draw(at: origin)
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

#elseif os(iOS)
    struct AutoPasteTextEditor: UIViewRepresentable {
        @Binding var text: String
        let placeholder: String
        let onPaste: (String) -> Void
        var onImagePaste: (([UIImage]) -> Void)?

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        func makeUIView(context: Context) -> PastingTextView {
            let textView = PastingTextView()
            textView.delegate = context.coordinator
            textView.backgroundColor = .clear
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
            textView.text = text
            textView.onPaste = onPaste
            textView.onImagePaste = onImagePaste
            textView.isScrollEnabled = true
            textView.alwaysBounceVertical = true
            textView.adjustsFontForContentSizeCategory = true
            textView.font = UIFont.preferredFont(forTextStyle: .body)
            textView.autocorrectionType = .default
            textView.smartDashesType = .no
            textView.smartQuotesType = .no
            textView.accessibilityHint = placeholder
            return textView
        }

        func updateUIView(_ uiView: PastingTextView, context _: Context) {
            if uiView.text != text {
                uiView.text = text
            }
            uiView.onPaste = onPaste
            uiView.onImagePaste = onImagePaste
        }

        final class Coordinator: NSObject, UITextViewDelegate {
            private let parent: AutoPasteTextEditor

            init(parent: AutoPasteTextEditor) {
                self.parent = parent
            }

            func textViewDidChange(_ textView: UITextView) {
                let updated = textView.text ?? ""
                if parent.text != updated {
                    parent.text = updated
                }
            }
        }
    }

    final class PastingTextView: UITextView {
        var onPaste: ((String) -> Void)?
        var onImagePaste: (([UIImage]) -> Void)?

        override func paste(_ sender: Any?) {
            // Check for images on the pasteboard first
            let pb = UIPasteboard.general
            if pb.hasImages, let images = pb.images, !images.isEmpty {
                onImagePaste?(images)
                return
            }

            // Fall through to text paste
            super.paste(sender)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let current = self.text ?? ""
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self.onPaste?(current)
            }
        }
    }
#endif
