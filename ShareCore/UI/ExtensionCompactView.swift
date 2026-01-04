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
                // Selected text preview (single line)
                selectedTextPreview
                
                // Divider line between original text and actions
                Divider()
                    .background(colors.divider)
                
                // Action chips
                actionChips
                
                // Result section
                if !viewModel.providerRuns.isEmpty {
                    resultSection
                } else if !viewModel.isLoadingConfiguration {
                    hintLabel
                }
                
                Spacer(minLength: 0)
            }
            .padding(16)
            
            // Loading overlay when configuration is loading
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
            
            // Character count
            Text("\(inputText.count)")
                .font(.system(size: 11))
                .foregroundColor(colors.textSecondary.opacity(0.7))
            
            // TTS speak button (only show when TTS is configured)
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
        ScrollView {
            VStack(spacing: 12) {
                ForEach(viewModel.providerRuns) { run in
                    providerResultCard(for: run)
                }
            }
        }
    }
    
    // MARK: - Provider Result Card
    
    private func providerResultCard(for run: HomeViewModel.ProviderRunViewState) -> some View {
        let runID = run.id
        let showModelName = viewModel.providerRuns.count > 1
        return VStack(alignment: .leading, spacing: 10) {
            content(for: run)
            bottomInfoBar(for: run, runID: runID, showModelName: showModelName)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colors.cardBackground)
        )
    }
    
    // MARK: - Bottom Info Bar
    
    @ViewBuilder
    private func bottomInfoBar(
        for run: HomeViewModel.ProviderRunViewState,
        runID: String,
        showModelName: Bool
    ) -> some View {
        switch run.status {
        case .idle, .running:
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(colors.accent)
                if showModelName {
                    Text(run.modelDisplayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }
                Text("Processing...")
                    .font(.system(size: 12))
                    .foregroundColor(colors.textSecondary)
                Spacer()
            }
            
        case let .streaming(_, start):
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(colors.accent)
                if showModelName {
                    Text(run.modelDisplayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }
                Text("Generating...")
                    .font(.system(size: 12))
                    .foregroundColor(colors.textSecondary)
                Spacer()
                liveTimer(start: start)
            }
            
        case let .streamingSentencePairs(_, start):
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(colors.accent)
                if showModelName {
                    Text(run.modelDisplayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }
                Text("Translating...")
                    .font(.system(size: 12))
                    .foregroundColor(colors.textSecondary)
                Spacer()
                liveTimer(start: start)
            }
            
        case let .success(_, copyText, _, _, _, sentencePairs):
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(colors.success)
                    .font(.system(size: 13))
                
                if let duration = run.durationText {
                    Text(duration)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }
                
                if showModelName {
                    Text(run.modelDisplayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }
                
                Spacer()
                
                // Action buttons
                if sentencePairs.isEmpty {
                    actionButtons(copyText: copyText, runID: runID)
                }
            }
            
        case .failure:
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(colors.error)
                    .font(.system(size: 13))
                
                if let duration = run.durationText {
                    Text(duration)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }
                
                if showModelName {
                    Text(run.modelDisplayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }
                
                Spacer()
                
                Button {
                    viewModel.performSelectedAction()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    @ViewBuilder
    private func actionButtons(copyText: String, runID: String) -> some View {
        if context.allowsReplacement {
            Button {
                context.finish(translation: AttributedString(copyText))
            } label: {
                Label("Replace", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(colors.accent)
            
            compactSpeakButton(for: copyText, runID: runID)
            compactCopyButton(for: copyText)
        } else {
            compactSpeakButton(for: copyText, runID: runID)
            compactCopyButton(for: copyText)
        }
    }
    
    private func liveTimer(start: Date) -> some View {
        TimelineView(.periodic(from: start, by: 0.1)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Text(String(format: "%.1fs", elapsed))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(colors.textSecondary)
        }
    }
    
    @ViewBuilder
    private func compactSpeakButton(for text: String, runID: String) -> some View {
        // Only show speak button when TTS is configured
        if AppPreferences.shared.ttsConfiguration.isValid {
            let isSpeaking = viewModel.isSpeaking(runID: runID)
            Button {
                viewModel.speakResult(text, runID: runID)
            } label: {
                if isSpeaking {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(colors.accent)
                } else {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 13))
                        .foregroundColor(colors.accent)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSpeaking)
        }
    }
    
    @ViewBuilder
    private func compactCopyButton(for text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 13))
                .foregroundColor(colors.accent)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private func content(for run: HomeViewModel.ProviderRunViewState) -> some View {
        switch run.status {
        case .idle, .running:
            skeletonPlaceholder()
            
        case let .streaming(text, _):
            if text.isEmpty {
                skeletonPlaceholder()
            } else {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(colors.textPrimary)
                    .textSelection(.enabled)
            }
            
        case let .streamingSentencePairs(pairs, _):
            if pairs.isEmpty {
                skeletonPlaceholder()
            } else {
                sentencePairsView(pairs)
            }
            
        case let .success(text, copyText, _, diff, supplementalTexts, sentencePairs):
            VStack(alignment: .leading, spacing: 10) {
                if !sentencePairs.isEmpty {
                    sentencePairsView(sentencePairs)
                } else if let diff {
                    diffView(diff)
                } else {
                    let mainText = !supplementalTexts.isEmpty ? copyText : text
                    Text(mainText)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textPrimary)
                        .textSelection(.enabled)
                }
                
                if !supplementalTexts.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(supplementalTexts.enumerated()), id: \.offset) { entry in
                            Text(entry.element)
                                .font(.system(size: 13))
                                .foregroundColor(colors.textPrimary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            
        case let .failure(message, _):
            VStack(alignment: .leading, spacing: 8) {
                Text("Request Failed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colors.error)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(colors.textSecondary)
                    .textSelection(.enabled)
            }
        }
    }
    
    private func sentencePairsView(_ pairs: [SentencePair]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                VStack(alignment: .leading, spacing: 6) {
                    Text(pair.original)
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                        .textSelection(.enabled)
                    Text(pair.translation)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textPrimary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 6)
                
                if index < pairs.count - 1 {
                    Divider()
                }
            }
        }
    }
    
    @ViewBuilder
    private func diffView(_ diff: TextDiffBuilder.Presentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if diff.hasRemovals {
                let originalText = TextDiffBuilder.attributedString(
                    for: diff.originalSegments,
                    palette: colors,
                    colorScheme: colorScheme
                )
                Text(originalText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
            }
            
            if diff.hasAdditions || (!diff.hasRemovals && !diff.hasAdditions) {
                let revisedText = TextDiffBuilder.attributedString(
                    for: diff.revisedSegments,
                    palette: colors,
                    colorScheme: colorScheme
                )
                Text(revisedText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
            }
        }
    }
    
    private func skeletonPlaceholder() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<2, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(colors.skeleton)
                    .frame(height: 8)
                    .frame(maxWidth: index == 1 ? 120 : .infinity)
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
