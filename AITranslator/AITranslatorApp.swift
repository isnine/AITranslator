//
//  TLingoApp.swift
//  TLingo
//
//  Created by Zander Wang on 2025/10/18.
//

import SwiftUI
import ShareCore
import Combine
#if os(macOS)
import AppKit
#endif

@main
struct AITranslatorApp: App {
  #if os(macOS)
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  #endif

  var body: some Scene {
    WindowGroup {
      RootTabView()
    }
    #if os(macOS)
    .windowStyle(.hiddenTitleBar)
    #endif
  }
}

#if os(macOS)
/// macOS app delegate for managing global hotkeys and Services
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Shared instance for accessing the received text from Services
  static var shared: AppDelegate?

  /// Text received from macOS Services (right-click menu)
  @Published var serviceReceivedText: String?

  func applicationDidFinishLaunching(_ notification: Notification) {
    AppDelegate.shared = self

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

  func applicationWillTerminate(_ notification: Notification) {
    // Stop clipboard monitoring
    ClipboardMonitor.shared.stopMonitoring()

    // Unregister global hotkey
    HotKeyManager.shared.unregister()
    
    // Teardown menu bar
    Task { @MainActor in
      MenuBarManager.shared.teardown()
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // If user enabled "keep running when closed", don't quit when window closes
    return !AppPreferences.shared.keepRunningWhenClosed
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // When user clicks Dock icon and no windows are visible, open main window
    if !flag {
      openMainWindow()
    }
    return true
  }

  /// Opens or brings the main window to front
  func openMainWindow() {
    // Try to find existing window and bring it to front
    if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
      window.makeKeyAndOrderFront(nil)
    } else {
      // No window exists, create a new one using the File > New Window action
      NSApp.sendAction(#selector(NSDocumentController.newDocument(_:)), to: nil, from: nil)
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Service handler for translating text from right-click menu
  /// This method name must match the NSMessage value in Info.plist
  @objc func translateText(
    _ pboard: NSPasteboard,
    userData: String?,
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
