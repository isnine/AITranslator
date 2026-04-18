//
//  AccessibilityGrabber.swift
//  TLingo
//
//  Text selection via macOS Accessibility API (Tier 1).
//

#if os(macOS)
    import AppKit
    import ApplicationServices

    enum AccessibilityGrabber {
        struct SelectionResult {
            let text: String
            let isEditable: Bool
        }

        /// Read the selected text from the frontmost application using the Accessibility API.
        /// Validates that the click occurred near the focused element to filter stale selections.
        @MainActor
        static func grabSelectedText(near clickPoint: CGPoint? = nil) -> String? {
            grabSelection(near: clickPoint)?.text
        }

        @MainActor
        static func grabSelection(near clickPoint: CGPoint? = nil) -> SelectionResult? {
            guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }

            let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

            var focusedValue: CFTypeRef?
            let focusResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                &focusedValue
            )
            guard focusResult == .success,
                  let focusedRef = focusedValue,
                  CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
            else { return nil }

            let focusedElement = unsafeBitCast(focusedRef, to: AXUIElement.self)

            var selectedValue: CFTypeRef?
            let selectResult = AXUIElementCopyAttributeValue(
                focusedElement,
                kAXSelectedTextAttribute as CFString,
                &selectedValue
            )
            guard selectResult == .success, let text = selectedValue as? String, !text.isEmpty else {
                return nil
            }

            if let clickPoint {
                var positionValue: CFTypeRef?
                var sizeValue: CFTypeRef?
                AXUIElementCopyAttributeValue(focusedElement, kAXPositionAttribute as CFString, &positionValue)
                AXUIElementCopyAttributeValue(focusedElement, kAXSizeAttribute as CFString, &sizeValue)

                if let positionValue, let sizeValue,
                   CFGetTypeID(positionValue) == AXValueGetTypeID(),
                   CFGetTypeID(sizeValue) == AXValueGetTypeID()
                {
                    var position = CGPoint.zero
                    var size = CGSize.zero
                    AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
                    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

                    // NSEvent.mouseLocation uses bottom-left origin; AX uses top-left origin
                    let screenHeight = NSScreen.screens.first?.frame.height ?? 0
                    let axClickY = screenHeight - clickPoint.y

                    let tolerance: CGFloat = 20
                    let expandedRect = CGRect(
                        x: position.x - tolerance,
                        y: position.y - tolerance,
                        width: size.width + tolerance * 2,
                        height: size.height + tolerance * 2
                    )

                    if !expandedRect.contains(CGPoint(x: clickPoint.x, y: axClickY)) {
                        return nil
                    }
                }
            }

            var settable: DarwinBoolean = false
            let settableResult = AXUIElementIsAttributeSettable(
                focusedElement,
                kAXValueAttribute as CFString,
                &settable
            )
            let isEditable = (settableResult == .success && settable.boolValue)

            return SelectionResult(text: text, isEditable: isEditable)
        }
    }
#endif
