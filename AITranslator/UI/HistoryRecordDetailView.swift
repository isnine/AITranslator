//
//  HistoryRecordDetailView.swift
//  TLingo
//

import ShareCore
import SwiftUI

struct HistoryRecordDetailView: View {
    let record: TranslationRecord

    @Environment(\.colorScheme) private var colorScheme

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sourceHeader
                ForEach(record.modelResults) { result in
                    HistoryResultCard(result: result)
                }
            }
            .padding(20)
        }
        .background(colors.background.ignoresSafeArea())
    }

    private var sourceHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.sourceText)
                .font(.system(size: 16))
                .foregroundColor(colors.textPrimary)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                if !record.actionName.isEmpty {
                    MetadataChipView(record.actionName, icon: "bolt.fill")
                }
                if record.isConversation {
                    MetadataChipView("Chat", icon: "bubble.left.and.bubble.right.fill")
                }
                Spacer()
                Text(record.timestamp, style: .date)
                    .font(.system(size: 12))
                    .foregroundColor(colors.textSecondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.cardBackground)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 12,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(colors.accent.opacity(0.6))
            .frame(width: 3)
        }
    }
}

// MARK: - Result Card

private struct HistoryResultCard: View {
    let result: ModelResult

    @Environment(\.colorScheme) private var colorScheme
    @State private var showingInfo = false

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    private var durationText: String? {
        guard result.duration > 0 else { return nil }
        return String(format: "%.1fs", result.duration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(result.resultText)
                .font(.system(size: 14))
                .foregroundColor(colors.textPrimary)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(colors.success)
                        .font(.system(size: 14))

                    if let duration = durationText {
                        Text(duration)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                    }

                    Text(result.modelDisplayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.textSecondary)

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingInfo.toggle()
                        }
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                            .foregroundColor(colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    PasteboardHelper.copy(result.resultText)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundColor(colors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.cardBackground)
        )
        .overlay(alignment: .topTrailing) {
            if showingInfo {
                infoPopover
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showingInfo)
    }

    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.modelDisplayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colors.textPrimary)
            if let duration = durationText {
                Text(String(format: NSLocalizedString("Duration: %@", comment: "Provider run duration"), duration))
                    .font(.system(size: 12))
                    .foregroundColor(colors.textSecondary)
            }
        }
        .fixedSize()
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colors.cardBackground)
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
        )
        .padding(.top, 8)
        .padding(.trailing, 8)
        .onTapGesture {
            withAnimation { showingInfo = false }
        }
    }
}
