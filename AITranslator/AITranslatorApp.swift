//
//  AITranslatorApp.swift
//  TLingo
//
//  Created by Zander Wang on 2025/10/18.
//

import Combine
import ShareCore
import SwiftUI
#if os(macOS)
    import AppKit
#endif

@main
struct AITranslatorApp: App {
    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        // Debug: Print configuration on launch
        #if DEBUG
            print("🚀 AITranslator launching...")
            print(BuildEnvironment.debugDescription)
            // Print first/last 4 chars of secret for verification
            let secret = BuildEnvironment.cloudSecret
            if secret.isEmpty {
                print("⚠️ WARNING: Cloud secret is empty!")
            } else {
                let prefix = String(secret.prefix(4))
                let suffix = String(secret.suffix(4))
                print("🔑 Secret preview: \(prefix)...\(suffix) (\(secret.count) chars)")
            }
            // Also write args to /tmp (stdout is unreliable when launched via open)
            let dbg = "/tmp/tlingo_launch_args.txt"
            let args = ProcessInfo.processInfo.arguments.joined(separator: "\n") + "\n"
            try? args.write(toFile: dbg, atomically: true, encoding: .utf8)
        #endif
    }

    static var isSnapshotMode: Bool {
        HomeViewModel.isSnapshotMode
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            #if os(macOS)
                MainWindowContent()
            #else
                RootTabView()
            #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .defaultLaunchBehavior(.presented)
        #endif
        .handlesExternalEvents(matching: ["tlingo"])
    }

    #if os(macOS)
    /// Configure the main window for screenshot capture mode
    static func configureSnapshotWindow() {
        if let window = NSApp.windows.first { // Catalyst windows may report canBecomeMain=false early
            let frame = NSRect(x: 50, y: 200, width: 1280, height: 800)
            window.setFrame(frame, display: true, animate: false)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Retry after a delay if window not yet available
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Self.configureSnapshotWindow()
            }
        }
    }
    #endif
}

