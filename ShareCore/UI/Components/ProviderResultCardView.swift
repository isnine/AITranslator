//
//  ProviderResultCardView.swift
//  ShareCore
//
//  Shared provider result card component used by HomeView, MenuBarPopoverView, and ExtensionCompactView
//

import SwiftUI

// MARK: - Provider Result Card View

/// A reusable card component for displaying provider execution results
public struct ProviderResultCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let run: HomeViewModel.ModelRunViewState
    let showModelName: Bool
    let viewModel: HomeViewModel
    let onCopy: (String) -> Void
    let onReplace: ((String) -> Void)?
    let onChat: (() -> Void)?

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    public init(
        run: HomeViewModel.ModelRunViewState,
        showModelName: Bool,
        viewModel: HomeViewModel,
        onCopy: @escaping (String) -> Void,
        onReplace: ((String) -> Void)? = nil,
        onChat: (() -> Void)? = nil
    ) {
        self.run = run
        self.showModelName = showModelName
        self.viewModel = viewModel
        self.onCopy = onCopy
        self.onReplace = onReplace
        self.onChat = onChat
    }

    public var body: some View {
        let hasDiff = viewModel.hasDiff(for: run.id)
        let isShowingDiff = viewModel.isDiffShown(for: run.id)
        let isSpeaking = viewModel.isSpeaking(runID: run.id)
        let copyText: String = {
            if case let .success(_, ct, _, _, _, _) = run.status { return ct }
            return ""
        }()

        VStack(alignment: .leading, spacing: 10) {
            ResultContentView(
                run: run,
                hasDiff: hasDiff,
                isShowingDiff: isShowingDiff,
                onToggleDiff: { viewModel.toggleDiffDisplay(for: run.id) },
                isSpeaking: isSpeaking,
                onSpeak: { viewModel.speakResult(copyText, runID: run.id) },
                onStopSpeaking: { viewModel.stopSpeaking() },
                onCopy: onCopy,
                onReplace: onReplace,
                onChat: onChat
            )
            ResultBottomInfoBar(
                run: run,
                showModelName: showModelName,
                hasDiff: hasDiff,
                isShowingDiff: isShowingDiff,
                onToggleDiff: { viewModel.toggleDiffDisplay(for: run.id) },
                isSpeaking: isSpeaking,
                onSpeak: { viewModel.speakResult(copyText, runID: run.id) },
                onStopSpeaking: { viewModel.stopSpeaking() },
                onRetry: { viewModel.performSelectedAction() },
                onCopy: onCopy,
                onReplace: onReplace,
                onChat: onChat
            )
        }
        .padding(14)
        .background(cardBackground)
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(colors.cardBackground)
    }
}

// MARK: - Result Content View

