//
//  AppPreferences.swift
//  ShareCore
//
//  Created by Codex on 2025/10/27.
//

import Combine
import Foundation

public final class AppPreferences: ObservableObject {
    public static let appGroupSuiteName = "group.com.zanderwang.AITranslator"
    private static let sharedDefaultsInstance: UserDefaults = AppPreferences.resolveSharedDefaults()

    public static var sharedDefaults: UserDefaults {
        sharedDefaultsInstance
    }

    public static let shared = AppPreferences()

    @Published public private(set) var targetLanguage: TargetLanguageOption
    @Published public private(set) var sourceLanguage: SourceLanguageOption
    @Published public private(set) var currentConfigName: String?
    @Published public private(set) var customConfigDirectory: URL?
    @Published public private(set) var useICloudForConfig: Bool
    @Published public private(set) var defaultAppHintDismissed: Bool
    @Published public private(set) var enabledModelIDs: Set<String>
    @Published public private(set) var selectedVoiceID: String
    @Published public private(set) var isPremium: Bool
    #if os(macOS)
        @Published public private(set) var keepRunningWhenClosed: Bool
    #endif

    private let defaults: UserDefaults
    private var notificationObserver: NSObjectProtocol?
    private var isRefreshing = false

    private init(defaults: UserDefaults = AppPreferences.resolveSharedDefaults()) {
        self.defaults = defaults
        targetLanguage = AppPreferences.readTargetLanguage(from: defaults)
        sourceLanguage = AppPreferences.readSourceLanguage(from: defaults)
        currentConfigName = defaults.string(forKey: StorageKeys.currentConfigName)
        customConfigDirectory = AppPreferences.readCustomConfigDirectory(from: defaults)
        useICloudForConfig = defaults.bool(forKey: StorageKeys.useICloudForConfig)
        defaultAppHintDismissed = defaults.bool(forKey: StorageKeys.defaultAppHintDismissed)
        enabledModelIDs = AppPreferences.readEnabledModelIDs(from: defaults)
        selectedVoiceID = defaults.string(forKey: StorageKeys.selectedVoiceID) ?? VoiceConfig.defaultVoiceID
        isPremium = defaults.bool(forKey: StorageKeys.isPremium)
        #if os(macOS)
            // Default to true - keep app running in menu bar when window is closed
            keepRunningWhenClosed = defaults.object(forKey: StorageKeys.keepRunningWhenClosed) == nil
                ? true
                : defaults.bool(forKey: StorageKeys.keepRunningWhenClosed)
        #endif

        notificationObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshFromDefaults()
            }
        }
    }

    deinit {
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    public func setTargetLanguage(_ option: TargetLanguageOption) {
        Logger.debug("[Preferences] setTargetLanguage called")
        Logger.debug("[Preferences] Requested option: \(option.rawValue)")
        Logger.debug("[Preferences] Current targetLanguage: \(targetLanguage.rawValue)")
        Logger.debug("[Preferences] Are they equal? \(targetLanguage == option)")
        guard targetLanguage != option else {
            Logger.debug("[Preferences] SKIPPING - values are equal, returning early")
            return
        }

        Logger.debug("[Preferences] Proceeding with update...")
        targetLanguage = option
        defaults.set(option.rawValue, forKey: TargetLanguageOption.storageKey)
        Logger.debug("[Preferences] Updated targetLanguage to: \(targetLanguage.rawValue)")
        Logger.debug("[Preferences] Wrote to UserDefaults key '\(TargetLanguageOption.storageKey)': \(option.rawValue)")

        // Verify the write
        let readBack = defaults.string(forKey: TargetLanguageOption.storageKey)
        Logger.debug("[Preferences] Read back from UserDefaults: \(readBack ?? "nil")")
    }

    public func setSourceLanguage(_ option: SourceLanguageOption) {
        guard sourceLanguage != option else { return }
        sourceLanguage = option
        defaults.set(option.rawValue, forKey: SourceLanguageOption.storageKey)
    }

    public func setCurrentConfigName(_ name: String?) {
        guard currentConfigName != name else { return }

        currentConfigName = name
        if let name {
            defaults.set(name, forKey: StorageKeys.currentConfigName)
        } else {
            defaults.removeObject(forKey: StorageKeys.currentConfigName)
        }
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
    }

    public func setUseICloudForConfig(_ useICloud: Bool) {
        guard useICloudForConfig != useICloud else { return }

        useICloudForConfig = useICloud
        defaults.set(useICloud, forKey: StorageKeys.useICloudForConfig)
    }

    public func setDefaultAppHintDismissed(_ dismissed: Bool) {
        guard defaultAppHintDismissed != dismissed else { return }

        defaultAppHintDismissed = dismissed
        defaults.set(dismissed, forKey: StorageKeys.defaultAppHintDismissed)
    }

    #if os(macOS)
        public func setKeepRunningWhenClosed(_ keepRunning: Bool) {
            guard keepRunningWhenClosed != keepRunning else { return }

            keepRunningWhenClosed = keepRunning
            defaults.set(keepRunning, forKey: StorageKeys.keepRunningWhenClosed)
        }
    #endif

    // MARK: - Enabled Models (flat model architecture)

    public func setEnabledModelIDs(_ ids: Set<String>) {
        guard enabledModelIDs != ids else { return }

        enabledModelIDs = ids
        defaults.set(Array(ids), forKey: StorageKeys.enabledModels)
    }

    // MARK: - Voice Selection

    public func setSelectedVoiceID(_ voiceID: String) {
        guard selectedVoiceID != voiceID else { return }

        selectedVoiceID = voiceID
        defaults.set(voiceID, forKey: StorageKeys.selectedVoiceID)
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
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let resolved = AppPreferences.readTargetLanguage(from: defaults)
        if resolved != targetLanguage {
            targetLanguage = resolved
        }

        let resolvedSource = AppPreferences.readSourceLanguage(from: defaults)
        if resolvedSource != sourceLanguage {
            sourceLanguage = resolvedSource
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

        let storedEnabledModels = AppPreferences.readEnabledModelIDs(from: defaults)
        if enabledModelIDs != storedEnabledModels {
            enabledModelIDs = storedEnabledModels
        }

        let storedVoiceID = defaults.string(forKey: StorageKeys.selectedVoiceID) ?? VoiceConfig.defaultVoiceID
        if selectedVoiceID != storedVoiceID {
            selectedVoiceID = storedVoiceID
        }

        let storedIsPremium = defaults.bool(forKey: StorageKeys.isPremium)
        if isPremium != storedIsPremium {
            isPremium = storedIsPremium
        }
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

    private static func readSourceLanguage(from defaults: UserDefaults) -> SourceLanguageOption {
        let stored = defaults.string(forKey: SourceLanguageOption.storageKey)
        return SourceLanguageOption(rawValue: stored ?? "") ?? .auto
    }

    private static func readEnabledModelIDs(from defaults: UserDefaults) -> Set<String> {
        guard let array = defaults.stringArray(forKey: StorageKeys.enabledModels) else {
            return []
        }
        return Set(array)
    }
}

private enum StorageKeys {
    static let currentConfigName = "current_config_name"
    static let customConfigDirectory = "custom_config_directory"
    static let useICloudForConfig = "use_icloud_for_config"
    static let defaultAppHintDismissed = "default_app_hint_dismissed"
    /// Key for enabled model IDs (flat model architecture)
    static let enabledModels = "enabled_models"
    /// Key for selected TTS voice ID
    static let selectedVoiceID = "selected_voice_id"
    /// Key for premium subscription status
    static let isPremium = "is_premium_subscriber"
    #if os(macOS)
        static let keepRunningWhenClosed = "keep_running_when_closed"
    #endif
}
