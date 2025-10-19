//
//  TranslationProvider.swift
//  TranslationUI
//
//  Created by Zander Wang on 2025/10/18.
//

import SwiftUI
import TranslationUIProvider
import ExtensionKit
import ShareCore

@main
final class TranslationProviderExtension: TranslationUIProviderExtension {

    required init() {}

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            HomeView(context: context)
        }
    }
}
