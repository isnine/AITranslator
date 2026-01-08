//
//  MenuBarManager.swift
//  AITranslator
//
//  Created by AI Assistant on 2025/12/31.
//

#if os(macOS)
import AppKit
import Combine
import ShareCore
import SwiftUI

/// Manages the menu bar status item with popover UI for quick action execution
@MainActor
final class MenuBarManager: NSObject, ObservableObject {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var popoverHostingController: NSHostingController<MenuBarPopoverView>?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    
    private let configurationStore: AppConfigurationStore
    
    private override init() {
        self.configurationStore = .shared
        super.init()
        
        // Listen for toggle popover notification from HotKeyManager
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTogglePopover),
            name: .toggleMenuBarPopover,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleTogglePopover() {
        Task { @MainActor in
            togglePopover(nil)
        }
    }
    
    /// Setup the menu bar status item
    func setup() {
        guard statusItem == nil else { return }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "AI Translator")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        setupPopover()
    }
    
    /// Remove the menu bar status item
    func teardown() {
        closePopover()
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        popover = nil
        popoverHostingController = nil
    }
    
    private func setupPopover() {
        let contentView = MenuBarPopoverView { [weak self] in
            self?.closePopover()
        }
        
        let hostingController = NSHostingController(rootView: contentView)
        popoverHostingController = hostingController
        
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 420)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController
        
        self.popover = popover
    }
    
    @objc private func togglePopover(_ sender: Any?) {
        if let popover = popover, popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }
    
    /// Public method to toggle popover visibility
    func toggle() {
        togglePopover(nil)
    }
    
    private func showPopover() {
        guard let button = statusItem?.button,
              let popover = popover else { return }
        
        // Recreate popover content to trigger onShow with fresh state
        let contentView = MenuBarPopoverView { [weak self] in
            self?.closePopover()
        }
        popoverHostingController?.rootView = contentView
        
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        
        // Notify that popover is now visible
        NotificationCenter.default.post(name: .menuBarPopoverDidShow, object: nil)
        
        // Setup event monitor to close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }
    
    private func closePopover() {
        popover?.performClose(nil)
        
        // Notify that popover is now hidden
        NotificationCenter.default.post(name: .menuBarPopoverDidClose, object: nil)
        
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

extension Notification.Name {
    static let menuBarPopoverDidShow = Notification.Name("menuBarPopoverDidShow")
    static let menuBarPopoverDidClose = Notification.Name("menuBarPopoverDidClose")
}
#endif
