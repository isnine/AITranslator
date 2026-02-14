//
//  ClipboardMonitor.swift
//  TLingo
//
//  Created by AI Assistant on 2026/01/08.
//

#if os(macOS)
    import AppKit
    import Foundation

    /// Monitors clipboard changes and tracks when content was last updated.
    /// Used to determine if clipboard content is "fresh" (recently copied).
    final class ClipboardMonitor {
        static let shared = ClipboardMonitor()

        /// The interval at which to check for clipboard changes (in seconds)
        private let checkInterval: TimeInterval = 1.0

        /// Timer for periodic clipboard checking
        private var timer: Timer?

        /// Last known changeCount from NSPasteboard
        private var lastChangeCount: Int = 0

        /// Timestamp when the clipboard content last changed
        private var lastChangeTime: Date?

        /// Whether monitoring is currently active
        private(set) var isMonitoring: Bool = false

        private init() {
            // Initialize with current pasteboard state
            lastChangeCount = NSPasteboard.general.changeCount
        }

        /// Starts monitoring clipboard changes.
        /// Call this once at app launch.
        func startMonitoring() {
            guard !isMonitoring else { return }
            isMonitoring = true

            // Update initial state
            lastChangeCount = NSPasteboard.general.changeCount

            // Create timer on main run loop
            timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
                self?.checkClipboardChange()
            }

            // Ensure timer fires even when UI is tracking
            RunLoop.main.add(timer!, forMode: .common)
        }

        /// Stops monitoring clipboard changes.
        func stopMonitoring() {
            timer?.invalidate()
            timer = nil
            isMonitoring = false
        }

        /// Checks if the clipboard has content that was updated within the specified time interval.
        /// - Parameter seconds: The time window in seconds (e.g., 5 means "within last 5 seconds")
        /// - Returns: `true` if clipboard content was updated within the specified time window
        func hasRecentContent(within seconds: TimeInterval) -> Bool {
            // First, check for any change that might have happened right now
            checkClipboardChange()

            guard let lastChange = lastChangeTime else {
                // No recorded change time means content existed before monitoring started
                return false
            }

            let elapsed = Date().timeIntervalSince(lastChange)
            return elapsed <= seconds
        }

        // MARK: - Private

        private func checkClipboardChange() {
            let currentChangeCount = NSPasteboard.general.changeCount

            if currentChangeCount != lastChangeCount {
                lastChangeCount = currentChangeCount
                lastChangeTime = Date()
            }
        }
    }
#endif
