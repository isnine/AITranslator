//
//  AnonymousUserID.swift
//  ShareCore
//

import Foundation

public enum AnonymousUserID {
    private static let key = "marketplace_anonymous_user_id"

    public static var current: String {
        if let existing = AppPreferences.sharedDefaults.string(forKey: key) {
            return existing
        }
        let newID = UUID().uuidString
        AppPreferences.sharedDefaults.set(newID, forKey: key)
        return newID
    }
}
