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
        #endif
    }

    private static var isSnapshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT")
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                #if os(macOS)
                .onAppear {
                    if Self.isSnapshotMode {
                        // Delay to ensure window is created
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            Self.configureSnapshotWindow()
                        }
                    }
                }
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .defaultLaunchBehavior(.presented)
        #endif
    }

    #if os(macOS)
    /// Configure the main window for screenshot capture mode
    private static func configureSnapshotWindow() {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        let frame = NSRect(x: 50, y: 200, width: 1280, height: 800)
        window.setFrame(frame, display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    #endif
}

#if os(macOS)
    /// macOS app delegate for managing global hotkeys and Services
    final class AppDelegate: NSObject, NSApplicationDelegate {
        /// Shared instance for accessing the received text from Services
        static var shared: AppDelegate?

        /// Text received from macOS Services (right-click menu)
        @Published var serviceReceivedText: String?

        private var isSnapshotMode: Bool {
            ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT")
        }

        func applicationDidFinishLaunching(_: Notification) {
            AppDelegate.shared = self

            // In snapshot mode, skip menu bar/hotkey setup and force window creation
            if isSnapshotMode {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                // Force SwiftUI to open a new window via the "New Window" menu action
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // This triggers SwiftUI's WindowGroup to create a new window instance
                    NSApp.sendAction(#selector(NSWindow.makeKeyAndOrderFront(_:)), to: nil, from: nil)

                    // Also try the newWindowForTab: selector which SwiftUI's WindowGroup responds to
                    if NSApp.windows.isEmpty || NSApp.windows.allSatisfy({ !$0.canBecomeMain }) {
                        NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.configureSnapshotWindow()
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
        }

        /// Configure window for screenshot capture
        private func configureSnapshotWindow() {
            // Try to find or force-create the main window
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                let frame = NSRect(x: 50, y: 200, width: 1280, height: 800)
                window.setFrame(frame, display: true, animate: false)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                print("📸 Snapshot: Window configured at \(frame)")
            } else {
                print("📸 Snapshot: No window found, retrying...")
                // Retry after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.configureSnapshotWindow()
                }
            }
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

        /// Opens or brings the main window to front
        func openMainWindow() {
            NSApp.activate(ignoringOtherApps: true)
            // Try to find existing window and bring it to front
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            }
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
                self.serviceReceivedText = text
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

    extension Notification.Name {
        static let serviceTextReceived = Notification.Name("serviceTextReceived")
    }
#endif
