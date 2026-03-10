#if os(macOS)

import Foundation
import SwiftUI

enum MacScreenshotExporter {

    /// Render a SwiftUI view offscreen and write it to PNG.
    ///
    /// This avoids Screen Recording permission and does not depend on `NSApp.windows`.
    @MainActor
    static func exportOffscreenPNG<V: View>(view: V, size: CGSize, to url: URL) throws {
        // ImageRenderer has been observed to hang early in app launch in some snapshot/automation contexts.
        // Use an NSHostingView + bitmap cache as a more predictable renderer.

        let root = view.frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true

        // Put the hosting view into an offscreen window; some AppKit drawing paths won't render
        // correctly (or can hang) if the view isn't in a window hierarchy.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .clear
        window.contentView = hosting

        // Let AppKit/SwiftUI settle
        window.displayIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "MacScreenshotExporter", code: 20, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap rep"])
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "MacScreenshotExporter", code: 21, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }
}

#endif
