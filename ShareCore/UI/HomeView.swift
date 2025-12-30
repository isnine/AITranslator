//
//  HomeView.swift
//  AITranslator
//
//  Created by Zander Wang on 2025/10/19.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(TranslationUIProvider)
import TranslationUIProvider
#endif
import WebKit
import UniformTypeIdentifiers

#if canImport(TranslationUIProvider)
public typealias AppTranslationContext = TranslationUIProviderContext
#else
public typealias AppTranslationContext = Never
#endif

public struct HomeView: View {
  @Environment(\.colorScheme) private var colorScheme
  @StateObject private var viewModel: HomeViewModel
  @State private var hasTriggeredAutoRequest = false
  @State private var isInputExpanded: Bool
  @State private var showingProviderInfo: UUID?
  var openFromExtension: Bool {
    #if canImport(TranslationUIProvider)
    return context != nil
    #else
    return false
    #endif
  }
  private let context: AppTranslationContext?

  private var colors: AppColorPalette {
    AppColors.palette(for: colorScheme)
  }

  private var usageScene: ActionConfig.UsageScene {
    #if canImport(TranslationUIProvider)
    guard let context else { return .app }
    return context.allowsReplacement ? .contextEdit : .contextRead
    #else
    return .app
    #endif
  }

  private var shouldShowDefaultAppCard: Bool {
    #if os(macOS)
    return false
    #else
    return true
    #endif
  }

  private var initialContextInput: String? {
    #if canImport(TranslationUIProvider)
    guard let inputText = context?.inputText else { return nil }
    return String(inputText.characters)
    #else
    return nil
    #endif
  }

  public init(context: AppTranslationContext? = nil) {
    self.context = context
    let initialScene: ActionConfig.UsageScene
    #if canImport(TranslationUIProvider)
    if let context {
      initialScene = context.allowsReplacement ? .contextEdit : .contextRead
    } else {
      initialScene = .app
    }
    #else
    initialScene = .app
    #endif
    _viewModel = StateObject(wrappedValue: HomeViewModel(usageScene: initialScene))
    #if canImport(TranslationUIProvider)
    _isInputExpanded = State(initialValue: context == nil)
    #else
    _isInputExpanded = State(initialValue: true)
    #endif
  }

  public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
              if !openFromExtension {
                header
                if shouldShowDefaultAppCard {
                  defaultAppCard
                }
              }
                inputComposer
                actionChips
                if viewModel.providerRuns.isEmpty {
                    hintLabel
                } else {
                    providerResultsSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
        .background(colors.background.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .onAppear {
          AppPreferences.shared.refreshFromDefaults()
          viewModel.updateUsageScene(usageScene)
          #if canImport(TranslationUIProvider)
          guard openFromExtension, !hasTriggeredAutoRequest else { return }
          if let inputText = initialContextInput {
            viewModel.inputText = inputText
          }
          hasTriggeredAutoRequest = true
          viewModel.performSelectedAction()
          #endif
        }
        .onChange(of: openFromExtension) {
          viewModel.updateUsageScene(usageScene)
        }
        #if canImport(TranslationUIProvider)
        .onChange(of: context?.allowsReplacement ?? false) {
          viewModel.updateUsageScene(usageScene)
        }
        #endif
    }

    private var header: some View {
        Text("Tree²")
            .font(.system(size: 28, weight: .semibold))
            .foregroundColor(colors.textPrimary)
    }

    private var defaultAppCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(colors.accent)
                    .font(.system(size: 20))

                Text("Set Tree² Lang as the default translation app")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.textPrimary)