/// Displays the main content of a provider result based on its status
struct ResultContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingErrorDetails = false

    let run: HomeViewModel.ModelRunViewState
    let hasDiff: Bool
    let isShowingDiff: Bool
    let onToggleDiff: () -> Void
    let isSpeaking: Bool
    let onSpeak: () -> Void
    let onStopSpeaking: () -> Void
    let onCopy: (String) -> Void
    let onReplace: ((String) -> Void)?
    let onChat: (() -> Void)?

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        switch run.status {
        case .idle, .running:
            SkeletonPlaceholder()

        case let .streaming(text, _):
            if text.isEmpty {
                SkeletonPlaceholder()
            } else {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(colors.textPrimary)
                    .textSelection(.enabled)
            }

        case let .streamingSentencePairs(pairs, _):
            if pairs.isEmpty {
                SkeletonPlaceholder()
            } else {
                SentencePairsView(pairs: pairs)
            }

        case let .success(text, copyText, _, diff, supplementalTexts, sentencePairs):
            successContent(
                text: text,
                copyText: copyText,
                diff: diff,
                supplementalTexts: supplementalTexts,
                sentencePairs: sentencePairs
            )

        case let .failure(message, _, responseBody):
            failureContent(message: message, responseBody: responseBody)
        }
    }

    @ViewBuilder
    private func failureContent(message: String, responseBody: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Request Failed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colors.error)

                if responseBody != nil {
                    errorDetailsButton(responseBody: responseBody!)
                }
            }
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(colors.textSecondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func errorDetailsButton(responseBody: String) -> some View {
        #if os(macOS)
            Button {
                showingErrorDetails.toggle()
            } label: {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundColor(colors.error)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingErrorDetails) {
                ErrorDetailsPopover(responseBody: responseBody)
            }
        #else
            Button {
                showingErrorDetails = true
            } label: {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundColor(colors.error)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingErrorDetails) {
                ErrorDetailsSheet(responseBody: responseBody)
            }
        #endif
    }

    @ViewBuilder
    private func successContent(
        text: String,
        copyText: String,
        diff: TextDiffBuilder.Presentation?,
        supplementalTexts: [String],
        sentencePairs: [SentencePair]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !sentencePairs.isEmpty {
                SentencePairsView(pairs: sentencePairs)
            } else if let diff, isShowingDiff {
                DiffView(diff: diff)
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
                    ResultActionButtons(
                        copyText: copyText,
                        showDiffToggle: true,
                        hasDiff: hasDiff,
                        isShowingDiff: isShowingDiff,
                        onToggleDiff: onToggleDiff,
                        isSpeaking: isSpeaking,
                        onSpeak: onSpeak,
                        onStopSpeaking: onStopSpeaking,
                        onCopy: onCopy,
                        onReplace: onReplace,
                        onChat: onChat
                    )
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
    }
}

// MARK: - Result Bottom Info Bar

/// Displays status information and action buttons at the bottom of a result card
struct ResultBottomInfoBar: View {
    @Environment(\.colorScheme) private var colorScheme

    let run: HomeViewModel.ModelRunViewState
    let showModelName: Bool
    let hasDiff: Bool
    let isShowingDiff: Bool
    let onToggleDiff: () -> Void
    let isSpeaking: Bool
    let onSpeak: () -> Void
    let onStopSpeaking: () -> Void
    let onRetry: () -> Void
    let onCopy: (String) -> Void
    let onReplace: ((String) -> Void)?
    let onChat: (() -> Void)?

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        switch run.status {
        case .idle, .running:
            processingBar

        case let .streaming(_, start):
            streamingBar(statusText: "Generating...", start: start)

        case let .streamingSentencePairs(_, start):
            streamingBar(statusText: "Translating...", start: start)

        case let .success(_, copyText, _, _, supplementalTexts, sentencePairs):
            successBar(copyText: copyText, supplementalTexts: supplementalTexts, sentencePairs: sentencePairs)

        case .failure:
            failureBar
        }
    }

    private var processingBar: some View {
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
    }

    private func streamingBar(statusText: String, start: Date) -> some View {
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
            Text(statusText)
                .font(.system(size: 12))
                .foregroundColor(colors.textSecondary)
            Spacer()
            LiveTimer(start: start)
        }
    }

    private func successBar(copyText: String, supplementalTexts: [String], sentencePairs: [SentencePair]) -> some View {
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

            // Action buttons (only for plain text mode without supplementalTexts)
            if sentencePairs.isEmpty && supplementalTexts.isEmpty {
                ResultActionButtons(
                    copyText: copyText,
                    showDiffToggle: true,
                    hasDiff: hasDiff,
                    isShowingDiff: isShowingDiff,
                    onToggleDiff: onToggleDiff,
                    isSpeaking: isSpeaking,
                    onSpeak: onSpeak,
                    onStopSpeaking: onStopSpeaking,
                    onCopy: onCopy,
                    onReplace: onReplace,
                    onChat: onChat
                )
            }
        }
    }

    private var failureBar: some View {
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
                onRetry()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colors.accent)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Result Action Buttons

/// A group of action buttons for result cards (diff toggle, speak, copy, replace)
struct ResultActionButtons: View {
    @Environment(\.colorScheme) private var colorScheme

