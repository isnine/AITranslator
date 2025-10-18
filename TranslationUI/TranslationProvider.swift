//
//  TranslationProvider.swift
//  TranslationUI
//
//  Created by Zander Wang on 2025/10/18.
//

import SwiftUI
import TranslationUIProvider
import ExtensionKit

@main
class TranslationProviderExtension: TranslationUIProviderExtension {

    required init() {
    }

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            TranslationProviderView(context: context)
        }
    }
}

struct TranslationProviderView: View {
    @State var context: TranslationUIProviderContext
    @State var translated: String = ""

    init(context c: TranslationUIProviderContext) {
        context = c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show the source text.  Keep in mind that this is an 
            // AttributedString, and SwiftUI will render it accordingly unless you
            // override display properties
            Text(context.inputText ?? "")

            Text(translated)

            Button(action: translate) {
                Label("Translate", systemImage: "translate")
            }

            // Replacement is optional, even if it is supported by the source app.
            // You should Not offer replacement, when the source app does not support it
            Button(action: replaceText) {
                Text("Replace With Translation")
            }.disabled(!context.allowsReplacement)

        }.padding(8)
    }

    private func translate() {
        if let toTranslate = context.inputText, !toTranslate.characters.isEmpty {
            // Here you call your own translate function
            translated = toTranslate.description
        }
    }

	// MARK: Host interaction
    private func replaceText() {
        context.finish(translation: AttributedString(translated))
    }

	// You can expand the sheet height, if you know you will need it
    private func expand() {
        context.expandSheet()
    }

}
