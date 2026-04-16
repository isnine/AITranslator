//
//  AppleScriptGrabber.swift
//  TLingo
//
//  Text selection via AppleScript for Safari (Tier 2).
//

#if os(macOS)
    import AppKit

    enum AppleScriptGrabber {
        /// Grab selected text from Safari using AppleScript + JavaScript.
        static func grabFromSafari() async -> String? {
            guard let frontApp = NSWorkspace.shared.frontmostApplication,
                  frontApp.bundleIdentifier == "com.apple.Safari"
            else { return nil }

            let script = """
                tell application "Safari"
                    do JavaScript "window.getSelection().toString()" in front document
                end tell
                """

            return await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let appleScript = NSAppleScript(source: script) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    var error: NSDictionary?
                    let result = appleScript.executeAndReturnError(&error)

                    if error != nil {
                        continuation.resume(returning: nil)
                    } else {
                        let text = result.stringValue
                        continuation.resume(returning: text?.isEmpty == false ? text : nil)
                    }
                }
            }
        }
    }
#endif
