//
//  ClipboardMonitor.swift
//  AITranslator
//
//  Created by AI Assistant on 2026/01/08.
//

#if os(macOS)
import AppKit
import Combine
import Foundation

/// Monitors clipboard changes and tracks when content was last updated.
/// Used to determine if clipboard content is "fresh" (recently copied).
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    /// Publisher that emits when clipboard content changes (with the new content)
    let clipboardChanged = PassthroughSubject<String, Never>()

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

    /// Gets the clipboard content if it was updated within the specified time interval.
    /// - Parameter seconds: The time window in seconds
    /// - Returns: The clipboard string if it's recent, otherwise `nil`
    func getRecentContent(within seconds: TimeInterval) -> String? {
        guard hasRecentContent(within: seconds) else { return nil }
        return NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private

    private func checkClipboardChange() {
        let currentChangeCount = NSPasteboard.general.changeCount

        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            lastChangeTime = Date()
            
            // Notify subscribers about the change
            if let content = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
                clipboardChanged.send(content)
            }
        }
    }
}
#endif
