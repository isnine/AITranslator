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
    @Published public private(set) var customConfigDirectory: URL?
    @Published public private(set) var useICloudForConfig: Bool
    @Published public private(set) var defaultAppHintDismissed: Bool
    #if os(macOS)
    @Published public private(set) var keepRunningWhenClosed: Bool
    #endif

    private let defaults: UserDefaults
    private var notificationObserver: NSObjectProtocol?

    private init(defaults: UserDefaults = AppPreferences.resolveSharedDefaults()) {
        self.defaults = defaults
        self.targetLanguage = AppPreferences.readTargetLanguage(from: defaults)
        self.ttsConfiguration = AppPreferences.readTTSConfiguration(from: defaults)
        self.currentConfigName = defaults.string(forKey: StorageKeys.currentConfigName)
        self.customConfigDirectory = AppPreferences.readCustomConfigDirectory(from: defaults)
        self.useICloudForConfig = defaults.bool(forKey: StorageKeys.useICloudForConfig)
        self.defaultAppHintDismissed = defaults.bool(forKey: StorageKeys.defaultAppHintDismissed)
        #if os(macOS)
        // Default to true - keep app running in menu bar when window is closed
        self.keepRunningWhenClosed = defaults.object(forKey: StorageKeys.keepRunningWhenClosed) == nil
            ? true
            : defaults.bool(forKey: StorageKeys.keepRunningWhenClosed)
        #endif

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
        print("[Preferences] setTargetLanguage called")
        print("[Preferences] Requested option: \(option.rawValue)")
        print("[Preferences] Current targetLanguage: \(targetLanguage.rawValue)")
        print("[Preferences] Are they equal? \(targetLanguage == option)")
        guard targetLanguage != option else {
            print("[Preferences] SKIPPING - values are equal, returning early")
            return
        }

        print("[Preferences] Proceeding with update...")
        targetLanguage = option
        defaults.set(option.rawValue, forKey: TargetLanguageOption.storageKey)
        defaults.synchronize()
        print("[Preferences] Updated targetLanguage to: \(targetLanguage.rawValue)")
        print("[Preferences] Wrote to UserDefaults key '\(TargetLanguageOption.storageKey)': \(option.rawValue)")
        
        // Verify the write
        let readBack = defaults.string(forKey: TargetLanguageOption.storageKey)
        print("[Preferences] Read back from UserDefaults: \(readBack ?? "nil")")
    }

    public func setTTSConfiguration(_ configuration: TTSConfiguration) {
        guard ttsConfiguration != configuration else { return }

        ttsConfiguration = configuration
        defaults.set(configuration.useBuiltInCloud, forKey: StorageKeys.ttsUseBuiltInCloud)
        defaults.set(configuration.endpointURL.absoluteString, forKey: StorageKeys.ttsEndpoint)
        defaults.set(configuration.apiKey, forKey: StorageKeys.ttsAPIKey)
        defaults.set(configuration.model, forKey: StorageKeys.ttsModel)
        defaults.set(configuration.voice, forKey: StorageKeys.ttsVoice)
        defaults.synchronize()
    }

    public func setCurrentConfigName(_ name: String?) {
        guard currentConfigName != name else { return }

        currentConfigName = name
        if let name {
            defaults.set(name, forKey: StorageKeys.currentConfigName)
        } else {
            defaults.removeObject(forKey: StorageKeys.currentConfigName)
        }
        defaults.synchronize()
    }

    public func setCustomConfigDirectory(_ url: URL?) {
        guard customConfigDirectory != url else { return }

        customConfigDirectory = url
        if let url = url {
            #if os(macOS)
            // Store bookmark data for security-scoped access (macOS only)
            if let bookmarkData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                defaults.set(bookmarkData, forKey: StorageKeys.customConfigDirectory)
            }
            #else
            // On iOS, just store the path directly (custom folders not supported)
            defaults.set(url.path, forKey: StorageKeys.customConfigDirectory)
            #endif
        } else {
            defaults.removeObject(forKey: StorageKeys.customConfigDirectory)
        }
        defaults.synchronize()
    }

    public func setUseICloudForConfig(_ useICloud: Bool) {
        guard useICloudForConfig != useICloud else { return }

        useICloudForConfig = useICloud
        defaults.set(useICloud, forKey: StorageKeys.useICloudForConfig)
        defaults.synchronize()
    }

    public func setDefaultAppHintDismissed(_ dismissed: Bool) {
        guard defaultAppHintDismissed != dismissed else { return }

        defaultAppHintDismissed = dismissed
        defaults.set(dismissed, forKey: StorageKeys.defaultAppHintDismissed)
        defaults.synchronize()
    }

    #if os(macOS)
    public func setKeepRunningWhenClosed(_ keepRunning: Bool) {
        guard keepRunningWhenClosed != keepRunning else { return }

        keepRunningWhenClosed = keepRunning
        defaults.set(keepRunning, forKey: StorageKeys.keepRunningWhenClosed)
        defaults.synchronize()
    }
    #endif

    // MARK: - Enabled Deployments (stored per provider name)

    /// Get enabled deployments for a specific provider
    /// - Parameter providerName: The provider's display name
    /// - Returns: The set of enabled deployment names, or nil if not stored (use config default)
    public func enabledDeployments(for providerName: String) -> Set<String>? {
        let key = StorageKeys.enabledDeploymentsPrefix + providerName
        guard let array = defaults.stringArray(forKey: key) else {
            return nil
        }
        return Set(array)
    }

    /// Set enabled deployments for a specific provider
    /// - Parameters:
    ///   - deployments: The set of enabled deployment names
    ///   - providerName: The provider's display name
    public func setEnabledDeployments(_ deployments: Set<String>, for providerName: String) {
        let key = StorageKeys.enabledDeploymentsPrefix + providerName
        defaults.set(Array(deployments), forKey: key)
        defaults.synchronize()
    }

    /// Remove enabled deployments setting for a provider (reverts to config default)
    /// - Parameter providerName: The provider's display name
    public func removeEnabledDeployments(for providerName: String) {
        let key = StorageKeys.enabledDeploymentsPrefix + providerName
        defaults.removeObject(forKey: key)
        defaults.synchronize()
    }

    /// Returns the iCloud Documents directory URL if available
    public static var iCloudDocumentsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
    }

    /// Check if iCloud is available
    public static var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
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

        let storedCustomDir = AppPreferences.readCustomConfigDirectory(from: defaults)
        if customConfigDirectory != storedCustomDir {
            customConfigDirectory = storedCustomDir
        }

        let storedUseICloud = defaults.bool(forKey: StorageKeys.useICloudForConfig)
        if useICloudForConfig != storedUseICloud {
            useICloudForConfig = storedUseICloud
        }

        #if os(macOS)
        let storedKeepRunning = defaults.object(forKey: StorageKeys.keepRunningWhenClosed) == nil
            ? true
            : defaults.bool(forKey: StorageKeys.keepRunningWhenClosed)
        if keepRunningWhenClosed != storedKeepRunning {
            keepRunningWhenClosed = storedKeepRunning
        }
        #endif
    }

    private static func readCustomConfigDirectory(from defaults: UserDefaults) -> URL? {
        #if os(macOS)
        guard let bookmarkData = defaults.data(forKey: StorageKeys.customConfigDirectory) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        // Start accessing security-scoped resource
        _ = url.startAccessingSecurityScopedResource()
        return url
        #else
        // On iOS, custom directories are not fully supported
        // Just return nil as we use iCloud or local storage
        return nil
        #endif
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
        let useBuiltInCloud = defaults.bool(forKey: StorageKeys.ttsUseBuiltInCloud)
        
        // If using built-in cloud, only voice matters
        if useBuiltInCloud {
            let voice = defaults.string(forKey: StorageKeys.ttsVoice) ?? TTSConfiguration.builtInCloudDefaultVoice
            return TTSConfiguration.builtInCloud(voice: voice)
        }
        
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
    static let ttsUseBuiltInCloud = "tts_use_builtin_cloud"
    static let ttsEndpoint = "tts_endpoint_url"
    static let ttsAPIKey = "tts_api_key"
    static let ttsModel = "tts_model"
    static let ttsVoice = "tts_voice"
    static let customConfigDirectory = "custom_config_directory"
    static let useICloudForConfig = "use_icloud_for_config"
    static let defaultAppHintDismissed = "default_app_hint_dismissed"
    /// Prefix for enabled deployments storage. Full key: "enabled_deployments.<providerName>"
    static let enabledDeploymentsPrefix = "enabled_deployments."
    #if os(macOS)
    static let keepRunningWhenClosed = "keep_running_when_closed"
    #endif
}
