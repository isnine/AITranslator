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
    @Published public private(set) var ttsUsesDefaultConfiguration: Bool

    private let defaults: UserDefaults
    private var notificationObserver: NSObjectProtocol?

    private init(defaults: UserDefaults = AppPreferences.resolveSharedDefaults()) {
        self.defaults = defaults
        self.targetLanguage = AppPreferences.readTargetLanguage(from: defaults)
        let ttsState = AppPreferences.readTTSConfiguration(from: defaults)
        self.ttsConfiguration = ttsState.configuration
        self.ttsUsesDefaultConfiguration = ttsState.usesDefault

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

    public func setTTSUsesDefaultConfiguration(_ usesDefault: Bool) {
        guard ttsUsesDefaultConfiguration != usesDefault else {
            defaults.set(usesDefault, forKey: StorageKeys.ttsUseDefault)
            defaults.synchronize()
            return
        }

        ttsUsesDefaultConfiguration = usesDefault
        defaults.set(usesDefault, forKey: StorageKeys.ttsUseDefault)
        defaults.synchronize()
    }

    public var effectiveTTSConfiguration: TTSConfiguration {
        ttsUsesDefaultConfiguration ? .default : ttsConfiguration
    }

    public func refreshFromDefaults() {
        defaults.synchronize()
        let resolved = AppPreferences.readTargetLanguage(from: defaults)
        if resolved != targetLanguage {
            targetLanguage = resolved
        }

        let ttsState = AppPreferences.readTTSConfiguration(from: defaults)
        if ttsConfiguration != ttsState.configuration {
            ttsConfiguration = ttsState.configuration
        }

        if ttsUsesDefaultConfiguration != ttsState.usesDefault {
            ttsUsesDefaultConfiguration = ttsState.usesDefault
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

    private static func readTTSConfiguration(
        from defaults: UserDefaults
    ) -> (configuration: TTSConfiguration, usesDefault: Bool) {
        let usesDefault = defaults.object(forKey: StorageKeys.ttsUseDefault) as? Bool ?? true
        let endpointString = defaults.string(forKey: StorageKeys.ttsEndpoint)
        let apiKey = defaults.string(forKey: StorageKeys.ttsAPIKey)
        let model = defaults.string(forKey: StorageKeys.ttsModel)
        let voice = defaults.string(forKey: StorageKeys.ttsVoice)

        let configuration: TTSConfiguration
        if
            let endpointString,
            !endpointString.isEmpty,
            let endpointURL = URL(string: endpointString),
            let apiKey,
            !apiKey.isEmpty
        {
            configuration = TTSConfiguration(
                endpointURL: endpointURL,
                apiKey: apiKey,
                model: model?.isEmpty == false ? model! : TTSConfiguration.default.model,
                voice: voice?.isEmpty == false ? voice! : TTSConfiguration.default.voice
            )
        } else {
            configuration = .default
        }

        return (configuration, usesDefault)
    }
}

private enum StorageKeys {
    static let ttsUseDefault = "tts_use_default_configuration"
    static let ttsEndpoint = "tts_endpoint_url"
    static let ttsAPIKey = "tts_api_key"
    static let ttsModel = "tts_model"
    static let ttsVoice = "tts_voice"
}