                Button(action: viewModel.openAppSettings) {
                    Text("Open Settings")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.cardBackground)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(colors.accent)
                        )
                }
                .buttonStyle(.plain)
            }

        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colors.cardBackground)
        )
    }

    private var inputComposer: some View {
        let isCollapsed = openFromExtension && !isInputExpanded

        return ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colors.inputBackground)

            VStack(alignment: .leading, spacing: 0) {
                if isCollapsed {
                    collapsedInputSummary
                } else {
                    expandedInputEditor
                }

                if !isCollapsed {
                    Spacer(minLength: 0)
                }
            }
            .padding(.bottom, isCollapsed ? 0 : 48)

            VStack {
                Spacer()
                HStack {
                    if openFromExtension && !isCollapsed {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isInputExpanded = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Collapse")
                                    .font(.system(size: 14, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(colors.textSecondary)
                    }

                    Spacer()

                    if !isCollapsed {
                        Button {
                            viewModel.performSelectedAction()
                        } label: {
                            HStack(spacing: 6) {
                                Text("Send")
                                    .font(.system(size: 15, weight: .semibold))
                                #if os(macOS)
                                Text("Cmd+Return")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(colors.chipPrimaryText.opacity(0.9))
                                #endif
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .foregroundColor(colors.chipPrimaryText)
                            .background(
                                Capsule()
                                    .fill(colors.accent)
                            )
                        }
                        .buttonStyle(.plain)
                        #if os(macOS)
                        .keyboardShortcut(.return, modifiers: [.command])
                        #endif
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, isCollapsed ? 0 : 12)
            }
        }
        .frame(maxWidth: .infinity)
//        .frame(minHeight: isCollapsed ? 16 : 170)
        .animation(.easeInOut(duration: 0.2), value: isInputExpanded)
    }

    private var collapsedInputSummary: some View {
        let displayText = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isInputExpanded = true
            }
        } label: {
            HStack(spacing: 12) {
                Text(displayText.isEmpty ? viewModel.inputPlaceholder : displayText)
                    .font(.system(size: 15))
                    .foregroundColor(displayText.isEmpty ? colors.textSecondary : colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedInputEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
#if !os(macOS)
                if viewModel.inputText.isEmpty {
                    Text(viewModel.inputPlaceholder)
                        .foregroundColor(colors.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }
#endif

#if os(macOS)
                AutoPasteTextEditor(
                    text: $viewModel.inputText,
                    placeholder: viewModel.inputPlaceholder
                ) { pastedText in
                    applyPastedTextIfNeeded(pastedText)
                }
                .frame(minHeight: 140, maxHeight: 160)
                .padding(12)
#elseif os(iOS)
                AutoPasteTextEditor(
                    text: $viewModel.inputText,
                    placeholder: viewModel.inputPlaceholder
                ) { pastedText in
                    applyPastedTextIfNeeded(pastedText)
                }
                .frame(minHeight: 140, maxHeight: 160)
                .padding(12)
#else
                TextEditor(text: $viewModel.inputText)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(colors.textPrimary)
                    .padding(12)
                    .frame(minHeight: 140, maxHeight: 160)
                    .onPasteCommand(of: [.plainText]) { providers in
                        handlePasteCommand(providers: providers)
                    }
#endif
            }
        }
    }

    private var actionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.actions) { action in
                    chip(for: action, isSelected: action.id == viewModel.selectedAction?.id)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(for action: ActionConfig, isSelected: Bool) -> some View {
        Button {
            if viewModel.selectAction(action) {
                viewModel.performSelectedAction()
            }
        } label: {
            Text(action.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? colors.chipPrimaryText : colors.chipSecondaryText)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? colors.chipPrimaryBackground : colors.chipSecondaryBackground)
                )
        }
        .buttonStyle(.plain)
    }

    private var hintLabel: some View {
        Text(viewModel.placeholderHint)
            .font(.system(size: 14))
            .foregroundColor(colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }

    private var providerResultsSection: some View {
        VStack(spacing: 16) {
            ForEach(viewModel.providerRuns) { run in
                providerResultCard(for: run)
            }
        }
    }

    private func providerResultCard(for run: HomeViewModel.ProviderRunViewState) -> some View {
        let providerID = run.provider.id
        return VStack(alignment: .leading, spacing: 12) {
            content(for: run)

            // Bottom info bar
            bottomInfoBar(for: run, providerID: providerID)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colors.cardBackground)
        )
        .overlay(alignment: .topTrailing) {
            if showingProviderInfo == providerID {
                providerInfoPopover(for: run)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showingProviderInfo)
    }

    @ViewBuilder
    private func bottomInfoBar(
        for run: HomeViewModel.ProviderRunViewState,
        providerID: UUID
    ) -> some View {
        switch run.status {
        case .idle, .running:
            EmptyView()

        case let .streaming(_, start):
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(colors.accent)
                Text("Generating...")
                    .font(.system(size: 13))
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
                Text("Translating...")
                    .font(.system(size: 13))
                    .foregroundColor(colors.textSecondary)
                Spacer()
                liveTimer(start: start)
            }

        case let .success(_, copyText, _, _, _, sentencePairs):
            HStack(spacing: 12) {
                // Status + Duration + Info
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(colors.success)
                        .font(.system(size: 14))

                    if let duration = run.durationText {
                        Text(duration)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                    }

                    providerInfoButton(providerID: providerID)
                }

                Spacer()

                // Action buttons
                if sentencePairs.isEmpty {
                    actionButtons(copyText: copyText, providerID: providerID)
                }
            }

        case .failure:
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(colors.error)
                        .font(.system(size: 14))

                    if let duration = run.durationText {
                        Text(duration)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                    }

                    providerInfoButton(providerID: run.provider.id)
                }

                Spacer()

                // Retry button
                Button {
                    viewModel.performSelectedAction()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func actionButtons(copyText: String, providerID: UUID) -> some View {
        #if canImport(TranslationUIProvider)
        if let context, context.allowsReplacement {
            Button {
                context.finish(translation: AttributedString(copyText))
            } label: {
                Label("Replace", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(colors.accent)

            compactSpeakButton(for: copyText, providerID: providerID)
            compactCopyButton(for: copyText)
        } else {
            compactSpeakButton(for: copyText, providerID: providerID)
            compactCopyButton(for: copyText)
        }
        #else
        compactSpeakButton(for: copyText, providerID: providerID)
        compactCopyButton(for: copyText)
        #endif
    }

    @ViewBuilder
    private func providerInfoButton(providerID: UUID) -> some View {
        Button {
            withAnimation {
                if showingProviderInfo == providerID {
                    showingProviderInfo = nil
                } else {
                    showingProviderInfo = providerID
                }
            }
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func providerInfoPopover(for run: HomeViewModel.ProviderRunViewState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(run.provider.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colors.textPrimary)
            Text(run.provider.modelName)
                .font(.system(size: 12))
                .foregroundColor(colors.textSecondary)
            if let duration = run.durationText {
                Text("Duration: \(duration)")
                    .font(.system(size: 12))
                    .foregroundColor(colors.textSecondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colors.cardBackground)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .padding(.top, 8)
        .padding(.trailing, 8)
        .onTapGesture {
            withAnimation {
                showingProviderInfo = nil
            }
        }
    }

    private func liveTimer(start: Date) -> some View {
        TimelineView(.periodic(from: start, by: 0.1)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Text(String(format: "%.1fs", elapsed))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundColor(colors.textSecondary)
        }
    }

    private func skeletonPlaceholder() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(colors.skeleton)
                    .frame(height: 10)
                    .frame(maxWidth: index == 2 ? 180 : .infinity)
                    .shimmer()
            }
        }
    }

    @ViewBuilder
    private func compactSpeakButton(for text: String, providerID: UUID) -> some View {
        let isSpeaking = viewModel.isSpeaking(providerID: providerID)
        Button {
            viewModel.speakResult(text, providerID: providerID)
        } label: {
            if isSpeaking {
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
        .disabled(isSpeaking)
    }

    @ViewBuilder
    private func compactCopyButton(for text: String) -> some View {
        Button {
            copyToPasteboard(text)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 14))
                .foregroundColor(colors.accent)
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 14))
                    .foregroundColor(colors.textPrimary)
                    .textSelection(.enabled)
            }

        case let .streamingSentencePairs(pairs, _):
            if pairs.isEmpty {
                skeletonPlaceholder()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(pair.original)
                                .font(.system(size: 14))
                                .foregroundColor(colors.textSecondary)
                                .textSelection(.enabled)
                            Text(pair.translation)
                                .font(.system(size: 14))
                                .foregroundColor(colors.textPrimary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 8)

                        if index < pairs.count - 1 {
                            Divider()
                        }
                    }
                }
            }

        case let .success(text, copyText, _, diff, supplementalTexts, sentencePairs):
            VStack(alignment: .leading, spacing: 12) {
                if !sentencePairs.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sentencePairs.enumerated()), id: \.offset) { index, pair in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(pair.original)
                                    .font(.system(size: 14))
                                    .foregroundColor(colors.textSecondary)
                                    .textSelection(.enabled)
                                Text(pair.translation)
                                    .font(.system(size: 14))
                                    .foregroundColor(colors.textPrimary)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 8)

                            if index < sentencePairs.count - 1 {
                                Divider()
                            }
                        }
                    }
                } else if let diff {
                    VStack(alignment: .leading, spacing: 8) {
                        if diff.hasRemovals {
                            let originalText = TextDiffBuilder.attributedString(
                                for: diff.originalSegments,
                                palette: colors,
                                colorScheme: colorScheme
                            )
                            Text(originalText)
                                .font(.system(size: 14))
                                .textSelection(.enabled)
                        }

                        if diff.hasAdditions || (!diff.hasRemovals && !diff.hasAdditions) {
                            let revisedText = TextDiffBuilder.attributedString(
                                for: diff.revisedSegments,
                                palette: colors,
                                colorScheme: colorScheme
                            )
                            Text(revisedText)
                                .font(.system(size: 14))
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    let mainText = !supplementalTexts.isEmpty ? copyText : text
                    Text(mainText)
                        .font(.system(size: 14))
                        .foregroundColor(colors.textPrimary)
                        .textSelection(.enabled)
                }

                if !supplementalTexts.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(supplementalTexts.enumerated()), id: \.offset) { entry in
                            Text(entry.element)
                                .font(.system(size: 14))
                                .foregroundColor(colors.textPrimary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

        case let .failure(message, _):
            VStack(alignment: .leading, spacing: 10) {
                Text("Request Failed")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colors.error)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }

    private func handlePasteCommand(providers: [NSItemProvider]) {
        if let clipboardText = readImmediatePasteboardText() {
            Task { @MainActor in
                applyPastedTextIfNeeded(clipboardText)
            }
            return
        }

        guard !providers.isEmpty else { return }

        let plainTextIdentifier = UTType.plainText.identifier

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(plainTextIdentifier) {
                provider.loadItem(forTypeIdentifier: plainTextIdentifier, options: nil) { item, _ in
                    guard let text = Self.coerceLoadedItemToString(item) else { return }
                    Task { @MainActor in
                        applyPastedTextIfNeeded(text)
                    }
                }
                return
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String else { return }
                    Task { @MainActor in
                        applyPastedTextIfNeeded(text)
                    }
                }
                return
            }
        }
    }

    private func readImmediatePasteboardText() -> String? {
        #if canImport(AppKit)
        if let text = NSPasteboard.general.string(forType: .string) {
            return text
        }
        #endif
        #if canImport(UIKit)
        if let text = UIPasteboard.general.string {
            return text
        }
        #endif
        return nil
    }

    @MainActor
    private func applyPastedTextIfNeeded(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        viewModel.inputText = text
        isInputExpanded = true
        viewModel.performSelectedAction()
    }

    private static func coerceLoadedItemToString(_ item: NSSecureCoding?) -> String? {
        switch item {
        case let data as Data:
            return String(data: data, encoding: .utf8)
        case let string as String:
            return string
        case let attributed as NSAttributedString:
            return attributed.string
        default:
            return nil
        }
    }
}

