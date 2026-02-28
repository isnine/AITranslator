import Foundation

public enum PasteboardHelper {
    public static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        NotificationCenter.default.post(name: .didCopyFromApp, object: nil)
        #endif
    }
}

extension Notification.Name {
    /// Posted after the app copies content to the pasteboard.
    /// ClipboardMonitor observes this to avoid treating the copy as external content.
    public static let didCopyFromApp = Notification.Name("com.tlingo.didCopyFromApp")
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
