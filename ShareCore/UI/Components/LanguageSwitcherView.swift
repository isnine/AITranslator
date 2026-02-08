//
//  LanguageSwitcherView.swift
//  ShareCore
//

import SwiftUI

/// A compact target language selector showing [🌐 日本語 ▾].
/// Tapping the language opens a picker to change the target language.
public struct LanguageSwitcherView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var preferences = AppPreferences.shared

    @State private var isTargetPickerPresented = false
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

    private var targetDisplayName: String {
        let target = preferences.targetLanguage
        if target == .appLanguage {
            return TargetLanguageOption.appLanguageEnglishName
        }
        return target.primaryLabel
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(globeFont)
                .foregroundColor(resolvedColor)

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
        .sheet(isPresented: $isTargetPickerPresented) {
            LanguagePickerView(
                selectedCode: $targetCode,
                isPresented: $isTargetPickerPresented
            )
            .presentationDetents([.medium, .large])
            .onChange(of: targetCode) {
                if let option = TargetLanguageOption(rawValue: targetCode) {
                    preferences.setTargetLanguage(option)
                }
            }
        }
    }
}
