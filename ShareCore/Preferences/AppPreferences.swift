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
    @Published public private(set) var ttsConfiguration: TTSConfiguration
    @Published public private(set) var currentConfigName: String?

    private let defaults: UserDefaults
    private var notificationObserver: NSObjectProtocol?

    private init(defaults: UserDefaults = AppPreferences.resolveSharedDefaults()) {
        self.defaults = defaults
        self.targetLanguage = AppPreferences.readTargetLanguage(from: defaults)
        self.ttsConfiguration = AppPreferences.readTTSConfiguration(from: defaults)
        self.currentConfigName = defaults.string(forKey: StorageKeys.currentConfigName)

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

    public func setTTSConfiguration(_ configuration: TTSConfiguration) {
        guard ttsConfiguration != configuration else {
            defaults.set(configuration.endpointURL.absoluteString, forKey: StorageKeys.ttsEndpoint)
            defaults.set(configuration.apiKey, forKey: StorageKeys.ttsAPIKey)
            defaults.set(configuration.model, forKey: StorageKeys.ttsModel)
            defaults.set(configuration.voice, forKey: StorageKeys.ttsVoice)
            defaults.synchronize()
            return
        }

        ttsConfiguration = configuration
        defaults.set(configuration.endpointURL.absoluteString, forKey: StorageKeys.ttsEndpoint)
        defaults.set(configuration.apiKey, forKey: StorageKeys.ttsAPIKey)
        defaults.set(configuration.model, forKey: StorageKeys.ttsModel)
        defaults.set(configuration.voice, forKey: StorageKeys.ttsVoice)
        defaults.synchronize()
    }

    public func setCurrentConfigName(_ name: String?) {
        guard currentConfigName != name else {
            return
        }

        currentConfigName = name
        if let name = name {
            defaults.set(name, forKey: StorageKeys.currentConfigName)
        } else {
            defaults.removeObject(forKey: StorageKeys.currentConfigName)
        }
        defaults.synchronize()
    }

    public var effectiveTTSConfiguration: TTSConfiguration {
        ttsConfiguration
    }

    public func refreshFromDefaults() {
        defaults.synchronize()
        let resolved = AppPreferences.readTargetLanguage(from: defaults)
        if resolved != targetLanguage {
            targetLanguage = resolved
        }

        let ttsConfig = AppPreferences.readTTSConfiguration(from: defaults)
        if ttsConfiguration != ttsConfig {
            ttsConfiguration = ttsConfig
        }

        let storedConfigName = defaults.string(forKey: StorageKeys.currentConfigName)
        if currentConfigName != storedConfigName {
            currentConfigName = storedConfigName
        }
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

    private static func readTTSConfiguration(from defaults: UserDefaults) -> TTSConfiguration {
        let endpointString = defaults.string(forKey: StorageKeys.ttsEndpoint) ?? ""
        let apiKey = defaults.string(forKey: StorageKeys.ttsAPIKey) ?? ""
        let model = defaults.string(forKey: StorageKeys.ttsModel) ?? ""
        let voice = defaults.string(forKey: StorageKeys.ttsVoice) ?? ""

        let endpointURL = URL(string: endpointString) ?? URL(string: "https://")!
        return TTSConfiguration(
            endpointURL: endpointURL,
            apiKey: apiKey,
            model: model,
            voice: voice
        )
    }
}

private enum StorageKeys {
    static let currentConfigName = "current_config_name"
    static let ttsEndpoint = "tts_endpoint_url"
    static let ttsAPIKey = "tts_api_key"
    static let ttsModel = "tts_model"
    static let ttsVoice = "tts_voice"
}
