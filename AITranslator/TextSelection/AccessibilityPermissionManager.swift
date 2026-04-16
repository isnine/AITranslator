//
//  AccessibilityPermissionManager.swift
//  TLingo
//
//  Manages Accessibility permission state with polling.
//

#if os(macOS)
    import AppKit
    import Combine

    nonisolated(unsafe) private let axTrustedPromptKey = "AXTrustedCheckOptionPrompt" as CFString

    @MainActor
    final class AccessibilityPermissionManager: ObservableObject {
        @Published private(set) var isAccessibilityGranted = false
        private var pollTimer: Timer?

        init() {
            isAccessibilityGranted = AXIsProcessTrusted()
        }

        /// Prompt the system accessibility permission dialog.
        func requestAccessibility() {
            let options = [axTrustedPromptKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            startPolling()
        }

        /// Open System Settings > Accessibility.
        func openAccessibilitySettings() {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            startPolling()
        }

        func startPolling() {
            guard pollTimer == nil else { return }
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let granted = AXIsProcessTrusted()
                    if granted != self.isAccessibilityGranted {
                        self.isAccessibilityGranted = granted
                    }
                    if granted {
                        self.stopPolling()
                    }
                }
            }
        }

        func stopPolling() {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
#endif
