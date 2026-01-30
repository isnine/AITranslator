import Foundation

public enum Logger {
    public static func debug(_ message: @autoclosure () -> String, tag: String? = nil) {
        #if DEBUG
            let prefix = tag?.isEmpty == false ? "[\(tag!)] " : ""
            print("\(prefix)\(message())")
        #endif
    }
}
