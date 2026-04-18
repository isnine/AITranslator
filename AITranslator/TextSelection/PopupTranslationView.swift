//
//  PopupTranslationView.swift
//  TLingo
//
//  Compact SwiftUI view for text selection translation results.
//

#if os(macOS)
    import ShareCore
    import SwiftUI

    struct PopupTranslationView: View {
        @ObservedObject var viewModel: HomeViewModel
        @Environment(\.colorScheme) private var colorScheme

        private var colors: AppColorPalette {
            AppColors.Palette(colorScheme: colorScheme, accentTheme: AppPreferences.shared.accentTheme)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                headerSection

                Divider()

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.modelRuns) { run in
                            ProviderResultCardView(
                                run: run,
                                showModelName: viewModel.modelRuns.count > 1,
                                viewModel: viewModel,
                                onCopy: { text in
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                }
                            )
                        }
                    }
                    .padding(12)
                }
            }
            .frame(minWidth: 320, minHeight: 200)
            .background(colors.cardBackground)
        }

        private var headerSection: some View {
            HStack(alignment: .top, spacing: 8) {
                Text(viewModel.inputText)
                    .font(.system(size: 13))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                actionPicker
            }
            .padding(12)
        }

        private var actionPicker: some View {
            Menu {
                ForEach(viewModel.actions) { action in
                    Button {
                        guard viewModel.selectAction(action) else { return }
                        viewModel.performSelectedAction()
                    } label: {
                        if action.id == viewModel.selectedActionID {
                            Label(action.name, systemImage: "checkmark")
                        } else {
                            Text(action.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.selectedAction?.name ?? NSLocalizedString("Translate", comment: "Default action name"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(colors.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colors.chipSecondaryBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(colors.divider, lineWidth: 0.5)
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
#endif
