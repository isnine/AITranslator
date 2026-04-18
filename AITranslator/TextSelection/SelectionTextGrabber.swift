//
//  SelectionTextGrabber.swift
//  TLingo
//
//  Resolves the currently selected text via AX → AppleScript → clipboard simulation.
//

#if os(macOS)
    import AppKit

    @MainActor
    enum SelectionTextGrabber {
        static func grab(near point: CGPoint) async -> String? {
            // Wait briefly so the target app's AX selection state is updated after mouse-up.
            try? await Task.sleep(for: .milliseconds(50))

            if let text = AccessibilityGrabber.grabSelectedText(near: point),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return text
            }

            if let text = await AppleScriptGrabber.grabFromSafari(),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return text
            }

            let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            guard frontBundleID != "com.apple.finder" else { return nil }

            if let text = await ClipboardGrabber.grabViaClipboard(),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return text
            }
            return nil
        }
    }
#endif
