//
//  ClipboardGrabber.swift
//  TLingo
//
//  Text selection via clipboard simulation (Tier 3).
//

#if os(macOS)
    import AppKit
    import os

    private let logger = os.Logger(subsystem: "com.zanderwang.AITranslator", category: "ClipboardGrabber")

    enum ClipboardGrabber {
        private static let isGrabbing = OSAllocatedUnfairLock(initialState: false)

        /// Tag applied to synthetic CGEvents to distinguish from real user keypresses.
        private static let syntheticEventTag: Int64 = 0x544C696E // "TLin"

        /// Grab selected text by simulating Cmd+C and reading the clipboard.
        /// Saves and restores previous clipboard content unless externally modified.
        @MainActor static func grabViaClipboard() async -> String? {
            guard isGrabbing.withLock({ val in
                if val { return false }
                val = true
                return true
            }) else { return nil }
            defer { isGrabbing.withLock { $0 = false } }

            let pasteboard = NSPasteboard.general
            let previousCount = pasteboard.changeCount

            // Save current clipboard contents with full type fidelity
            let savedItems: [[(NSPasteboard.PasteboardType, Data)]]? = pasteboard.pasteboardItems?.compactMap { item in
                let pairs = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                    guard let data = item.data(forType: type) else { return nil }
                    return (type, data)
                }
                return pairs.isEmpty ? nil : pairs
            }

            // Detect real user Cmd+C during grab window
            let userCopied = OSAllocatedUnfairLock(initialState: false)
            let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command),
                   event.keyCode == 0x08, // 'c'
                   event.cgEvent?.getIntegerValueField(.eventSourceUserData) != syntheticEventTag
                {
                    userCopied.withLock { $0 = true }
                }
            }
            defer { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }

            simulateCopy()

            // Wait for clipboard to update (max 300ms)
            let deadline = Date().addingTimeInterval(0.3)
            while pasteboard.changeCount == previousCount, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }

            guard pasteboard.changeCount != previousCount else {
                return nil
            }

            let postCopyCount = pasteboard.changeCount

            // Filter file URL selections
            let isFileSelection = pasteboard.canReadObject(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            )

            let text = isFileSelection ? nil : pasteboard.string(forType: .string)

            // Grace period for external Cmd+C
            try? await Task.sleep(for: .milliseconds(30))

            let externalModification = pasteboard.changeCount != postCopyCount || userCopied.withLock { $0 }

            // Restore previous clipboard only if no external modification
            if !externalModification {
                pasteboard.clearContents()
                if let savedItems {
                    let items = savedItems.map { itemTypes -> NSPasteboardItem in
                        let item = NSPasteboardItem()
                        for (type, data) in itemTypes {
                            item.setData(data, forType: type)
                        }
                        return item
                    }
                    pasteboard.writeObjects(items)
                }
            }

            guard let text, !text.isEmpty else {
                return nil
            }
            return text
        }

        private static func simulateCopy() {
            let source = CGEventSource(stateID: .combinedSessionState)

            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
            keyDown?.flags = .maskCommand
            keyDown?.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
            keyDown?.post(tap: .cgSessionEventTap)

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
            keyUp?.flags = .maskCommand
            keyUp?.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
            keyUp?.post(tap: .cgSessionEventTap)
        }
    }
#endif
