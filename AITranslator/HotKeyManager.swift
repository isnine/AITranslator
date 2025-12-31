//
//  HotKeyManager.swift
//  AITranslator
//
//  Created by AI Assistant on 2025/12/31.
//

#if os(macOS)
import AppKit
import Carbon
import Combine
import ShareCore

/// Hot key configuration
struct HotKeyConfiguration: Equatable, Codable {
  var keyCode: UInt32
  var modifiers: UInt32

  /// Default shortcut: Option + T
  static let `default` = HotKeyConfiguration(
    keyCode: UInt32(kVK_ANSI_T),
    modifiers: UInt32(optionKey)
  )

  /// Returns the display string for modifier keys
  var modifiersDisplayString: String {
    var result = ""
    if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
    return result
  }

  /// Returns the display string for the key
  var keyDisplayString: String {
    keyCodeToString(keyCode)
  }

  /// Returns the full shortcut display string
  var displayString: String {
    modifiersDisplayString + keyDisplayString
  }
}

/// Singleton class for managing global hotkeys.
/// Default shortcut is Option + T to show/hide the app window.
final class HotKeyManager: ObservableObject {
  static let shared = HotKeyManager()

  private var eventHotKey: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private var cancellables = Set<AnyCancellable>()

  /// Current hotkey configuration
  @Published private(set) var configuration: HotKeyConfiguration

  /// Storage keys
  private static let storageKeyCode = "hotkey_keycode"
  private static let storageModifiers = "hotkey_modifiers"

  private init() {
    let defaults = AppPreferences.sharedDefaults
    let storedKeyCode = defaults.object(forKey: Self.storageKeyCode) as? UInt32
    let storedModifiers = defaults.object(forKey: Self.storageModifiers) as? UInt32

    if let keyCode = storedKeyCode, let modifiers = storedModifiers {
      configuration = HotKeyConfiguration(keyCode: keyCode, modifiers: modifiers)
    } else {
      configuration = .default
    }
  }

  /// Updates the hotkey configuration
  func updateConfiguration(_ newConfiguration: HotKeyConfiguration) {
    guard configuration != newConfiguration else { return }

    // Unregister the old hotkey first
    unregisterHotKey()

    // Update configuration
    configuration = newConfiguration

    // Save to UserDefaults
    let defaults = AppPreferences.sharedDefaults
    defaults.set(newConfiguration.keyCode, forKey: Self.storageKeyCode)
    defaults.set(newConfiguration.modifiers, forKey: Self.storageModifiers)
    defaults.synchronize()

    // Register the new hotkey
    registerHotKey()
  }

  /// Registers the global hotkey
  func register() {
    guard eventHandler == nil else { return }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    // Install event handler
    let handlerResult = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ -> OSStatus in
        HotKeyManager.shared.handleHotKeyEvent()
        return noErr
      },
      1,
      &eventType,
      nil,
      &eventHandler
    )

    guard handlerResult == noErr else {
      print("Failed to install event handler: \(handlerResult)")
      return
    }

    registerHotKey()
  }

  /// Registers the hotkey with the system
  private func registerHotKey() {
    guard eventHotKey == nil else { return }

    var hotKeyID = EventHotKeyID()
    hotKeyID.signature = OSType("AITR".fourCharCodeValue)
    hotKeyID.id = 1

    // Register the hotkey
    let registerResult = RegisterEventHotKey(
      configuration.keyCode,
      configuration.modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &eventHotKey
    )

    if registerResult != noErr {
      print("Failed to register hotkey: \(registerResult)")
    }
  }

  /// Unregisters the hotkey from the system
  private func unregisterHotKey() {
    if let hotKey = eventHotKey {
      UnregisterEventHotKey(hotKey)
      eventHotKey = nil
    }
  }

  /// Unregisters the global hotkey and removes event handler
  func unregister() {
    unregisterHotKey()

    if let handler = eventHandler {
      RemoveEventHandler(handler)
      eventHandler = nil
    }
  }

  /// Handles the hotkey event
  private func handleHotKeyEvent() {
    DispatchQueue.main.async {
      self.toggleAppVisibility()
    }
  }

  /// Toggles the app window visibility
  private func toggleAppVisibility() {
    // Check if the app is active and has visible windows
    let hasVisibleWindow = NSApp.windows.contains { window in
      window.isVisible && !window.isMiniaturized && window.canBecomeMain
    }

    if NSApp.isActive && hasVisibleWindow {
      // App is active with visible windows, hide it
      NSApp.hide(nil)
    } else {
      // App is not active or has no visible windows, show it
      NSApp.activate(ignoringOtherApps: true)

      // If no visible windows, show the first available window
      if !hasVisibleWindow {
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
          window.makeKeyAndOrderFront(nil)
        }
      } else {
        // Activate existing visible window
        for window in NSApp.windows where window.isVisible && window.canBecomeMain {
          window.makeKeyAndOrderFront(nil)
          break
        }
      }
    }
  }
}

