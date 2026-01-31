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
        @State private var isLanguagePickerPresented: Bool = false
        @State private var targetLanguageCode: String = AppPreferences.shared.targetLanguage.rawValue

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

                    if !viewModel.modelRuns.isEmpty {
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
            // When the user changes the selection in the host app, the system may reuse the same
            // extension instance and only update the context's selected text. We need to re-run the
            // currently selected action so results update immediately (without requiring the user to
            // switch actions back-and-forth).
            .onChange(of: inputText) {
                guard hasTriggeredAutoRequest else { return }
                // Avoid redundant requests.
                guard viewModel.inputText != inputText else { return }

                viewModel.inputText = inputText
                if !inputText.isEmpty {
                    viewModel.performSelectedAction()
                }
            }
            .onChange(of: context.allowsReplacement) {
                viewModel.updateUsageScene(usageScene)
            }
            .sheet(isPresented: $isLanguagePickerPresented) {
                LanguagePickerView(
                    selectedCode: $targetLanguageCode,
                    isPresented: $isLanguagePickerPresented
                )
            }
            .onChange(of: targetLanguageCode) {
                let option = TargetLanguageOption(rawValue: targetLanguageCode) ?? .appLanguage
                AppPreferences.shared.setTargetLanguage(option)
                viewModel.refreshConfiguration()
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

                targetLanguageIndicator

                if AppPreferences.shared.ttsConfiguration.isValid && !inputText.isEmpty {
                    inputSpeakButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selectedTextPreviewBackground)
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

        private var targetLanguageIndicator: some View {
            let option = TargetLanguageOption(rawValue: targetLanguageCode) ?? .appLanguage
            let displayName: String = {
                if option == .appLanguage {
                    return TargetLanguageOption.appLanguageEnglishName
                } else {
                    return option.primaryLabel
                }
            }()

            return TargetLanguageButton(
                title: displayName,
                action: { isLanguagePickerPresented = true },
                foregroundColor: colors.textSecondary.opacity(0.7),
                spacing: 4,
                globeFont: .system(size: 10),
                textFont: .system(size: 11),
                chevronSystemName: "chevron.up.chevron.down",
                chevronFont: .system(size: 8)
            )
        }

        // MARK: - Action Chips

        private var actionChips: some View {
            ActionChipsView(
                actions: viewModel.actions,
                selectedActionID: viewModel.selectedAction?.id,
                spacing: 8,
                font: .system(size: 13, weight: .medium),
                // NOTE: In the iOS Translation UI extension we render chips using a glassEffect
                // background (not a solid accent fill). Using white text (chipPrimaryText) makes the
                // selected action illegible in Light Mode with Liquid Glass.
                textColor: { isSelected in
                    isSelected ? colors.textPrimary : colors.textSecondary
                },
                background: { isSelected in
                    AnyView(chipBackground(isSelected: isSelected))
                },
                horizontalPadding: 14,
                verticalPadding: 8
            ) { action in
                if viewModel.selectAction(action) {
                    viewModel.performSelectedAction()
                }
            }
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
            let showModelName = viewModel.modelRuns.count > 1
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.modelRuns) { run in
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
            LoadingOverlay(
                backgroundColor: Color(UIColor.systemBackground).opacity(0.95),
                messageFont: .system(size: 13),
                textColor: colors.textSecondary,
                accentColor: colors.accent
            )
        }

        // MARK: - Liquid Glass Backgrounds

        @ViewBuilder
        private var selectedTextPreviewBackground: some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 8))
        }

        @ViewBuilder
        private func chipBackground(isSelected: Bool) -> some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.clear)
                .glassEffect(isSelected ? .regular : .regular.interactive(), in: .rect(cornerRadius: 8))
        }
    }
#endif
