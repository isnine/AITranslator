//
//  PopupDismissMonitor.swift
//  TLingo
//
//  Monitors click-outside and Escape key to dismiss the translation popup.
//

#if os(macOS)
    import AppKit

    @MainActor
    final class PopupDismissMonitor {
        private let panel: NSPanel
        private let onDismiss: () -> Void
        private var globalClickMonitor: Any?
        private var globalKeyMonitor: Any?
        private var localClickMonitor: Any?
        private var localKeyMonitor: Any?

        init(panel: NSPanel, onDismiss: @escaping () -> Void) {
            self.panel = panel
            self.onDismiss = onDismiss
        }

        func start() {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in
                    self?.onDismiss()
                }
            }

            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // Escape
                    Task { @MainActor in
                        self?.onDismiss()
                    }
                }
            }

            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                // If click is inside our panel, let it through
                if event.window === self.panel { return event }
                Task { @MainActor in
                    self.onDismiss()
                }
                return event
            }

            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // Escape
                    Task { @MainActor in
                        self?.onDismiss()
                    }
                    return nil
                }
                return event
            }
        }

        func stop() {
            if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
            if let m = globalKeyMonitor { NSEvent.removeMonitor(m) }
            if let m = localClickMonitor { NSEvent.removeMonitor(m) }
            if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
            globalClickMonitor = nil
            globalKeyMonitor = nil
            localClickMonitor = nil
            localKeyMonitor = nil
        }
    }
#endif
