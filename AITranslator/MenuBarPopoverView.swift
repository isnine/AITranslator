//
//  MenuBarPopoverView.swift
//  TLingo
//
//  Created by AI Assistant on 2025/12/31.
//

#if os(macOS)
import SwiftUI
import ShareCore
import Combine
import AppKit

/// A compact popover view for menu bar quick translation
struct MenuBarPopoverView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: HomeViewModel
    @ObservedObject private var hotKeyManager = HotKeyManager.shared
    @State private var inputText: String = ""
    @State private var showHotkeyHint: Bool = true
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
                headerSection
                
                Divider()
                    .background(colors.divider)
                
                inputSection
                actionChips
                
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

            if viewModel.isLoadingConfiguration {
                configurationLoadingOverlay
            }
        }
        .frame(width: 360, height: 420)
        .onReceive(NotificationCenter.default.publisher(for: .menuBarPopoverDidShow)) { _ in
            viewModel.refreshConfiguration()
            loadClipboardAndExecute()
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
        let clipboardContent = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasRecentClipboard = ClipboardMonitor.shared.hasRecentContent(within: 5)
        
        if hasRecentClipboard && !clipboardContent.isEmpty {
            inputText = clipboardContent
            viewModel.inputText = inputText
            viewModel.performSelectedAction()
        } else if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputText = clipboardContent
        }
    }
    
    private func executeTranslation() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        viewModel.inputText = trimmedText
        viewModel.performSelectedAction()
    }
    
    // MARK: - Header Section
    
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
    
    // MARK: - Input Section
    
    private var inputSection: some View {
        VStack(spacing: 8) {
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
            
            HStack(spacing: 8) {
                Text("\(inputText.count) characters")
                    .font(.system(size: 11))
                    .foregroundColor(colors.textSecondary.opacity(0.7))
                
                Spacer()
                
                if AppPreferences.shared.ttsConfiguration.isValid && !inputText.isEmpty {
                    inputSpeakButton
                }
                
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
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(text, forType: .string)
                        }
                    )
                }
            }
        }
    }
}
#endif