#if os(macOS)
    /// Wrapper view that captures the openWindow environment action and provides it to AppDelegate
    struct MainWindowContent: View {
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            RootTabView()
                .onAppear {
                    AppDelegate.shared?.openWindowAction = openWindow

                    if AITranslatorApp.isSnapshotMode {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            AITranslatorApp.configureSnapshotWindow()
                        }

                        // NOTE: Snapshot export is handled in AppDelegate.applicationDidFinishLaunching.
                    }
                }
        }
    }

    /// macOS app delegate for managing global hotkeys and Services
    // Simple helper to append trace lines without pulling in extra logging infra.
    fileprivate extension String {
        func appendLine(to path: String) throws {
            let url = URL(fileURLWithPath: path)
            let data = (self).data(using: .utf8)!
            if FileManager.default.fileExists(atPath: path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: [.atomic])
            }
        }
    }

    final class AppDelegate: NSObject, NSApplicationDelegate {
        /// Shared instance for accessing the received text from Services
        static var shared: AppDelegate?

        /// Stored SwiftUI openWindow action for creating new windows
        var openWindowAction: OpenWindowAction?

        private var windowObservers: [NSObjectProtocol] = []

        override init() {
            super.init()
            // Set shared early so SwiftUI views can access it during onAppear
            // (which may fire before applicationDidFinishLaunching)
            AppDelegate.shared = self
        }

        func applicationDidFinishLaunching(_: Notification) {

            // In snapshot mode, skip menu bar/hotkey setup and force window creation
            if AITranslatorApp.isSnapshotMode {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                // Debug marker: confirm we entered didFinish snapshot branch
                try? "didFinish snapshot\n".write(toFile: "/tmp/tlingo_didfinish.txt", atomically: true, encoding: .utf8)

                let args = ProcessInfo.processInfo.arguments
                // Debug: capture didFinish args (launched via `open` hides stdout)
                try? (args.joined(separator: "\n") + "\n").write(toFile: "/tmp/tlingo_didfinish_args.txt", atomically: true, encoding: .utf8)

                let requestedExportPath: String? = {
                    if let idx = args.firstIndex(of: "-MACOS_EXPORT_PATH"), idx + 1 < args.count {
                        return args[idx + 1]
                    }
                    return nil
                }()

                // If we were asked to export, render offscreen and quit (no Screen Recording permission needed).
                if let requestedExportPath {
                    let trace = "/tmp/tlingo_export_trace.txt"
                    func t(_ s: String) { try? (s + "\n").appendLine(to: trace) }

                    do {
                        t("ENTER didFinish export")
                        let fm = FileManager.default

                        // Debug build has App Sandbox disabled (ENABLE_APP_SANDBOX=NO), so we can write
                        // directly to the requested path inside the repo.
                        let outURL = URL(fileURLWithPath: requestedExportPath)
                        t("OUT: \(outURL.path)")
                        try fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)

                        // Timeout watchdog so automation never hangs forever.
                        var finished = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) {
                            guard !finished else { return }
                            finished = true
                            let fail = "FAIL\nTIMEOUT\n" + outURL.path + "\n"
                            try? fail.write(toFile: "/tmp/tlingo_export_status.txt", atomically: true, encoding: .utf8)
                            NSApp.terminate(nil)
                        }

                        // Give SwiftUI/AppKit a moment to settle before offscreen rendering.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            guard !finished else { return }
                            do {
                                let args = ProcessInfo.processInfo.arguments
                                let screen = MacSnapshotScreen.fromLaunchArguments(args)
                                let view = macSnapshotView(for: screen)

                                t("BEFORE export")
                                try MacScreenshotExporter.exportOffscreenPNG(
                                    view: view,
                                    size: CGSize(width: 1600, height: 800),
                                    to: outURL
                                )
                                t("AFTER export")

                                finished = true
                                let okText = "OK\n" + outURL.path + "\n"
                                try? okText.write(toFile: "/tmp/tlingo_export_status.txt", atomically: true, encoding: .utf8)

                                t("TERMINATE")
                                NSApp.terminate(nil)
                            } catch {
                                finished = true
                                t("CATCH(inner): \(String(describing: error))")
                                let failText = "FAIL\n" + String(describing: error) + "\n"
                                try? failText.write(toFile: "/tmp/tlingo_export_status.txt", atomically: true, encoding: .utf8)
                                NSApp.terminate(nil)
                            }
                        }
                    } catch {
                        t("CATCH: \(String(describing: error))")
                        let failText = "FAIL\n" + String(describing: error) + "\n"
                        try? failText.write(toFile: "/tmp/tlingo_export_status.txt", atomically: true, encoding: .utf8)
                        NSApp.terminate(nil)
                    }
                    return
                }

                // Otherwise (no export requested), keep previous behavior to show a window.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.sendAction(#selector(NSWindow.makeKeyAndOrderFront(_:)), to: nil, from: nil)

                    if NSApp.windows.isEmpty || NSApp.windows.allSatisfy({ !$0.canBecomeMain }) {
                        self.openWindowAction?(id: "main")
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        AITranslatorApp.configureSnapshotWindow()
                    }
                }
                return
            }

            // Start clipboard monitoring for auto-translate feature
            ClipboardMonitor.shared.startMonitoring()

            // Register global hotkey (Option + T by default)
            HotKeyManager.shared.register()

            // Setup menu bar status item
            Task { @MainActor in
                MenuBarManager.shared.setup()
            }

            // Register this object as a service provider for handling text from right-click menu
            NSApp.servicesProvider = self

            // Register the pasteboard types this app can receive via Services
            // This tells the system that this app can accept string data from the Services menu
            NSApp.registerServicesMenuSendTypes([.string], returnTypes: [])

            // Force update dynamic services
            NSUpdateDynamicServices()

            // Observe window lifecycle for smart Dock icon management
            setupWindowObservers()
        }

        func applicationWillTerminate(_: Notification) {
            // Stop clipboard monitoring
            ClipboardMonitor.shared.stopMonitoring()

            // Unregister global hotkey
            HotKeyManager.shared.unregister()

            // Teardown menu bar
            Task { @MainActor in
                MenuBarManager.shared.teardown()
            }

            // Remove window observers
            for observer in windowObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            windowObservers.removeAll()
        }

        func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
            // If user enabled "keep running when closed", don't quit when window closes
            return !AppPreferences.shared.keepRunningWhenClosed
        }

        func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
            // When user clicks Dock icon and no windows are visible, open main window
            if !flag {
                openMainWindow()
            }
            return true
        }

        // MARK: - Smart Dock Icon Management

        /// Show Dock icon and menu bar (regular app mode)
        func activateRegularMode() {
            NSApp.setActivationPolicy(.regular)
        }

        /// Hide Dock icon when no windows are visible (menu bar-only mode)
        private func activateAccessoryModeIfNeeded() {
            let hasVisibleMainWindow = NSApp.windows.contains {
                $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain
            }
            if !hasVisibleMainWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        private func setupWindowObservers() {
            // When a window becomes main, show Dock icon
            let mainObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.activateRegularMode()
            }

            // When a window closes, hide Dock icon if no other windows remain
            let closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Delay check to let the window fully close
                DispatchQueue.main.async {
                    self?.activateAccessoryModeIfNeeded()
                }
            }

            windowObservers = [mainObserver, closeObserver]
        }

        /// Opens or brings the main window to front
        func openMainWindow() {
            activateRegularMode()

            // Look for a usable main window (visible or minimized, not a stale closed window)
            if let window = NSApp.windows.first(where: {
                $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized)
            }) {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            } else if let openWindow = openWindowAction {
                openWindow(id: "main")
                // Delay activation to let the window appear after policy switch
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            } else {
                createMainWindowViaAppKit()
            }
        }

        /// Creates the main window directly via AppKit when SwiftUI's openWindow is unavailable
        private func createMainWindowViaAppKit() {
            let hostingController = NSHostingController(rootView: MainWindowContent())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hostingController
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        /// Service handler for translating text from right-click menu
        /// This method name must match the NSMessage value in Info.plist
        @objc func translateText(
            _ pboard: NSPasteboard,
            userData _: String?,
            error: AutoreleasingUnsafeMutablePointer<NSString?>
        ) {
            guard let text = pboard.string(forType: .string), !text.isEmpty else {
                error.pointee = "No text provided" as NSString
                return
            }

            // Store the received text and bring app to foreground
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)

                // Post notification so UI can respond
                NotificationCenter.default.post(
                    name: .serviceTextReceived,
                    object: nil,
                    userInfo: ["text": text]
                )
            }
        }
    }
#endif
