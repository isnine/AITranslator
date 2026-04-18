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

            var wasDragOrMultiClick = clickCount >= 2
            if !wasDragOrMultiClick, let downPoint = mouseDownPoint {
                let dx = point.x - downPoint.x
                let dy = point.y - downPoint.y
                wasDragOrMultiClick = sqrt(dx * dx + dy * dy) > 5
            }
            mouseDownPoint = nil

            guard wasDragOrMultiClick else { return }
            onTextSelected?(point)
        }
    }
#endif