#if os(macOS)
private struct AutoPasteTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onPaste: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PastingTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.onPaste = onPaste
        textView.placeholderAttributedString = makePlaceholderAttributedString()

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PastingTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }

        textView.onPaste = onPaste
        if textView.placeholderAttributedString?.string != placeholder {
            textView.placeholderAttributedString = makePlaceholderAttributedString()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: AutoPasteTextEditor

        init(parent: AutoPasteTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let updated = textView.string
            if parent.text != updated {
                parent.text = updated
            }
        }
    }

    private func makePlaceholderAttributedString() -> NSAttributedString {
        NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
    }
}

private final class PastingTextView: NSTextView {
    var onPaste: ((String) -> Void)?
    var placeholderAttributedString: NSAttributedString? {
        didSet { needsDisplay = true }
    }

    override func paste(_ sender: Any?) {
        super.paste(sender)
        let current = string
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onPaste?(current)
        needsDisplay = true
    }

    override var isRichText: Bool {
        get { false }
        set { }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty,
              window?.firstResponder !== self,
              let placeholder = placeholderAttributedString else {
            return
        }

        let inset = textContainerInset
        let padding = textContainer?.lineFragmentPadding ?? 0
        let origin = CGPoint(
            x: inset.width + padding,
            y: bounds.height - inset.height - placeholder.size().height
        )
        placeholder.draw(at: origin)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { needsDisplay = true }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { needsDisplay = true }
        return result
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}
#elseif os(iOS)
private struct AutoPasteTextEditor: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onPaste: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PastingTextView {
        let textView = PastingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.text = text
        textView.onPaste = onPaste
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.adjustsFontForContentSizeCategory = true
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.autocorrectionType = .default
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.accessibilityHint = placeholder
        return textView
    }

    func updateUIView(_ uiView: PastingTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.onPaste = onPaste
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: AutoPasteTextEditor

        init(parent: AutoPasteTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let updated = textView.text ?? ""
            if parent.text != updated {
                parent.text = updated
            }
        }
    }
}

private final class PastingTextView: UITextView {
    var onPaste: ((String) -> Void)?

    override func paste(_ sender: Any?) {
        super.paste(sender)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let current = self.text ?? ""
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            self.onPaste?(current)
        }
    }
}
#endif

// MARK: - Shimmer Animation

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            .white.opacity(0.4),
                            .clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: -geometry.size.width * 0.3 + phase * geometry.size.width * 1.6)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

private extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

#Preview {
  HomeView(context: nil)
        .preferredColorScheme(.dark)
}
