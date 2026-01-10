//
//  ExtensionCompactView.swift
//  ShareCore
//
//  Created by AI Assistant on 2026/01/04.
//

#if canImport(UIKit) && canImport(TranslationUIProvider)
import SwiftUI
import TranslationUIProvider

/// A compact view for iOS Translation Extension, mirroring the Mac MenuBarPopoverView style
public struct ExtensionCompactView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: HomeViewModel
    @State private var hasTriggeredAutoRequest = false
    
    private let context: TranslationUIProviderContext
    
    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }
    
    private var usageScene: ActionConfig.UsageScene {
        context.allowsReplacement ? .contextEdit : .contextRead
    }
    
    private var inputText: String {
        guard let text = context.inputText else { return "" }
        return String(text.characters)
    }
    
    public init(context: TranslationUIProviderContext) {
        self.context = context
        let initialScene: ActionConfig.UsageScene = context.allowsReplacement ? .contextEdit : .contextRead
        _viewModel = StateObject(wrappedValue: HomeViewModel(usageScene: initialScene))
    }
    
    public var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                selectedTextPreview
                
                Divider()
                    .background(colors.divider)
                
                actionChips
                
                if !viewModel.providerRuns.isEmpty {
                    resultSection
                } else if !viewModel.isLoadingConfiguration {
                    hintLabel
                }
                
                Spacer(minLength: 0)
            }
            .padding(16)
            
            if viewModel.isLoadingConfiguration {
                configurationLoadingOverlay
            }
        }
        .onAppear {
            AppPreferences.shared.refreshFromDefaults()
            
            if !hasTriggeredAutoRequest {
                viewModel.refreshConfiguration()
                viewModel.updateUsageScene(usageScene)
                viewModel.inputText = inputText
                hasTriggeredAutoRequest = true
                viewModel.performSelectedAction()
            }
        }
        .onChange(of: context.allowsReplacement) {
            viewModel.updateUsageScene(usageScene)
        }
    }
    
    // MARK: - Selected Text Preview
    
    private var selectedTextPreview: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 12))
                .foregroundColor(colors.textSecondary)
            
            Text(inputText)
                .font(.system(size: 14))
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer(minLength: 0)
            
            Text("\(inputText.count)")
                .font(.system(size: 11))
                .foregroundColor(colors.textSecondary.opacity(0.7))
            
            if AppPreferences.shared.ttsConfiguration.isValid && !inputText.isEmpty {
                inputSpeakButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colors.inputBackground)
        )
    }
    
    @ViewBuilder
    private var inputSpeakButton: some View {
        Button {
            viewModel.speakInputText()
        } label: {
            if viewModel.isSpeakingInputText {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(colors.accent)
            } else {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(colors.accent)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSpeakingInputText)
    }
    
    // MARK: - Action Chips
    
    private var actionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.actions) { action in
                    actionChip(for: action, isSelected: action.id == viewModel.selectedAction?.id)
                }
            }
        }
    }
    
    private func actionChip(for action: ActionConfig, isSelected: Bool) -> some View {
        Button {
            if viewModel.selectAction(action) {
                viewModel.performSelectedAction()
            }
        } label: {
            Text(action.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? colors.chipPrimaryText : colors.chipSecondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? colors.chipPrimaryBackground : colors.chipSecondaryBackground)
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Hint Label
    
    private var hintLabel: some View {
        Text(viewModel.placeholderHint)
            .font(.system(size: 13))
            .foregroundColor(colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }
    
    // MARK: - Result Section
    
    @ViewBuilder
    private var resultSection: some View {
        let showModelName = viewModel.providerRuns.count > 1
        ScrollView {
            VStack(spacing: 12) {
                ForEach(viewModel.providerRuns) { run in
                    ProviderResultCardView(
                        run: run,
                        showModelName: showModelName,
                        viewModel: viewModel,
                        onCopy: { text in
                            UIPasteboard.general.string = text
                        },
                        onReplace: context.allowsReplacement ? { text in
                            context.finish(translation: AttributedString(text))
                        } : nil
                    )
                }
            }
        }
    }
    
    // MARK: - Loading Overlay
    
    private var configurationLoadingOverlay: some View {
        ZStack {
            Color(UIColor.systemBackground).opacity(0.95)
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(colors.accent)
                    .controlSize(.regular)
                Text("Loading...")
                    .font(.system(size: 13))
                    .foregroundColor(colors.textSecondary)
            }
        }
    }
}
#endif
