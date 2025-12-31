//
//  AITranslatorApp.swift
//  AITranslator
//
//  Created by Zander Wang on 2025/10/18.
//

import SwiftUI
import ShareCore

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
/// macOS app delegate for managing global hotkeys
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Register global hotkey (Option + T by default)
    HotKeyManager.shared.register()
  }

  func applicationWillTerminate(_ notification: Notification) {
    // Unregister global hotkey
    HotKeyManager.shared.unregister()
  }
}
#endif
