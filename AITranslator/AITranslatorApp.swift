//
//  AITranslatorApp.swift
//  AITranslator
//
//  Created by Zander Wang on 2025/10/18.
//

import SwiftUI
import ShareCore
import Combine

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

    // Register global hotkey (Option + T by default)
    HotKeyManager.shared.register()

    // Register this object as a service provider for handling text from right-click menu
    NSApp.servicesProvider = self
    NSUpdateDynamicServices()
  }

  func applicationWillTerminate(_ notification: Notification) {
    // Unregister global hotkey
    HotKeyManager.shared.unregister()
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
