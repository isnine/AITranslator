//
//  TranslationProvider.swift
//  TranslationUI
//
//  Created by Zander Wang on 2025/10/18.
//

import SwiftUI
import Foundation
import TranslationUIProvider
import ExtensionKit
import ShareCore

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
            HomeView(context: context)
        }
    }
}