// MARK: - String Extension

private extension String {
  /// Converts a 4-character string to OSType
  var fourCharCodeValue: FourCharCode {
    guard count == 4 else { return 0 }

    var result: FourCharCode = 0
    for char in utf16 {
      result = (result << 8) + FourCharCode(char)
    }
    return result
  }
}

/// Converts a keyCode to a displayable string
private func keyCodeToString(_ keyCode: UInt32) -> String {
  switch Int(keyCode) {
  case kVK_ANSI_A: return "A"
  case kVK_ANSI_B: return "B"
  case kVK_ANSI_C: return "C"
  case kVK_ANSI_D: return "D"
  case kVK_ANSI_E: return "E"
  case kVK_ANSI_F: return "F"
  case kVK_ANSI_G: return "G"
  case kVK_ANSI_H: return "H"
  case kVK_ANSI_I: return "I"
  case kVK_ANSI_J: return "J"
  case kVK_ANSI_K: return "K"
  case kVK_ANSI_L: return "L"
  case kVK_ANSI_M: return "M"
  case kVK_ANSI_N: return "N"
  case kVK_ANSI_O: return "O"
  case kVK_ANSI_P: return "P"
  case kVK_ANSI_Q: return "Q"
  case kVK_ANSI_R: return "R"
  case kVK_ANSI_S: return "S"
  case kVK_ANSI_T: return "T"
  case kVK_ANSI_U: return "U"
  case kVK_ANSI_V: return "V"
  case kVK_ANSI_W: return "W"
  case kVK_ANSI_X: return "X"
  case kVK_ANSI_Y: return "Y"
  case kVK_ANSI_Z: return "Z"
  case kVK_ANSI_0: return "0"
  case kVK_ANSI_1: return "1"
  case kVK_ANSI_2: return "2"
  case kVK_ANSI_3: return "3"
  case kVK_ANSI_4: return "4"
  case kVK_ANSI_5: return "5"
  case kVK_ANSI_6: return "6"
  case kVK_ANSI_7: return "7"
  case kVK_ANSI_8: return "8"
  case kVK_ANSI_9: return "9"
  case kVK_Space: return "Space"
  case kVK_Return: return "↩"
  case kVK_Tab: return "⇥"
  case kVK_Escape: return "⎋"
  case kVK_Delete: return "⌫"
  case kVK_ForwardDelete: return "⌦"
  case kVK_UpArrow: return "↑"
  case kVK_DownArrow: return "↓"
  case kVK_LeftArrow: return "←"
  case kVK_RightArrow: return "→"
  case kVK_F1: return "F1"
  case kVK_F2: return "F2"
  case kVK_F3: return "F3"
  case kVK_F4: return "F4"
  case kVK_F5: return "F5"
  case kVK_F6: return "F6"
  case kVK_F7: return "F7"
  case kVK_F8: return "F8"
  case kVK_F9: return "F9"
  case kVK_F10: return "F10"
  case kVK_F11: return "F11"
  case kVK_F12: return "F12"
  default: return "?"
  }
}
#endif
