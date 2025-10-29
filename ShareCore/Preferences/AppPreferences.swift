//
//  AppPreferences.swift
//  ShareCore
//
//  Created by Codex on 2025/10/27.
//

import Foundation
import Combine

public final class AppPreferences: ObservableObject {
    public static let appGroupSuiteName = "group.com.zanderwang.AITranslator"
    private static let sharedDefaultsInstance: UserDefaults = AppPreferences.resolveSharedDefaults()

    public static var sharedDefaults: UserDefaults {
        sharedDefaultsInstance
    }

    public static let shared = AppPreferences()

    @Published public private(set) var targetLanguage: TargetLanguageOption

    private let defaults: UserDefaults
    private var notificationObserver: NSObjectProtocol?

    private init(defaults: UserDefaults = AppPreferences.resolveSharedDefaults()) {
        self.defaults = defaults
        self.targetLanguage = AppPreferences.readTargetLanguage(from: defaults)

        notificationObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            self?.refreshFromDefaults()
        }
    }

    deinit {
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    public func setTargetLanguage(_ option: TargetLanguageOption) {
        guard targetLanguage != option else {
            defaults.set(option.rawValue, forKey: TargetLanguageOption.storageKey)
            defaults.synchronize()
            return
        }

        targetLanguage = option
        defaults.set(option.rawValue, forKey: TargetLanguageOption.storageKey)
        defaults.synchronize()
    }

    public func refreshFromDefaults() {
        defaults.synchronize()
        let resolved = AppPreferences.readTargetLanguage(from: defaults)
        guard resolved != targetLanguage else { return }
        targetLanguage = resolved
    }

    private static func resolveSharedDefaults() -> UserDefaults {
        UserDefaults.standard.addSuite(named: appGroupSuiteName)

        guard let defaults = UserDefaults(suiteName: appGroupSuiteName) else {
            assertionFailure("App group defaults unavailable. Falling back to standard defaults.")
            return .standard
        }
        return defaults
    }

    private static func readTargetLanguage(from defaults: UserDefaults) -> TargetLanguageOption {
        let stored = defaults.string(forKey: TargetLanguageOption.storageKey)
        return TargetLanguageOption(rawValue: stored ?? "") ?? .appLanguage
    }
}
