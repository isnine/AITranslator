//
//  TranslationPopupPanel.swift
//  TLingo
//
//  Floating non-activating panel for text selection translation results.
//

#if os(macOS)
    import AppKit

    final class TranslationPopupPanel: NSPanel {
        init(contentRect: NSRect) {
            super.init(
                contentRect: contentRect,
                styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless, .resizable],
                backing: .buffered,
                defer: true
            )

            level = .floating
            isOpaque = false
            backgroundColor = .clear
            hidesOnDeactivate = false
            isMovableByWindowBackground = false
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            isReleasedWhenClosed = false
            minSize = CGSize(width: 320, height: 200)
            maxSize = CGSize(width: 600, height: 600)

            contentView?.wantsLayer = true
            contentView?.layer?.cornerRadius = 12
            contentView?.layer?.masksToBounds = true
        }

        override var canBecomeKey: Bool { true }

        override func sendEvent(_ event: NSEvent) {
            if event.type == .leftMouseDown {
                if !isKeyWindow { makeKey() }
            }
            super.sendEvent(event)
        }
    }
#endif
