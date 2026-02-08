//
//  LanguageSwitcherView.swift
//  ShareCore
//

import SwiftUI

/// A compact language switcher showing [🌐 Auto → 日本語 ▾].
/// Tapping the source or target language opens a picker.
/// Tapping the arrow swaps source and target (when source is not Auto).
public struct LanguageSwitcherView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var preferences = AppPreferences.shared

    @State private var isSourcePickerPresented = false
    @State private var isTargetPickerPresented = false

    /// Binding wrappers for the pickers
    @State private var sourceCode: String = ""
    @State private var targetCode: String = ""

    let globeFont: Font
    let textFont: Font
    let chevronFont: Font
    let foregroundColor: Color?

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    public init(
        globeFont: Font = .system(size: 12),
        textFont: Font = .system(size: 13, weight: .medium),
        chevronFont: Font = .system(size: 8),
        foregroundColor: Color? = nil
    ) {
        self.globeFont = globeFont
        self.textFont = textFont
        self.chevronFont = chevronFont
        self.foregroundColor = foregroundColor
    }

    private var resolvedColor: Color {
        foregroundColor ?? colors.textSecondary
    }

    private var sourceDisplayName: String {
        preferences.sourceLanguage.displayName
    }

    private var targetDisplayName: String {
        let target = preferences.targetLanguage
        if target == .appLanguage {
            return TargetLanguageOption.appLanguageEnglishName
        }
        return target.primaryLabel
    }

    private var canSwap: Bool {
        preferences.sourceLanguage != .auto
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(globeFont)
                .foregroundColor(resolvedColor)

            // Source language button
            Button {
                sourceCode = preferences.sourceLanguage.rawValue
                isSourcePickerPresented = true
            } label: {
                Text(sourceDisplayName)
                    .font(textFont)
                    .foregroundColor(resolvedColor)
            }
            .buttonStyle(.plain)

            // Arrow / swap button
            Button {
                if canSwap {
                    swapLanguages()
                }
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(resolvedColor.opacity(canSwap ? 1.0 : 0.5))
            }
            .buttonStyle(.plain)
            .disabled(!canSwap)

            // Target language button
            Button {
                targetCode = preferences.targetLanguage.rawValue
                isTargetPickerPresented = true
            } label: {
                Text(targetDisplayName)
                    .font(textFont)
                    .foregroundColor(resolvedColor)
            }
            .buttonStyle(.plain)

            Image(systemName: "chevron.up.chevron.down")
                .font(chevronFont)
                .foregroundColor(resolvedColor.opacity(0.6))
        }
        .sheet(isPresented: $isSourcePickerPresented) {
            LanguagePickerView(
                selectedCode: $sourceCode,
                isPresented: $isSourcePickerPresented,
                mode: .source
            )
            .presentationDetents([.medium, .large])
            .onChange(of: sourceCode) {
                if let option = SourceLanguageOption(rawValue: sourceCode) {
                    preferences.setSourceLanguage(option)
                }
            }
        }
        .sheet(isPresented: $isTargetPickerPresented) {
            LanguagePickerView(
                selectedCode: $targetCode,
                isPresented: $isTargetPickerPresented,
                mode: .target
            )
            .presentationDetents([.medium, .large])
            .onChange(of: targetCode) {
                if let option = TargetLanguageOption(rawValue: targetCode) {
                    preferences.setTargetLanguage(option)
                }
            }
        }
    }

    private func swapLanguages() {
        let currentSource = preferences.sourceLanguage
        let currentTarget = preferences.targetLanguage

        // Map source → target
        if let newTarget = targetLanguageOption(from: currentSource) {
            // Map target → source
            if let newSource = sourceLanguageOption(from: currentTarget) {
                preferences.setSourceLanguage(newSource)
                preferences.setTargetLanguage(newTarget)
            }
        }
    }

    /// Converts a SourceLanguageOption to the corresponding TargetLanguageOption.
    private func targetLanguageOption(from source: SourceLanguageOption) -> TargetLanguageOption? {
        switch source {
        case .auto: return nil
        case .english: return .english
        case .simplifiedChinese: return .simplifiedChinese
        case .japanese: return .japanese
        case .korean: return .korean
        case .french: return .french
        case .german: return .german
        case .spanish: return .spanish
        }
    }

    /// Converts a TargetLanguageOption to the corresponding SourceLanguageOption.
    private func sourceLanguageOption(from target: TargetLanguageOption) -> SourceLanguageOption? {
        switch target {
        case .appLanguage: return nil
        case .english: return .english
        case .simplifiedChinese: return .simplifiedChinese
        case .japanese: return .japanese
        case .korean: return .korean
        case .french: return .french
        case .german: return .german
        case .spanish: return .spanish
        }
    }
}
