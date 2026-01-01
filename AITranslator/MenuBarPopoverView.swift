//
//  MenuBarPopoverView.swift
//  AITranslator
//
//  Created by AI Assistant on 2025/12/31.
//

#if os(macOS)
import SwiftUI
import ShareCore
import Combine

/// A compact popover view for menu bar quick translation
struct MenuBarPopoverView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: HomeViewModel
    @State private var clipboardText: String = ""
    @State private var clipboardMonitorTimer: Timer?
    let onClose: () -> Void
    
    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: HomeViewModel(usageScene: .app))
    }
    
    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                headerSection
                
                Divider()
                    .background(colors.divider)
                
                // Clipboard content preview
                clipboardPreview
                
                // Action chips
                actionChips
                
                // Result section - reusing HomeView's result rendering
                if !viewModel.providerRuns.isEmpty {
                    Divider()
                        .background(colors.divider)
                    resultSection
                }
                
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: 360, height: 420)
            .background(colors.background)

            // Loading overlay when configuration is loading
            if viewModel.isLoadingConfiguration {
                configurationLoadingOverlay
            }
        }
        .frame(width: 360, height: 420)
        .onAppear {
            // Refresh configuration first, then load clipboard and execute
            viewModel.refreshConfiguration()
            loadClipboardAndExecute()
            startClipboardMonitor()
        }
        .onDisappear {
            stopClipboardMonitor()
        }
    }

    private var configurationLoadingOverlay: some View {
        ZStack {
            colors.background.opacity(0.95)
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
    
    private func loadClipboardAndExecute() {
        clipboardText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if !clipboardText.isEmpty {
            viewModel.inputText = clipboardText
            viewModel.performSelectedAction()
        }
    }
    
    private func startClipboardMonitor() {
        // Monitor clipboard every 0.5 seconds
        clipboardMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            checkClipboardChange()
        }
    }
    
    private func stopClipboardMonitor() {
        clipboardMonitorTimer?.invalidate()
        clipboardMonitorTimer = nil
    }
    
    private func checkClipboardChange() {
        let newClipboardText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Only trigger if clipboard content changed and is not empty
        if newClipboardText != clipboardText && !newClipboardText.isEmpty {
            clipboardText = newClipboardText
            viewModel.inputText = newClipboardText
            viewModel.performSelectedAction()
        }
    }
    
    private var headerSection: some View {
        HStack {
            Text("Quick Translate")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(colors.textPrimary)
            
            Spacer()
            
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var clipboardPreview: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 12))
                .foregroundColor(colors.textSecondary)
            
            if clipboardText.isEmpty {
                Text("Clipboard is empty")
                    .font(.system(size: 13))
                    .foregroundColor(colors.textSecondary)
                    .italic()
            } else {
                Text(clipboardText)
                    .font(.system(size: 13))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer(minLength: 0)
            
            if !clipboardText.isEmpty {
                Text("\(clipboardText.count)")
                    .font(.system(size: 11))
                    .foregroundColor(colors.textSecondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colors.inputBackground)
        )
    }
    
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
                    Capsule()
                        .fill(isSelected ? colors.chipPrimaryBackground : colors.chipSecondaryBackground)
                )
        }
        .buttonStyle(.plain)
    }
    
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
    
    // MARK: - Reused from HomeView
    
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

                if sentencePairs.isEmpty {
                    compactSpeakButton(for: copyText, runID: runID)
                    compactCopyButton(for: copyText)
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
        
        @unknown default:
            EmptyView()
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

    @ViewBuilder
    private func compactCopyButton(for text: String) -> some View {
        Button {
            copyToPasteboard(text)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 13))
                .foregroundColor(colors.accent)
        }
        .buttonStyle(.plain)
    }
    
    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
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
        
        @unknown default:
            EmptyView()
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
    
}
#endif
