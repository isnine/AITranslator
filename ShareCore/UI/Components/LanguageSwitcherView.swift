//
//  LanguageSwitcherView.swift
//  ShareCore
//

import SwiftUI

/// A language selector that adapts to context:
/// - Translate actions: `[Auto ▾]  →  [日本語 ▾]` with optional resolved-target overlay
/// - Other actions:     `[🌐 日本語 ▾]` (original layout)
public struct LanguageSwitcherView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var preferences = AppPreferences.shared

    @State private var isTargetPickerPresented = false
    @State private var isSourcePickerPresented = false
    @State private var targetCode: String = ""
    @State private var sourceCode: String = ""

    let globeFont: Font
    let textFont: Font
    let chevronFont: Font
    let foregroundColor: Color?
    /// Whether the current action is a translate action (shows directional layout).
    let isTranslateAction: Bool
    /// When non-nil, target language was auto-corrected to this value.
    let resolvedTarget: TargetLanguageOption?
    /// Called when the user picks an override target from the resolved-target menu.
    let onOverrideTarget: ((TargetLanguageOption) -> Void)?
    /// When non-nil, shows the source selector with a strikethrough and this detected language label beside it.
    let detectedSource: SourceLanguageOption?
    /// Called when the user picks a new source language (so callers can clear detectedSource state).
    let onSourceChanged: (() -> Void)?

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    public init(
        globeFont: Font = .system(size: 12),
        textFont: Font = .system(size: 13, weight: .medium),
        chevronFont: Font = .system(size: 8),
        foregroundColor: Color? = nil,
        isTranslateAction: Bool = false,
        resolvedTarget: TargetLanguageOption? = nil,
        onOverrideTarget: ((TargetLanguageOption) -> Void)? = nil,
        detectedSource: SourceLanguageOption? = nil,
        onSourceChanged: (() -> Void)? = nil
    ) {
        self.globeFont = globeFont
        self.textFont = textFont
        self.chevronFont = chevronFont
        self.foregroundColor = foregroundColor
        self.isTranslateAction = isTranslateAction
        self.resolvedTarget = resolvedTarget
        self.onOverrideTarget = onOverrideTarget
        self.detectedSource = detectedSource
        self.onSourceChanged = onSourceChanged
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

    private var sourceDisplayName: String {
        let source = preferences.sourceLanguage
        return source.primaryLabel
    }

    private var filteredTargetOptions: [TargetLanguageOption] {
        let appleTranslateEnabled = preferences.enabledModelIDs.contains(ModelConfig.appleTranslateID)
        return TargetLanguageOption.filteredSelectionOptions(
            appleTranslateEnabled: appleTranslateEnabled,
            installedLanguages: preferences.appleTranslateInstalledLanguages
        )
    }

    private var sourceRows: [LanguageRow] {
        SourceLanguageOption.allCases.map {
            LanguageRow(id: $0.rawValue, primaryLabel: $0.primaryLabel, secondaryLabel: $0.secondaryLabel)
        }
    }

    @ViewBuilder
    private var layoutContent: some View {
        HStack(spacing: 0) {
            if isTranslateAction {
                directionalLayout
            } else {
                standardLayout
                if let resolved = resolvedTarget, let onOverride = onOverrideTarget {
                    resolvedTargetMenu(resolved: resolved, onOverride: onOverride)
                }
            }
        }
    }

    public var body: some View {
        layoutContent
        .sheet(isPresented: $isTargetPickerPresented) {
            LanguagePickerView(
                selectedCode: $targetCode,
                isPresented: $isTargetPickerPresented,
                availableOptions: filteredTargetOptions,
                title: String(localized: "Select Target Language")
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isSourcePickerPresented) {
            LanguagePickerView(
                selectedCode: $sourceCode,
                isPresented: $isSourcePickerPresented,
                rows: sourceRows,
                title: String(localized: "Select Source Language")
            )
            .presentationDetents([.medium, .large])
        }
        .onChange(of: targetCode) {
            if let option = TargetLanguageOption(rawValue: targetCode) {
                preferences.setTargetLanguage(option)
            }
        }
        .onChange(of: sourceCode) {
            if let option = SourceLanguageOption(rawValue: sourceCode) {
                preferences.setSourceLanguage(option)
                onSourceChanged?()
            }
        }
    }

    // MARK: - Standard layout: [🌐 日本語 ▾]

    private var standardLayout: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(globeFont)
                .foregroundColor(resolvedColor)

            Button {
                targetCode = preferences.targetLanguage.rawValue
                isTargetPickerPresented = true
            } label: {
                Text(targetDisplayName)
                    .font(textFont)
                    .foregroundColor(resolvedColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(.plain)

            Image(systemName: "chevron.up.chevron.down")
                .font(chevronFont)
                .foregroundColor(resolvedColor.opacity(0.6))
        }
    }

    // MARK: - Directional layout: [Auto ▾] → [日本語 ▾]

    private func languageLabel(_ text: String) -> some View {
        Text(text)
            .font(textFont)
            .foregroundColor(resolvedColor)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var directionalLayout: some View {
        HStack(spacing: 4) {
            // Source language button
            Button {
                sourceCode = preferences.sourceLanguage.rawValue
                isSourcePickerPresented = true
            } label: {
                HStack(spacing: 3) {
                    let showDetected = detectedSource != nil && detectedSource != preferences.sourceLanguage
                    languageLabel(sourceDisplayName)
                        .strikethrough(showDetected)
                    if showDetected, let detected = detectedSource {
                        languageLabel(detected.primaryLabel)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(chevronFont)
                        .foregroundColor(resolvedColor.opacity(0.6))
                }
            }
            .buttonStyle(.plain)

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(resolvedColor.opacity(0.5))
                .padding(.horizontal, 2)

            // Target language button / menu
            if let resolved = resolvedTarget, let onOverride = onOverrideTarget {
                let showResolved = resolved != preferences.targetLanguage
                Menu {
                    if showResolved {
                        Button {
                            onOverride(preferences.targetLanguage)
                        } label: {
                            Label(preferences.targetLanguage.primaryLabel, systemImage: "arrow.uturn.backward")
                        }
                        Divider()
                    }
                    ForEach(filteredTargetOptions.filter { $0 != resolved }) { option in
                        Button(option.primaryLabel) {
                            onOverride(option)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        languageLabel(targetDisplayName)
                            .strikethrough(showResolved)
                        if showResolved {
                            languageLabel(resolved.primaryLabel)
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(chevronFont)
                            .foregroundColor(resolvedColor.opacity(0.6))
                    }
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif
                .buttonStyle(.plain)
                .fixedSize()
            } else {
                Button {
                    targetCode = preferences.targetLanguage.rawValue
                    isTargetPickerPresented = true
                } label: {
                    HStack(spacing: 3) {
                        languageLabel(targetDisplayName)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(chevronFont)
                            .foregroundColor(resolvedColor.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Resolved target menu

    @ViewBuilder
    private func resolvedTargetMenu(
        resolved: TargetLanguageOption,
        onOverride: @escaping (TargetLanguageOption) -> Void
    ) -> some View {
        let preferred = preferences.targetLanguage
        let menuTextFont: Font = globeFont == .system(size: 10) ? .system(size: 11, weight: .medium) : .system(size: 12, weight: .medium)
        let menuChevronFont: Font = globeFont == .system(size: 10) ? .system(size: 6) : .system(size: 7)
        let menuArrowFont: Font = globeFont == .system(size: 10) ? .system(size: 8, weight: .semibold) : .system(size: 9, weight: .semibold)

        Menu {
            if resolved != preferred {
                Button {
                    onOverride(preferred)
                } label: {
                    Label(preferred.primaryLabel, systemImage: "arrow.uturn.backward")
                }
                Divider()
            }
            ForEach(filteredTargetOptions.filter { $0 != resolved }) { option in
                Button(option.primaryLabel) {
                    onOverride(option)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.right")
                    .font(menuArrowFont)
                Text(resolved.primaryLabel)
                    .font(menuTextFont)
                Image(systemName: "chevron.up.chevron.down")
                    .font(menuChevronFont)
                    .opacity(0.6)
            }
            .foregroundColor(colors.textSecondary)
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .fixedSize()
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
}
