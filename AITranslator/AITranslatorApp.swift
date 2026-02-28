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

    static var isSnapshotMode: Bool {
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
    static func configureSnapshotWindow() {
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
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
    /// macOS app delegate for managing global hotkeys and Services
    final class AppDelegate: NSObject, NSApplicationDelegate {
        /// Shared instance for accessing the received text from Services
        static var shared: AppDelegate?

        private var windowObservers: [NSObjectProtocol] = []

        func applicationDidFinishLaunching(_: Notification) {
            AppDelegate.shared = self

            // In snapshot mode, skip menu bar/hotkey setup and force window creation
            if AITranslatorApp.isSnapshotMode {
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
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                // Window was destroyed by SwiftUI; ask WindowGroup to create a new one
                NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
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
