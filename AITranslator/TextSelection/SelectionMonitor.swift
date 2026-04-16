//
//  SelectionMonitor.swift
//  TLingo
//
//  Monitors global mouse events and detects text selection via 3-tier fallback.
//

#if os(macOS)
    import AppKit
    import os

    private let logger = os.Logger(subsystem: "com.zanderwang.AITranslator", category: "SelectionMonitor")

    @MainActor
    final class SelectionMonitor {
        var onTextSelected: ((String, CGPoint) -> Void)?
        var onMouseDown: ((CGPoint) -> Void)?

        nonisolated(unsafe) private var globalMonitor: Any?
        nonisolated(unsafe) private var mouseDownMonitor: Any?
        private var mouseDownPoint: CGPoint?
        private var isSuppressed = false
        nonisolated(unsafe) private var suppressTask: Task<Void, Never>?
        private var grabTask: Task<Void, Never>?

        deinit {
            if let monitor = mouseDownMonitor { NSEvent.removeMonitor(monitor) }
            if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
            suppressTask?.cancel()
            grabTask?.cancel()
        }

        func start() {
            guard globalMonitor == nil else { return }
            logger.debug("Selection monitoring started")

            mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                let screenPoint = NSEvent.mouseLocation
                Task { @MainActor in
                    self?.mouseDownPoint = screenPoint
                    self?.onMouseDown?(screenPoint)
                }
            }

            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                let screenPoint = NSEvent.mouseLocation
                let clickCount = event.clickCount
                Task { @MainActor in
                    self?.handleMouseUp(at: screenPoint, clickCount: clickCount)
                }
            }
        }

        func stop() {
            if let monitor = mouseDownMonitor {
                NSEvent.removeMonitor(monitor)
                mouseDownMonitor = nil
            }
            if let monitor = globalMonitor {
                NSEvent.removeMonitor(monitor)
                globalMonitor = nil
            }
            suppressTask?.cancel()
            suppressTask = nil
            grabTask?.cancel()
            grabTask = nil
            logger.debug("Selection monitoring stopped")
        }

        /// Suppress detection for 0.5s to prevent re-trigger after dismissal.
        func suppressBriefly() {
            isSuppressed = true
            suppressTask?.cancel()
            suppressTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.isSuppressed = false
            }
        }

        private func handleMouseUp(at point: CGPoint, clickCount: Int) {
            guard !isSuppressed else { return }

            let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            // Skip Finder to avoid file selection conflicts
            let isFinderFrontmost = frontBundleID == "com.apple.finder"

            // Determine if the gesture looks like a text selection
            var wasDragOrMultiClick = clickCount >= 2
            if !wasDragOrMultiClick, let downPoint = mouseDownPoint {
                let dx = point.x - downPoint.x
                let dy = point.y - downPoint.y
                let distance = sqrt(dx * dx + dy * dy)
                wasDragOrMultiClick = distance > 5
            }
            mouseDownPoint = nil

            grabTask?.cancel()
            grabTask = Task { @MainActor [weak self] in
                let clipboardCountAtMouseUp = NSPasteboard.general.changeCount

                // Wait 100ms for the target app to update its AX selection state
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }

                // Tier 1: Accessibility API
                if let text = AccessibilityGrabber.grabSelectedText(near: point),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    self.onTextSelected?(text, point)
                    return
                }

                guard wasDragOrMultiClick else { return }

                // Tier 2: AppleScript (Safari)
                if let text = await AppleScriptGrabber.grabFromSafari(),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    self.onTextSelected?(text, point)
                    return
                }

                guard !Task.isCancelled, !isFinderFrontmost else { return }

                // Short-circuit: if clipboard changed since mouse-up, user already pressed Cmd+C
                if NSPasteboard.general.changeCount != clipboardCountAtMouseUp {
                    if NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
                        return
                    }
                    if let text = NSPasteboard.general.string(forType: .string),
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        self.onTextSelected?(text, point)
                        return
                    }
                }

                // Tier 3: Clipboard simulation
                if let text = await ClipboardGrabber.grabViaClipboard(),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    self.onTextSelected?(text, point)
                    return
                }
            }
        }
    }
#endif
