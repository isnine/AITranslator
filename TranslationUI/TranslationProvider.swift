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
        // Load configuration from shared UserDefaults (XPC-based, no filesystem permission dialog)
        AppConfigurationStore.shared.loadFromSharedDefaults()
    }

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            ExtensionCompactView(context: context)
        }
    }
}
