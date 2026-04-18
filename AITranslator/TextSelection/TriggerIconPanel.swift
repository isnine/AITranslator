//
//  TriggerIconPanel.swift
//  TLingo
//
//  Tiny floating panel that hosts the trigger icon near the cursor.
//

#if os(macOS)
    import AppKit

    final class TriggerIconPanel: NSPanel {
        static let height: CGFloat = 32
        static let singleWidth: CGFloat = 32
        static let dualWidth: CGFloat = 68

        init(width: CGFloat) {
            let rect = NSRect(x: 0, y: 0, width: width, height: Self.height)
            super.init(
                contentRect: rect,
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: true
            )

            isReleasedWhenClosed = false
            level = .floating
            isOpaque = false
            backgroundColor = .clear
            hidesOnDeactivate = false
            isMovableByWindowBackground = false
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }

        override var canBecomeKey: Bool { false }
    }
#endif
