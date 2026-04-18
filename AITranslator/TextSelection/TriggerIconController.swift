//
//  TriggerIconController.swift
//  TLingo
//
//  Manages trigger icon lifecycle: show near cursor, hover/click to translate or polish, auto-dismiss.
//

#if os(macOS)
    import AppKit

    enum TriggerAction {
        case translate
        case polish

        var symbolName: String {
            switch self {
            case .translate: return "translate"
            case .polish:    return "wand.and.sparkles"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .translate: return "Translate"
            case .polish:    return "Polish"
            }
        }
    }

    // MARK: - TriggerIconButton

    @MainActor
    final class TriggerIconButton: NSView {
        let action: TriggerAction
        var onMouseEntered: (() -> Void)?
        var onMouseExited: (() -> Void)?
        var onMouseDown: (() -> Void)?

        private var trackingArea: NSTrackingArea?
        private var isHovered = false

        init(action: TriggerAction, frame frameRect: NSRect) {
            self.action = action
            super.init(frame: frameRect)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError() }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea {
                removeTrackingArea(existing)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }

            if isHovered {
                ctx.setFillColor(NSColor.labelColor.withAlphaComponent(0.08).cgColor)
                let highlight = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
                highlight.fill()
            }

            let sizeConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let colorConfig = NSImage.SymbolConfiguration(hierarchicalColor: .labelColor)
            if let image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: action.accessibilityLabel)?
                .withSymbolConfiguration(sizeConfig.applying(colorConfig))
            {
                let imageSize = image.size
                let imageRect = NSRect(
                    x: (bounds.width - imageSize.width) / 2,
                    y: (bounds.height - imageSize.height) / 2,
                    width: imageSize.width,
                    height: imageSize.height
                )
                image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
        }

        override func mouseEntered(with _: NSEvent) {
            isHovered = true
            needsDisplay = true
            onMouseEntered?()
        }

        override func mouseExited(with _: NSEvent) {
            isHovered = false
            needsDisplay = true
            onMouseExited?()
        }

        override func mouseDown(with _: NSEvent) {
            onMouseDown?()
        }
    }

    // MARK: - TriggerContainerView

    @MainActor
    final class TriggerContainerView: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError() }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }

            let rect = bounds.insetBy(dx: 1, dy: 1)
            let radius = rect.height / 2

            ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            path.fill()

            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.setLineWidth(0.5)
            path.lineWidth = 0.5
            path.stroke()
        }
    }

    // MARK: - TriggerIconController

    @MainActor
    final class TriggerIconController {
        var onTranslateRequested: ((String) -> Void)?
        var onPolishRequested: ((String) -> Void)?
        var onDismissed: (() -> Void)?

        private var panel: TriggerIconPanel?
        private var anchorPoint: CGPoint?
        private var hoverTimer: Timer?
        private var pendingHoverAction: TriggerAction?
        private var autoDismissTimer: Timer?
        private var grabTask: Task<Void, Never>?

        func show(near point: CGPoint, allowPolish: Bool) {
            dismissSilently()

            anchorPoint = point

            let actions: [TriggerAction] = allowPolish ? [.translate, .polish] : [.translate]
            let buttonSize = TriggerIconPanel.height
            let panelWidth = allowPolish ? TriggerIconPanel.dualWidth : TriggerIconPanel.singleWidth
            let panelHeight = TriggerIconPanel.height

            let panel = TriggerIconPanel(width: panelWidth)
            let container = TriggerContainerView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))

            for (index, action) in actions.enumerated() {
                let xOffset = allowPolish ? (index == 0 ? 2 : panelWidth - buttonSize - 2) : 0
                let button = TriggerIconButton(
                    action: action,
                    frame: NSRect(x: xOffset, y: 0, width: buttonSize, height: buttonSize)
                )
                button.onMouseEntered = { [weak self] in self?.startHoverTimer(for: action) }
                button.onMouseExited = { [weak self] in self?.cancelHoverTimer() }
                button.onMouseDown = { [weak self] in self?.trigger(action: action) }
                container.addSubview(button)
            }

            if allowPolish {
                let divider = NSView(frame: NSRect(
                    x: panelWidth / 2 - 0.5,
                    y: 6,
                    width: 1,
                    height: panelHeight - 12
                ))
                divider.wantsLayer = true
                divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
                container.addSubview(divider)
            }

            panel.contentView = container

            let offset: CGFloat = 8
            var x = point.x + offset
            var y = point.y - offset - panelHeight

            if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main {
                let visibleFrame = screen.visibleFrame
                if x + panelWidth > visibleFrame.maxX { x = point.x - panelWidth - offset }
                if y + panelHeight > visibleFrame.maxY { y = point.y - panelHeight - offset }
                if x < visibleFrame.minX { x = visibleFrame.minX }
                if y < visibleFrame.minY { y = visibleFrame.minY }
            }

            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
            panel.alphaValue = 0
            panel.orderFront(nil)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 1
            }

            self.panel = panel

            startAutoDismissTimer()
        }

        func dismiss() {
            guard let panel else { return }
            cancelAllTimers()

            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    panel.contentView = nil
                    panel.close()
                    self?.cleanup()
                    self?.onDismissed?()
                }
            })
        }

        func dismissSilently() {
            grabTask?.cancel()
            grabTask = nil
            guard let panel else { return }
            cancelAllTimers()
            panel.contentView = nil
            panel.close()
            cleanup()
        }

        var isVisible: Bool {
            panel?.isVisible ?? false
        }

        private func cleanup() {
            panel = nil
            anchorPoint = nil
            pendingHoverAction = nil
        }

        // MARK: - Timers

        private func startHoverTimer(for action: TriggerAction) {
            cancelHoverTimer()
            cancelAutoDismissTimer()
            pendingHoverAction = action
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let pending = self.pendingHoverAction else { return }
                    self.trigger(action: pending)
                }
            }
        }

        private func cancelHoverTimer() {
            hoverTimer?.invalidate()
            hoverTimer = nil
            pendingHoverAction = nil
        }

        private func startAutoDismissTimer() {
            cancelAutoDismissTimer()
            autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.dismiss()
                }
            }
        }

        private func cancelAutoDismissTimer() {
            autoDismissTimer?.invalidate()
            autoDismissTimer = nil
        }

        private func cancelAllTimers() {
            cancelHoverTimer()
            cancelAutoDismissTimer()
        }

        private func trigger(action: TriggerAction) {
            guard let point = anchorPoint else { return }
            cancelAllTimers()

            guard let panel else { return }
            panel.contentView = nil
            panel.close()
            cleanup()

            grabTask = Task { @MainActor [weak self] in
                guard let text = await SelectionTextGrabber.grab(near: point),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !Task.isCancelled
                else { return }
                self?.grabTask = nil
                switch action {
                case .translate: self?.onTranslateRequested?(text)
                case .polish:    self?.onPolishRequested?(text)
                }
            }
        }
    }
#endif
