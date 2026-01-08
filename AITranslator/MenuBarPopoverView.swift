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
    @ObservedObject private var hotKeyManager = HotKeyManager.shared
    @State private var inputText: String = ""
    @State private var showHotkeyHint: Bool = true
    @State private var clipboardSubscription: AnyCancellable?
    @FocusState private var isInputFocused: Bool
    let onClose: () -> Void
    
    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    /// Whether the quick translate hotkey is configured
    private var isHotkeyConfigured: Bool {
        !hotKeyManager.quickTranslateConfiguration.isEmpty
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
                
                // Editable input text
                inputSection
                
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
        .onReceive(NotificationCenter.default.publisher(for: .menuBarPopoverDidShow)) { _ in
            // Refresh configuration first, then load clipboard and execute
            viewModel.refreshConfiguration()
            loadClipboardAndExecute()
            
            // Subscribe to clipboard changes while popover is visible
            subscribeToClipboardChanges()
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarPopoverDidClose)) { _ in
            unsubscribeFromClipboardChanges()
        }
    }
    
    private func subscribeToClipboardChanges() {
        guard clipboardSubscription == nil else { return }
        clipboardSubscription = ClipboardMonitor.shared.clipboardChanged
            .receive(on: DispatchQueue.main)
            .sink { newContent in
                inputText = newContent
                viewModel.inputText = newContent
                viewModel.performSelectedAction()
            }
    }
    
    private func unsubscribeFromClipboardChanges() {
        clipboardSubscription?.cancel()
        clipboardSubscription = nil
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
        let clipboardContent = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasRecentClipboard = ClipboardMonitor.shared.hasRecentContent(within: 5)
        
        // If clipboard has recent content (within 5 seconds), always use it
        if hasRecentClipboard && !clipboardContent.isEmpty {
            inputText = clipboardContent
            viewModel.inputText = inputText
            viewModel.performSelectedAction()
        } else if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Otherwise, only load clipboard if input is empty (for display, no auto-translate)
            inputText = clipboardContent
        }
    }
    
    private func executeTranslation() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        viewModel.inputText = trimmedText
        viewModel.performSelectedAction()
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
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

            // Hotkey hint when not configured
            if !isHotkeyConfigured && showHotkeyHint {
                hotkeyHintView
            }
        }
    }

    private var hotkeyHintView: some View {
        HStack(spacing: 4) {
            Image(systemName: "keyboard")
                .font(.system(size: 10))
                .foregroundColor(colors.textSecondary.opacity(0.8))

            Text("Set a shortcut in Settings → Hotkeys")
                .font(.system(size: 11))
                .foregroundColor(colors.textSecondary.opacity(0.8))

            Spacer()

            Button {
                showHotkeyHint = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(colors.textSecondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }
    
    private var inputSection: some View {
        VStack(spacing: 8) {
            // Editable text input
            TextEditor(text: $inputText)
                .font(.system(size: 13))
                .foregroundColor(colors.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($isInputFocused)
                .frame(height: 60)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(colors.inputBackground)
                )
            
            // Bottom bar with character count and action buttons
            HStack(spacing: 8) {
                Text("\(inputText.count) characters")
                    .font(.system(size: 11))
                    .foregroundColor(colors.textSecondary.opacity(0.7))
                
                Spacer()
                
                // Input speak button (only show when TTS is configured)
                if AppPreferences.shared.ttsConfiguration.isValid && !inputText.isEmpty {
                    inputSpeakButton
                }
                
                // Translate button
                Button {
                    executeTranslation()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 12))
                        Text("Translate")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? colors.accent.opacity(0.5) : colors.accent)
                    )
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    @ViewBuilder
    private var inputSpeakButton: some View {
        Button {
            viewModel.inputText = inputText
            viewModel.speakInputText()
        } label: {
            if viewModel.isSpeakingInputText {
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
        .disabled(viewModel.isSpeakingInputText)
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
                viewModel.inputText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
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

        case let .success(_, copyText, _, _, supplementalTexts, sentencePairs):
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

                // Action buttons in bottom bar (only for plain text mode without supplementalTexts)
                if sentencePairs.isEmpty && supplementalTexts.isEmpty {
                    diffToggleButton(for: runID)
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
            copyToPasteboard(text)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 13))
                .foregroundColor(colors.accent)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func diffToggleButton(for runID: String) -> some View {
        if viewModel.hasDiff(for: runID) {
            let isShowingDiff = viewModel.isDiffShown(for: runID)
            Button {
                viewModel.toggleDiffDisplay(for: runID)
            } label: {
                Image(systemName: isShowingDiff ? "eye.slash" : "eye")
                    .font(.system(size: 13))
                    .foregroundColor(colors.accent)
            }
            .buttonStyle(.plain)
            .help(isShowingDiff ? "Hide changes" : "Show changes")
        }
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
            let showDiff = run.showDiff
            let runID = run.id
            VStack(alignment: .leading, spacing: 10) {
                if !sentencePairs.isEmpty {
                    sentencePairsView(sentencePairs)
                } else if let diff, showDiff {
                    diffView(diff)
                } else {
                    let mainText = !supplementalTexts.isEmpty ? copyText : text
                    Text(mainText)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textPrimary)
                        .textSelection(.enabled)
                }

                // Action buttons above divider (only when supplementalTexts exist)
                if sentencePairs.isEmpty && !supplementalTexts.isEmpty {
                    HStack(spacing: 10) {
                        Spacer()
                        diffToggleButton(for: runID)
                        compactSpeakButton(for: copyText, runID: runID)
                        compactCopyButton(for: copyText)
                    }
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
