//
//  TranslationProvider.swift
//  TranslationUI
//
//  Created by Zander Wang on 2025/10/18.
//

import ExtensionKit
import Foundation
import ShareCore
import SwiftUI
import TranslationUIProvider

@main
final class TranslationProviderExtension: TranslationUIProviderExtension {
    required init() {
        UserDefaults.standard.addSuite(named: AppPreferences.appGroupSuiteName)
        AppPreferences.shared.refreshFromDefaults()
        // Force reload configuration from disk to ensure we have the latest config
        // This is critical because the extension may have been launched after
        // the main app modified the configuration
        AppConfigurationStore.shared.reloadCurrentConfiguration()
    }

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            ExtensionCompactView(context: context)
        }
    }
}
