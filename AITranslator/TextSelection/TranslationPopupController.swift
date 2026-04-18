//
//  TranslationPopupController.swift
//  TLingo
//
//  Manages the lifecycle and positioning of the translation popup panel.
//

#if os(macOS)
    import AppKit
    import ShareCore
    import SwiftUI

    enum PopupAction {
        case translate
        case polish
    }

    @MainActor
    final class TranslationPopupController {
        var onDismiss: (() -> Void)?

        private var panel: TranslationPopupPanel?
        private var dismissMonitor: PopupDismissMonitor?
        private var currentViewModel: HomeViewModel?

        func showAtCursor(text: String, action: PopupAction = .translate) {
            dismiss()

            let viewModel = HomeViewModel()
            currentViewModel = viewModel

            if action == .polish, let polishAction = viewModel.actions.first(where: { $0.outputType == .diff }) {
                viewModel.selectedActionID = polishAction.id
            }

            let initialSize = CGSize(width: 400, height: 320)
            let newPanel = TranslationPopupPanel(contentRect: NSRect(origin: .zero, size: initialSize))

            let contentView = PopupTranslationView(viewModel: viewModel)
            let hostingView = NSHostingView(rootView: contentView)
            hostingView.sizingOptions = []
            newPanel.contentView = hostingView
            panel = newPanel

            // Position near cursor
            let cursorPos = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorPos) })
                ?? NSScreen.main
                ?? NSScreen.screens.first

            if let screen {
                let visibleFrame = screen.visibleFrame
                let offset: CGFloat = 20

                var x = cursorPos.x + offset
                var y = cursorPos.y - initialSize.height - offset

                // Clamp to screen bounds
                if x + initialSize.width > visibleFrame.maxX {
                    x = cursorPos.x - initialSize.width - offset
                }
                if y < visibleFrame.minY {
                    y = cursorPos.y + offset
                }
                if x < visibleFrame.minX { x = visibleFrame.minX + 8 }
                if y + initialSize.height > visibleFrame.maxY {
                    y = visibleFrame.maxY - initialSize.height - 8
                }

                newPanel.setFrame(NSRect(x: x, y: y, width: initialSize.width, height: initialSize.height), display: true)
            }

            newPanel.orderFront(nil)
            startDismissMonitor()

            // Set text and trigger translation
            viewModel.inputText = text
            viewModel.performSelectedAction()
        }

        func dismiss() {
            dismissMonitor?.stop()
            dismissMonitor = nil
            panel?.contentView = nil
            panel?.close()
            panel = nil
            currentViewModel = nil
            onDismiss?()
        }

        var isVisible: Bool {
            panel?.isVisible ?? false
        }

        private func startDismissMonitor() {
            guard let panel else { return }
            dismissMonitor = PopupDismissMonitor(panel: panel) { [weak self] in
                self?.dismiss()
            }
            dismissMonitor?.start()
        }
    }
#endif
