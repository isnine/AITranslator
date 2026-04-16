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
                // Header with source text
                headerSection

                Divider()

                // Results
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
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.inputText)
                    .font(.system(size: 13))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            .padding(12)
        }
    }
#endif
