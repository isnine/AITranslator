//
//  SelectionMonitor.swift
//  TLingo
//
//  Detects "looks like a text selection" gestures via global mouse monitoring.
//  Does not read text — that happens lazily when the user engages with the trigger icon.
//

#if os(macOS)
    import AppKit
    import os

    private let logger = os.Logger(subsystem: "com.zanderwang.AITranslator", category: "SelectionMonitor")

    @MainActor
    final class SelectionMonitor {
        var onTextSelected: ((CGPoint) -> Void)?
        var onMouseDown: ((CGPoint) -> Void)?

        nonisolated(unsafe) private var globalMonitor: Any?
        nonisolated(unsafe) private var mouseDownMonitor: Any?
        private var mouseDownPoint: CGPoint?
        private var isSuppressed = false
        nonisolated(unsafe) private var suppressTask: Task<Void, Never>?

        deinit {
            if let monitor = mouseDownMonitor { NSEvent.removeMonitor(monitor) }
            if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
            suppressTask?.cancel()
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

            var dragDistance: CGFloat = 0
            if let downPoint = mouseDownPoint {
                let dx = point.x - downPoint.x
                let dy = point.y - downPoint.y
                dragDistance = sqrt(dx * dx + dy * dy)
            }
            mouseDownPoint = nil

            let wasDragOrMultiClick = clickCount >= 2 || dragDistance > 5
            guard wasDragOrMultiClick else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, !self.isSuppressed else { return }

                if let text = AccessibilityGrabber.grabSelectedText(near: point),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    self.onTextSelected?(point)
                    return
                }

                // AX unavailable (Chrome / Electron / etc). Require a deliberate drag
                // to avoid showing the icon for stray double-clicks on empty space.
                if dragDistance > 20 {
                    self.onTextSelected?(point)
                }
            }
        }
    }
#endif
