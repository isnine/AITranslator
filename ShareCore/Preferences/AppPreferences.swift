//
//  AppPreferences.swift
//  ShareCore
//
//  Created by Codex on 2025/10/27.
//

import Combine
import Foundation
import os

private let logger = os.Logger(subsystem: "com.zanderwang.AITranslator", category: "Preferences")

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
    @Published public private(set) var useICloudForConfig: Bool
    @Published public private(set) var defaultAppHintDismissed: Bool
    @Published public private(set) var voiceActionHintDismissed: Bool
    @Published public private(set) var enabledModelIDs: Set<String>
    @Published public private(set) var selectedVoiceID: String
    @Published public private(set) var isPremium: Bool
    @Published public private(set) var hasAcceptedDataSharing: Bool
    @Published public private(set) var accentTheme: AccentTheme
    @Published public private(set) var appleTranslateInstalledLanguages: Set<String>
    #if os(macOS)
        @Published public private(set) var textSelectionTranslationEnabled: Bool
        @Published public private(set) var hasCompletedOnboarding: Bool
    #endif

    private let defaults: UserDefaults
    private var notificationObserver: NSObjectProtocol?
    private var isRefreshing = false

    private init(defaults: UserDefaults = AppPreferences.resolveSharedDefaults()) {
        self.defaults = defaults
        targetLanguage = AppPreferences.readTargetLanguage(from: defaults)
        sourceLanguage = AppPreferences.readSourceLanguage(from: defaults)
        currentConfigName = defaults.string(forKey: StorageKeys.currentConfigName)
        useICloudForConfig = defaults.bool(forKey: StorageKeys.useICloudForConfig)
        defaultAppHintDismissed = defaults.bool(forKey: StorageKeys.defaultAppHintDismissed)
        voiceActionHintDismissed = defaults.bool(forKey: StorageKeys.voiceActionHintDismissed)
        enabledModelIDs = AppPreferences.readEnabledModelIDs(from: defaults)
        selectedVoiceID = defaults.string(forKey: StorageKeys.selectedVoiceID) ?? VoiceConfig.defaultVoiceID
        isPremium = defaults.bool(forKey: StorageKeys.isPremium)
        hasAcceptedDataSharing = defaults.bool(forKey: StorageKeys.hasAcceptedDataSharing)
        accentTheme = AppPreferences.readAccentTheme(from: defaults)
        appleTranslateInstalledLanguages = AppPreferences.readInstalledLanguages(from: defaults)

        // Clean up stale custom directory bookmark data from previous versions
        defaults.removeObject(forKey: "custom_config_directory")

        #if os(macOS)
            textSelectionTranslationEnabled = defaults.bool(forKey: StorageKeys.textSelectionTranslationEnabled)
            hasCompletedOnboarding = defaults.bool(forKey: StorageKeys.hasCompletedOnboarding)
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
        logger.debug("setTargetLanguage: \(option.rawValue, privacy: .public) (current: \(self.targetLanguage.rawValue, privacy: .public))")
        guard targetLanguage != option else { return }

        targetLanguage = option
        defaults.set(option.rawValue, forKey: TargetLanguageOption.storageKey)
        logger.debug("targetLanguage updated to \(self.targetLanguage.rawValue, privacy: .public)")
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

    public func setVoiceActionHintDismissed(_ dismissed: Bool) {
        guard voiceActionHintDismissed != dismissed else { return }

        voiceActionHintDismissed = dismissed
        defaults.set(dismissed, forKey: StorageKeys.voiceActionHintDismissed)
    }

    #if os(macOS)
        public func setTextSelectionTranslationEnabled(_ enabled: Bool) {
            guard textSelectionTranslationEnabled != enabled else { return }

            textSelectionTranslationEnabled = enabled
            defaults.set(enabled, forKey: StorageKeys.textSelectionTranslationEnabled)
        }

        public func setHasCompletedOnboarding(_ completed: Bool) {
            guard hasCompletedOnboarding != completed else { return }

            hasCompletedOnboarding = completed
            defaults.set(completed, forKey: StorageKeys.hasCompletedOnboarding)
        }
    #endif

    // MARK: - Enabled Models (flat model architecture)

    public func setEnabledModelIDs(_ ids: Set<String>) {
        guard enabledModelIDs != ids else { return }

        enabledModelIDs = ids
        defaults.set(Array(ids), forKey: StorageKeys.enabledModels)
    }

    // MARK: - Apple Translate Installed Languages

    public func setAppleTranslateInstalledLanguages(_ languages: Set<String>) {
        guard appleTranslateInstalledLanguages != languages else { return }

        appleTranslateInstalledLanguages = languages
        defaults.set(Array(languages), forKey: StorageKeys.appleTranslateInstalledLanguages)
    }

    // MARK: - Voice Selection

    public func setSelectedVoiceID(_ voiceID: String) {
        guard selectedVoiceID != voiceID else { return }

        selectedVoiceID = voiceID
        defaults.set(voiceID, forKey: StorageKeys.selectedVoiceID)
    }

    // MARK: - Data Sharing Consent

    public func setHasAcceptedDataSharing(_ accepted: Bool) {
        guard hasAcceptedDataSharing != accepted else { return }

        hasAcceptedDataSharing = accepted
        defaults.set(accepted, forKey: StorageKeys.hasAcceptedDataSharing)
    }

    // MARK: - Accent Theme

    public func setAccentTheme(_ theme: AccentTheme) {
        guard accentTheme != theme else { return }

        accentTheme = theme
        defaults.set(theme.rawValue, forKey: StorageKeys.accentTheme)
    }

    // MARK: - Satisfaction Prompt

    public var shouldShowSatisfactionPrompt: Bool {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let lastVersion = defaults.string(forKey: StorageKeys.satisfactionPromptLastVersion)
        let lastDate = defaults.object(forKey: StorageKeys.satisfactionPromptLastDate) as? Date

        let isNewVersion = lastVersion == nil || lastVersion != currentVersion
        let isOldEnough = lastDate == nil || Date().timeIntervalSince(lastDate!) >= 7 * 24 * 3600

        return isNewVersion && isOldEnough
    }

    public func markSatisfactionPromptShown() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        defaults.set(version, forKey: StorageKeys.satisfactionPromptLastVersion)
        defaults.set(Date(), forKey: StorageKeys.satisfactionPromptLastDate)
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

        let storedUseICloud = defaults.bool(forKey: StorageKeys.useICloudForConfig)
        if useICloudForConfig != storedUseICloud {
            useICloudForConfig = storedUseICloud
        }

        #if os(macOS)
            let storedTextSelection = defaults.bool(forKey: StorageKeys.textSelectionTranslationEnabled)
            if textSelectionTranslationEnabled != storedTextSelection {
                textSelectionTranslationEnabled = storedTextSelection
            }

            let storedOnboarding = defaults.bool(forKey: StorageKeys.hasCompletedOnboarding)
            if hasCompletedOnboarding != storedOnboarding {
                hasCompletedOnboarding = storedOnboarding
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

        let storedHasAcceptedDataSharing = defaults.bool(forKey: StorageKeys.hasAcceptedDataSharing)
        if hasAcceptedDataSharing != storedHasAcceptedDataSharing {
            hasAcceptedDataSharing = storedHasAcceptedDataSharing
        }

        let storedAccentTheme = AppPreferences.readAccentTheme(from: defaults)
        if accentTheme != storedAccentTheme {
            accentTheme = storedAccentTheme
        }

        let storedVoiceActionHint = defaults.bool(forKey: StorageKeys.voiceActionHintDismissed)
        if voiceActionHintDismissed != storedVoiceActionHint {
            voiceActionHintDismissed = storedVoiceActionHint
        }

        let storedInstalledLangs = AppPreferences.readInstalledLanguages(from: defaults)
        if appleTranslateInstalledLanguages != storedInstalledLangs {
            appleTranslateInstalledLanguages = storedInstalledLangs
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

    private static func readSourceLanguage(from defaults: UserDefaults) -> SourceLanguageOption {
        let stored = defaults.string(forKey: SourceLanguageOption.storageKey)
        return SourceLanguageOption(rawValue: stored ?? "") ?? .auto
    }

    private static func readAccentTheme(from defaults: UserDefaults) -> AccentTheme {
        AccentTheme(rawValue: defaults.string(forKey: StorageKeys.accentTheme) ?? "") ?? .default
    }

    private static func readEnabledModelIDs(from defaults: UserDefaults) -> Set<String> {
        guard let array = defaults.stringArray(forKey: StorageKeys.enabledModels) else {
            return []
        }
        return Set(array)
    }

    private static func readInstalledLanguages(from defaults: UserDefaults) -> Set<String> {
        guard let array = defaults.stringArray(forKey: StorageKeys.appleTranslateInstalledLanguages) else {
            return []
        }
        return Set(array)
    }
}

private enum StorageKeys {
    static let currentConfigName = "current_config_name"
    static let useICloudForConfig = "use_icloud_for_config"
    static let defaultAppHintDismissed = "default_app_hint_dismissed"
    static let voiceActionHintDismissed = "voice_action_hint_dismissed"
    /// Key for enabled model IDs (flat model architecture)
    static let enabledModels = "enabled_models"
    /// Key for selected TTS voice ID
    static let selectedVoiceID = "selected_voice_id"
    /// Key for premium subscription status
    static let isPremium = "is_premium_subscriber"
    /// Key for data sharing consent
    static let hasAcceptedDataSharing = "has_accepted_data_sharing"
    /// Key for accent theme preference
    static let accentTheme = "accent_theme"
    /// Key for Apple Translate installed language codes
    static let appleTranslateInstalledLanguages = "apple_translate_installed_languages"
    #if os(macOS)
        static let textSelectionTranslationEnabled = "text_selection_translation_enabled"
        static let hasCompletedOnboarding = "has_completed_onboarding"
    #endif
    static let satisfactionPromptLastVersion = "satisfaction_prompt_last_version"
    static let satisfactionPromptLastDate = "satisfaction_prompt_last_date"
}