    let copyText: String
    let showDiffToggle: Bool
    let hasDiff: Bool
    let isShowingDiff: Bool
    let onToggleDiff: () -> Void
    let isSpeaking: Bool
    let onSpeak: () -> Void
    let onStopSpeaking: () -> Void
    let onCopy: (String) -> Void
    let onReplace: ((String) -> Void)?
    let onChat: (() -> Void)?

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        Group {
            if showDiffToggle {
                DiffToggleButton(hasDiff: hasDiff, isShowingDiff: isShowingDiff, onToggle: onToggleDiff)
            }
            SpeakButton(isSpeaking: isSpeaking, onSpeak: onSpeak, onStop: onStopSpeaking)
            CopyButton(text: copyText, onCopy: onCopy)
            if let onReplace {
                ReplaceButton(text: copyText, onReplace: onReplace)
            }
            if let onChat {
                ContinueChatButton(onChat: onChat)
            }
        }
    }
}

// MARK: - Atomic Button Components

/// Toggle button for showing/hiding diff view
struct DiffToggleButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let hasDiff: Bool
    let isShowingDiff: Bool
    let onToggle: () -> Void

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        if hasDiff {
            Button {
                onToggle()
            } label: {
                Image(systemName: isShowingDiff ? "eye.slash" : "eye")
                    .font(.system(size: 13))
                    .foregroundColor(colors.accent)
            }
            .buttonStyle(.plain)
            .help(isShowingDiff ? "Hide changes" : "Show changes")
        }
    }
}

/// Button for copying text to clipboard
struct CopyButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let onCopy: (String) -> Void

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        Button {
            onCopy(text)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 13))
                .foregroundColor(colors.accent)
        }
        .buttonStyle(.plain)
    }
}

/// Button for opening continue-conversation chat
struct ContinueChatButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let onChat: () -> Void

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        Button {
            onChat()
        } label: {
            Image(systemName: "text.bubble")
                .font(.system(size: 13))
                .foregroundColor(colors.accent)
        }
        .buttonStyle(.plain)
        .help("Continue conversation")
    }
}

/// Button for replacing selected text (iOS extension only)
struct ReplaceButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let onReplace: (String) -> Void

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        Button {
            onReplace(text)
        } label: {
            Label("Replace", systemImage: "arrow.left.arrow.right")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundColor(colors.accent)
    }
}

/// Button for speaking text aloud via TTS
struct SpeakButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let isSpeaking: Bool
    let onSpeak: () -> Void
    let onStop: () -> Void

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        Button {
            if isSpeaking {
                onStop()
            } else {
                onSpeak()
            }
        } label: {
            Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                .font(.system(size: 13))
                .foregroundColor(isSpeaking ? colors.error : colors.accent)
        }
        .buttonStyle(.plain)
        .help(isSpeaking ? "Stop speaking" : "Speak text")
    }
}

// MARK: - Shared UI Components

/// Displays a live updating timer
struct LiveTimer: View {
    @Environment(\.colorScheme) private var colorScheme

    let start: Date

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        TimelineView(.periodic(from: start, by: 1.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Text(String(format: "%.0fs", elapsed))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(colors.textSecondary)
        }
    }
}

/// Skeleton loading placeholder
struct SkeletonPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0 ..< 2, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(colors.skeleton)
                    .frame(height: 8)
                    .frame(maxWidth: index == 1 ? 120 : .infinity)
            }
        }
    }
}

/// Displays sentence pairs (original + translation)
struct SentencePairsView: View {
    @Environment(\.colorScheme) private var colorScheme

    let pairs: [SentencePair]

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
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
}

/// Displays diff view with highlighted changes
struct DiffView: View {
    @Environment(\.colorScheme) private var colorScheme

    let diff: TextDiffBuilder.Presentation

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
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
}

// MARK: - Error Details Views

#if os(macOS)
    struct ErrorDetailsPopover: View {
        @Environment(\.colorScheme) private var colorScheme
        let responseBody: String

        private var colors: AppColorPalette {
            AppColors.palette(for: colorScheme)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Error Details")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.textPrimary)

                ScrollView {
                    Text(responseBody)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(colors.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .frame(width: 400, height: 300)
        }
    }
#else
    struct ErrorDetailsSheet: View {
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.dismiss) private var dismiss
        let responseBody: String

        private var colors: AppColorPalette {
            AppColors.palette(for: colorScheme)
        }

        var body: some View {
            NavigationStack {
                ScrollView {
                    Text(responseBody)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(colors.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .navigationTitle("Error Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
#endif
